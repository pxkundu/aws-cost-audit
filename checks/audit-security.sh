#!/bin/bash

source ../lib/helpers.sh
source ../lib/report_helpers.sh
source ../settings.sh

# Constants
MAX_RETRIES=3
RETRY_DELAY=2
TIMEOUT=30
MAX_INGRESS_RULES=50
MAX_EGRESS_RULES=50
KMS_KEY_AGE_DAYS=365
CLOUDTRAIL_RETENTION_DAYS=90
VPC_FLOW_LOGS_RETENTION_DAYS=30
ERROR_LOG_FILE="reports/security_audit_errors_$(date +%Y%m%d_%H%M%S).log"
AUDIT_STATE_FILE="reports/security_audit_state_$(date +%Y%m%d_%H%M%S).json"
FINDINGS_FILE="reports/security_findings_$(date +%Y%m%d_%H%M%S).txt"
FINAL_REPORT="reports/security_audit_report_$(date +%Y%m%d_%H%M%S).md"

# Function to handle script termination
cleanup_and_exit() {
    local exit_code=$1
    local error_message=$2
    
    # Log the error if provided
    if [ -n "$error_message" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $error_message" >> "$ERROR_LOG_FILE"
        display_error "🚨 $error_message"
    fi
    
    # Cleanup temporary files
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
    
    # Save audit state if we have partial results
    if [ ${#AUDIT_RESULTS[@]} -gt 0 ]; then
        echo "${AUDIT_RESULTS[@]}" | jq -s '.' > "$AUDIT_STATE_FILE"
        display_info "💾 Partial audit results saved to $AUDIT_STATE_FILE"
    fi
    
    exit $exit_code
}

# Set up trap for script termination
trap 'cleanup_and_exit 1 "Script terminated unexpectedly"' SIGINT SIGTERM

# Function to make AWS API calls with enhanced retry mechanism
aws_api_call() {
    local command="$1"
    local retry_count=0
    local output=""
    local last_error=""
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Use timeout to prevent hanging
        output=$(timeout $TIMEOUT aws $command 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            # Validate JSON output if the command should return JSON
            if [[ "$command" =~ "describe"|"list"|"get" ]]; then
                if ! echo "$output" | jq . >/dev/null 2>&1; then
                    last_error="Invalid JSON response"
                    retry_count=$((retry_count + 1))
                    [ $retry_count -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
                    continue
                fi
            fi
            echo "$output"
            return 0
        elif [ $exit_code -eq 124 ]; then
            last_error="Command timed out after ${TIMEOUT}s"
            display_warning "⚠️ AWS API call timed out. Retrying... (Attempt $((retry_count + 1))/$MAX_RETRIES)"
        else
            last_error="$output"
            display_warning "⚠️ AWS API call failed. Retrying... (Attempt $((retry_count + 1))/$MAX_RETRIES)"
        fi
        
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
    done
    
    # Log the error with timestamp and command
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: AWS API call failed after $MAX_RETRIES attempts" >> "$ERROR_LOG_FILE"
    echo "Command: $command" >> "$ERROR_LOG_FILE"
    echo "Last Error: $last_error" >> "$ERROR_LOG_FILE"
    echo "----------------------------------------" >> "$ERROR_LOG_FILE"
    
    display_error "🚨 AWS API call failed after $MAX_RETRIES attempts"
    return 1
}

# Function to validate AWS credentials and permissions
validate_aws_credentials() {
    display_info "🔍 Validating AWS credentials and permissions..."
    
    # Check if we can get caller identity
    local identity=$(aws_api_call "sts get-caller-identity")
    if [ $? -ne 0 ]; then
        cleanup_and_exit 1 "Failed to validate AWS credentials"
    fi
    
    # Check required permissions
    local required_permissions=(
        "iam:ListUsers"
        "iam:ListAccessKeys"
        "iam:ListUserPolicies"
        "iam:ListRoles"
        "iam:GetRole"
        "ec2:DescribeSecurityGroups"
        "ec2:DescribeVpcs"
        "ec2:DescribeFlowLogs"
        "ec2:DescribeVpcEndpoints"
        "ec2:DescribeVpcPeeringConnections"
        "s3:ListBuckets"
        "s3:GetBucketPolicy"
        "s3:GetBucketAcl"
        "s3:GetBucketEncryption"
        "cloudtrail:ListTrails"
        "cloudtrail:GetTrail"
        "cloudtrail:GetTrailStatus"
        "kms:ListKeys"
        "kms:DescribeKey"
        "kms:GetKeyRotationStatus"
        "logs:DescribeLogGroups"
    )
    
    local missing_permissions=()
    for permission in "${required_permissions[@]}"; do
        if ! aws_api_call "iam simulate-principal-policy --policy-source-arn arn:aws:iam::$(echo "$identity" | jq -r '.Account'):user/$(echo "$identity" | jq -r '.Arn' | cut -d'/' -f2) --action-names $permission" | jq -e '.EvaluationResults[].EvalDecision == "allowed"' >/dev/null 2>&1; then
            missing_permissions+=("$permission")
        fi
    done
    
    if [ ${#missing_permissions[@]} -gt 0 ]; then
        display_error "🚨 Missing required permissions:"
        printf '%s\n' "${missing_permissions[@]}" | while read -r perm; do
            display_error "   - $perm"
        done
        cleanup_and_exit 1 "Insufficient AWS permissions"
    fi
    
    display_info "✅ AWS credentials and permissions validated"
}

# Function to check AWS service health
check_aws_services() {
    display_info "🔍 Checking AWS service health..."
    
    local services=("iam" "ec2" "s3" "cloudtrail" "kms" "logs")
    local unhealthy_services=()
    
    for service in "${services[@]}"; do
        if ! aws_api_call "$service describe-account-attributes" >/dev/null 2>&1; then
            unhealthy_services+=("$service")
        fi
    done
    
    if [ ${#unhealthy_services[@]} -gt 0 ]; then
        display_warning "⚠️ Unhealthy AWS services detected:"
        printf '%s\n' "${unhealthy_services[@]}" | while read -r service; do
            display_warning "   - $service"
        done
        return 1
    fi
    
    display_info "✅ AWS services are healthy"
    return 0
}

# Function to handle partial results
handle_partial_results() {
    local check_name=$1
    local status=$2
    local message=$3
    
    AUDIT_RESULTS+=("{\"check\":\"$check_name\",\"status\":\"$status\",\"message\":\"$message\",\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}")
    
    # Save state after each check
    echo "${AUDIT_RESULTS[@]}" | jq -s '.' > "$AUDIT_STATE_FILE"
}

# Initialize audit results array
declare -a AUDIT_RESULTS

# Function to log finding with severity
log_finding() {
    local category=$1
    local severity=$2
    local message=$3
    
    echo "[$category] $severity: $message" >> "$FINDINGS_FILE"
    format_finding "$severity" "$message"
}

# Main audit function with enhanced error handling
audit_security() {
    display_info "🔎 Running security audit..."
    
    # Create temporary directory for data
    temp_dir=$(create_temp_dir)
    if [ $? -ne 0 ]; then
        cleanup_and_exit 1 "Failed to create temporary directory"
    fi
    
    # Initialize findings file
    echo -e "# Security Audit Findings\n" > "$FINDINGS_FILE"
    echo -e "Generated on: $(date '+%Y-%m-%d %H:%M:%S')\n" >> "$FINDINGS_FILE"
    
    # Validate AWS environment
    validate_aws_credentials
    check_aws_services
    
    # Run audits with error handling and progress tracking
    local checks=(
        "audit_iam_permissions:IAM Permissions"
        "audit_security_groups:Security Groups"
        "audit_s3_security:S3 Security"
        "audit_cloudtrail:CloudTrail"
        "audit_kms_keys:KMS Keys"
        "audit_vpc_security:VPC Security"
        "audit_iam_password_policy:IAM Password Policy"
    )
    
    local total_checks=${#checks[@]}
    local current_check=0
    
    for check in "${checks[@]}"; do
        current_check=$((current_check + 1))
        local func_name=$(echo "$check" | cut -d':' -f1)
        local check_name=$(echo "$check" | cut -d':' -f2)
        
        display_info "🔍 Running $check_name check..."
        generate_progress_bar $current_check $total_checks
        
        if ! $func_name; then
            handle_partial_results "$check_name" "ERROR" "Check failed"
            log_finding "$check_name" "ERROR" "Check failed"
            display_error "🚨 $check_name check failed"
        else
            handle_partial_results "$check_name" "SUCCESS" "Check completed successfully"
            log_finding "$check_name" "SUCCESS" "Check completed successfully"
            display_info "✅ $check_name check completed"
        fi
    done
    
    # Generate final report
    generate_final_report "$FINDINGS_FILE" "$FINAL_REPORT"
    
    # Cleanup
    cleanup "$temp_dir"
    
    display_info "✅ Security audit completed"
    display_info "📄 Final report generated: $FINAL_REPORT"
    return 0
}

# Update the audit functions to use new logging
audit_iam_permissions() {
    display_info "🔍 Auditing IAM permissions..."
    
    # Get IAM users
    local users=$(aws_api_call "iam list-users")
    if [ $? -ne 0 ]; then
        log_finding "IAM" "ERROR" "Failed to retrieve IAM users"
        return 1
    fi
    
    # Process each user
    echo "$users" | jq -c '.Users[]' | while read -r user; do
        local username=$(echo "$user" | jq -r '.UserName')
        
        # Check for access keys
        local access_keys=$(aws_api_call "iam list-access-keys --user-name $username")
        if [ $? -eq 0 ]; then
            local key_count=$(echo "$access_keys" | jq '.AccessKeyMetadata | length')
            if [ "$key_count" -gt 1 ]; then
                log_finding "IAM" "HIGH" "User $username has multiple access keys"
            fi
            
            # Check for old access keys
            echo "$access_keys" | jq -c '.AccessKeyMetadata[]' | while read -r key; do
                local key_id=$(echo "$key" | jq -r '.AccessKeyId')
                local create_date=$(echo "$key" | jq -r '.CreateDate')
                local key_age=$(( $(date +%s) - $(date -d "$create_date" +%s) ))
                local key_age_days=$(( key_age / 86400 ))
                
                if [ $key_age_days -gt 90 ]; then
                    log_finding "IAM" "MEDIUM" "Access key $key_id for user $username is $key_age_days days old"
                fi
            done
        fi
    done
    
    return 0
}

# Execute the audit
audit_security
exit_code=$?

# Update summary file with overall status
if [ $exit_code -eq 0 ]; then
    echo "✅ Security audit completed successfully" >> "$SUMMARY_FILE"
else
    echo "🚨 Security audit encountered errors" >> "$SUMMARY_FILE"
fi

exit $exit_code 