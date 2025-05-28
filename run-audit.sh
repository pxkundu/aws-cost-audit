#!/bin/bash

#####################################################################################################################
#    █████╗ ██╗    ██╗███████╗                                                                                      #
#   ██╔══██╗██║    ██║██╔════╝                                                                                      #
#   ███████║██║ █╗ ██║███████╗                                                                                      #
#   ██╔══██║██║███╗██║╚════██║                                                                                      #
#   ██║  ██║╚███╔███╔╝███████║                                                                                      #
#   ╚═╝  ╚═╝ ╚══╝╚══╝ ╚══════╝                                                                                      #
#    █████╗ ██╗   ██╗██████╗ ██╗████████╗    ████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗           #
#   ██╔══██╗██║   ██║██╔══██╗██║╚══██╔══╝    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║           #
#   ███████║██║   ██║██║  ██║██║   ██║          ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║           #
#   ██╔══██║██║   ██║██║  ██║██║   ██║          ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║           #
#   ██║  ██║╚██████╔╝██████╔╝██║   ██║          ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗      #
#   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝   ╚═╝          ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝      #
#####################################################################################################################
# AWS Audit Terminal - Comprehensive Security and Cost Analysis Tool                                                #
# Version: 1.0.0                                                                                                    #
# https://github.com/pxkundu/aws-cost-audit                                                                       #
#####################################################################################################################

# Source helper functions and settings
source lib/helpers.sh
source settings.sh

# Display project title
display_project_title

# Initialize logging
LOG_FILE="reports/audit_aws_$(date +%Y%m%d_%H%M%S).log"
SUMMARY_FILE="reports/summary_report_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee -a "$LOG_FILE") 2>&1

# Interactive AWS profile selection
display_info "🔍 Select an AWS Profile or add a new one:"
profiles=($(aws configure list-profiles))
if [ ${#profiles[@]} -eq 0 ]; then
    display_warning "⚠️ No AWS profiles found. You can add a new profile below."
    profiles=()
fi

# Add "Add new profile" option
options=("${profiles[@]}" "Add new profile")
PS3="Enter the number of the AWS profile (or select 'Add new profile'): "
select choice in "${options[@]}"; do
    if [ "$choice" == "Add new profile" ]; then
        display_info "🌟 Adding a new AWS profile..."
        read -p "Enter new profile name: " new_profile
        if [ -z "$new_profile" ]; then
            display_error "🚨 Profile name cannot be empty."
            exit 1
        fi
        read -p "Enter AWS Access Key ID: " access_key
        if [ -z "$access_key" ]; then
            display_error "🚨 Access Key ID cannot be empty."
            exit 1
        fi
        read -s -p "Enter AWS Secret Access Key: " secret_key
        echo
        if [ -z "$secret_key" ]; then
            display_error "🚨 Secret Access Key cannot be empty."
            exit 1
        fi
        read -p "Enter default region (e.g., us-east-1) [us-east-1]: " region
        region=${region:-us-east-1}

        # Configure new profile
        aws configure set aws_access_key_id "$access_key" --profile "$new_profile" 2>/dev/null
        if [ $? -ne 0 ]; then
            display_error "🚨 Failed to set Access Key ID for profile $new_profile."
            exit 1
        fi
        aws configure set aws_secret_access_key "$secret_key" --profile "$new_profile" 2>/dev/null
        if [ $? -ne 0 ]; then
            display_error "🚨 Failed to set Secret Access Key for profile $new_profile."
            exit 1
        fi
        aws configure set region "$region" --profile "$new_profile" 2>/dev/null
        if [ $? -ne 0 ]; then
            display_error "🚨 Failed to set region for profile $new_profile."
            exit 1
        fi
        export AWS_PROFILE="$new_profile"
        display_info "✅ New profile '$new_profile' created and selected."
        break
    elif [ -n "$choice" ]; then
        export AWS_PROFILE="$choice"
        display_info "✅ Selected AWS Profile: $choice"
        break
    else
        display_error "🚨 Invalid selection. Please try again."
    fi
done

# Get AWS account and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    display_error "🚨 Failed to retrieve AWS Account ID. Check AWS CLI configuration and credentials."
    exit 1
fi
REGION=$(aws configure get region --profile "$AWS_PROFILE")
if [ -z "$REGION" ]; then
    REGION="us-east-1"
    display_warning "⚠️ Region not set in AWS CLI config. Defaulting to us-east-1."
fi

# Initialize summary report
echo "🌟 AWS Cost Audit Summary - $(date +'%d-%b-%Y %H:%M:%S')" > "$SUMMARY_FILE"
echo "📛 Account: $ACCOUNT_ID | 📍 Region: $REGION | 🔑 Profile: $AWS_PROFILE" >> "$SUMMARY_FILE"
echo "==============================" >> "$SUMMARY_FILE"

display_info "🌟 AWS Cost Audit Started on $(date +'%d-%b-%Y %H:%M:%S')"
display_info "📛 Account: $ACCOUNT_ID | 📍 Region: $REGION | 🔑 Profile: $AWS_PROFILE"
display_info "=============================="

# Run checks and collect results
declare -A CHECK_RESULTS
CHECKS=(
    "audit-budgets.sh:Budget Alerts"
    "audit-instance-optimization.sh:Instance Optimization"
    "audit-security.sh:Security Audit"
    "audit-untagged.sh:Untagged Resources"
    "audit-idle-ec2.sh:Idle EC2 Instances"
    "audit-s3-lifecycle.sh:S3 Lifecycle Policies"
    "audit-old-rds.sh:Old RDS Snapshots"
    "audit-ebs-volumes.sh:Forgotten EBS Volumes"
    "audit-data-transfer.sh:Data Transfer Risks"
    "audit-on-demand.sh:On-Demand EC2 Instances"
    "audit-idle-elb.sh:Idle Load Balancers"
    "audit-unused-ami.sh:Unused AMIs"
)

for check in "${CHECKS[@]}"; do
    script=$(echo "$check" | cut -d':' -f1)
    name=$(echo "$check" | cut -d':' -f2)
    display_info "\n--- 📊 $name Check ---"
    if [ -f "./checks/$script" ]; then
        bash "./checks/$script" >> "$SUMMARY_FILE"
        if [ $? -eq 0 ]; then
            CHECK_RESULTS["$name"]="✅ Success"
        else
            CHECK_RESULTS["$name"]="⚠️ Failed"
            display_warning "⚠️ $name check encountered an issue."
        fi
    else
        display_error "🚨 Script ./checks/$script not found."
        CHECK_RESULTS["$name"]="🚨 Not Found"
    fi
done

# Generate summary
echo -e "\n=== 🌟 Summary of Findings ===" >> "$SUMMARY_FILE"
for name in "${!CHECK_RESULTS[@]}"; do
    echo "$name: ${CHECK_RESULTS[$name]}" >> "$SUMMARY_FILE"
done

display_info "\n✅ AWS Cost Audit Completed"
display_info "📄 Summary report saved to $SUMMARY_FILE"
send_notification "AWS Cost Audit Completed" "Audit completed for account $ACCOUNT_ID using profile $AWS_PROFILE. Summary report: $SUMMARY_FILE"