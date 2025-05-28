#!/bin/bash

# ASCII Art for project title
PROJECT_TITLE="
    █████╗ ██╗    ██╗███████╗    
   ██╔══██╗██║    ██║██╔════╝    
   ███████║██║ █╗ ██║███████╗       
   ██╔══██║██║███╗██║╚════██║       
   ██║  ██║╚███╔███╔╝███████║       
   ╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝      
    █████╗ ██╗   ██╗██████╗ ██╗████████╗    ████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗     
   ██╔══██╗██║   ██║██╔══██╗██║╚══██╔══╝    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║     
   ███████║██║   ██║██║  ██║██║   ██║          ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║     
   ██╔══██║██║   ██║██║  ██║██║   ██║          ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║     
   ██║  ██║╚██████╔╝██████╔╝██║   ██║          ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗
   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝   ╚═╝          ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝
"

# Function to display project title
display_project_title() {
    echo -e "\033[1;36m$PROJECT_TITLE\033[0m"
    echo -e "\033[1;33mAWS Audit Terminal - Comprehensive Security and Cost Analysis Tool\033[0m"
    echo -e "\033[1;33mVersion: 1.0.0\033[0m"
    echo -e "\033[1;33m$(date '+%Y-%m-%d %H:%M:%S')\033[0m\n"
}

# Utility functions for AWS Cost Audit

# Logging levels
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Default log level
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Timestamp function
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(get_timestamp)
    
    if [ $level -ge $LOG_LEVEL ]; then
        case $level in
            $LOG_LEVEL_DEBUG)
                echo -e "\033[0;36m🔍 [DEBUG]\033[0m $timestamp - $message"
                ;;
            $LOG_LEVEL_INFO)
                echo -e "\033[1;32m🌟 [INFO]\033[0m $timestamp - $message"
                ;;
            $LOG_LEVEL_WARN)
                echo -e "\033[1;33m⚠️ [WARNING]\033[0m $timestamp - $message"
                ;;
            $LOG_LEVEL_ERROR)
                echo -e "\033[1;31m🚨 [ERROR]\033[0m $timestamp - $message"
                ;;
        esac
    fi
}

# Display functions with logging
display_info() {
    log $LOG_LEVEL_INFO "$1"
}

display_warning() {
    log $LOG_LEVEL_WARN "$1"
}

display_error() {
    log $LOG_LEVEL_ERROR "$1"
}

display_debug() {
    log $LOG_LEVEL_DEBUG "$1"
}

# Format output based on configuration
format_output() {
    local data="$1"
    if [ "$OUTPUT_FORMAT" == "json" ]; then
        echo "$data" | jq . 2>/dev/null || echo "$data"
    else
        echo "$data"
    fi
}

# Send notification with retry mechanism
send_notification() {
    local subject="$1"
    local message="$2"
    local max_retries=3
    local retry_count=0
    
    if [ "$SEND_NOTIFICATIONS" == "true" ] && [ -n "$NOTIFY_EMAIL" ]; then
        while [ $retry_count -lt $max_retries ]; do
            aws ses send-email \
                --from "no-reply@example.com" \
                --destination "ToAddresses=$NOTIFY_EMAIL" \
                --message "Subject={Data=$subject},Body={Text={Data=$message}}" \
                --region "$REGION" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                display_info "📧 Notification sent to $NOTIFY_EMAIL"
                return 0
            else
                retry_count=$((retry_count + 1))
                if [ $retry_count -lt $max_retries ]; then
                    display_warning "⚠️ Failed to send notification. Retrying... (Attempt $retry_count/$max_retries)"
                    sleep 2
                fi
            fi
        done
        
        display_error "🚨 Failed to send notification after $max_retries attempts"
        return 1
    fi
}

# Validate AWS credentials
validate_aws_credentials() {
    local profile="$1"
    if ! aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
        display_error "🚨 Invalid AWS credentials for profile: $profile"
        return 1
    fi
    return 0
}

# Check required commands
check_required_commands() {
    local missing_commands=()
    
    for cmd in aws jq bc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        display_error "🚨 Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    return 0
}

# Create temporary directory
create_temp_dir() {
    local temp_dir=$(mktemp -d)
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to create temporary directory"
        return 1
    fi
    echo "$temp_dir"
}

# Cleanup function
cleanup() {
    local temp_dir="$1"
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
        display_debug "Cleaned up temporary directory: $temp_dir"
    fi
}

# Format currency
format_currency() {
    local amount="$1"
    printf "$%.2f" "$amount"
}

# Calculate percentage
calculate_percentage() {
    local value="$1"
    local total="$2"
    echo "scale=2; ($value / $total) * 100" | bc
}

# Validate numeric input
is_numeric() {
    local input="$1"
    [[ "$input" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# Validate date format (YYYY-MM-DD)
is_valid_date() {
    local date="$1"
    [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# Get AWS account alias
get_account_alias() {
    local profile="$1"
    aws iam list-account-aliases --profile "$profile" --query 'AccountAliases[0]' --output text 2>/dev/null || echo "Unknown"
}

# Export all functions
export -f display_info display_warning display_error display_debug
export -f format_output send_notification validate_aws_credentials
export -f check_required_commands create_temp_dir cleanup
export -f format_currency calculate_percentage is_numeric is_valid_date
export -f get_account_alias get_timestamp log
