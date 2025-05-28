#!/bin/bash

# ASCII Art for different report sections
SECURITY_HEADER="
    ███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗
    ██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝██║   ██║
    ███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║   ██║   ██║
    ╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║   ██║   ██║
    ███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║   ╚██████╔╝
    ╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝    ╚═════╝ 
"

SUMMARY_HEADER="
    ███████╗██╗   ██╗███╗   ███╗███╗   ███╗ █████╗ ██████╗ ██╗   ██╗
    ██╔════╝██║   ██║████╗ ████║████╗ ████║██╔══██╗██╔══██╗╚██╗ ██╔╝
    ███████╗██║   ██║██╔████╔██║██╔████╔██║███████║██████╔╝ ╚████╔╝ 
    ╚════██║██║   ██║██║╚██╔╝██║██║╚██╔╝██║██╔══██║██╔══██╗  ╚██╔╝  
    ███████║╚██████╔╝██║ ╚═╝ ██║██║ ╚═╝ ██║██║  ██║██║  ██║   ██║   
    ╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
"

# Emoji mapping for different severity levels
declare -A SEVERITY_EMOJIS=(
    ["CRITICAL"]="🔴"
    ["HIGH"]="🟠"
    ["MEDIUM"]="🟡"
    ["LOW"]="🟢"
    ["INFO"]="ℹ️"
    ["SUCCESS"]="✅"
    ["WARNING"]="⚠️"
    ["ERROR"]="🚨"
)

# Function to generate a progress bar
generate_progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    printf "["
    printf "%${completed}s" | tr " " "█"
    printf "%${remaining}s" | tr " " "░"
    printf "] %d%%\n" $percentage
}

# Function to format findings with emojis and colors
format_finding() {
    local severity=$1
    local message=$2
    local emoji=${SEVERITY_EMOJIS[$severity]}
    
    case $severity in
        "CRITICAL")
            echo -e "${emoji} \033[1;31m$message\033[0m"
            ;;
        "HIGH")
            echo -e "${emoji} \033[31m$message\033[0m"
            ;;
        "MEDIUM")
            echo -e "${emoji} \033[33m$message\033[0m"
            ;;
        "LOW")
            echo -e "${emoji} \033[32m$message\033[0m"
            ;;
        "INFO")
            echo -e "${emoji} \033[36m$message\033[0m"
            ;;
        *)
            echo -e "${emoji} $message"
            ;;
    esac
}

# Function to generate a summary table
generate_summary_table() {
    local findings_file=$1
    local output_file=$2
    
    echo -e "\n=== 📊 Findings Summary ===" > "$output_file"
    echo -e "| Severity | Count | Description |" >> "$output_file"
    echo -e "|----------|-------|-------------|" >> "$output_file"
    
    # Count findings by severity
    local -A severity_counts
    while IFS= read -r line; do
        if [[ $line =~ ^(CRITICAL|HIGH|MEDIUM|LOW|INFO): ]]; then
            severity=${BASH_REMATCH[1]}
            severity_counts[$severity]=$((severity_counts[$severity] + 1))
        fi
    done < "$findings_file"
    
    # Generate table rows
    for severity in "CRITICAL" "HIGH" "MEDIUM" "LOW" "INFO"; do
        count=${severity_counts[$severity]:-0}
        emoji=${SEVERITY_EMOJIS[$severity]}
        echo -e "| $emoji $severity | $count | $(get_severity_description $severity) |" >> "$output_file"
    done
}

# Function to get severity description
get_severity_description() {
    local severity=$1
    case $severity in
        "CRITICAL")
            echo "Immediate action required"
            ;;
        "HIGH")
            echo "Action required within 24 hours"
            ;;
        "MEDIUM")
            echo "Action required within a week"
            ;;
        "LOW")
            echo "Action recommended"
            ;;
        "INFO")
            echo "For information only"
            ;;
    esac
}

# Function to generate a detailed report
generate_detailed_report() {
    local findings_file=$1
    local output_file=$2
    
    echo -e "$SECURITY_HEADER" > "$output_file"
    echo -e "\n=== 🔍 Detailed Findings ===" >> "$output_file"
    echo -e "Generated on: $(date '+%Y-%m-%d %H:%M:%S')\n" >> "$output_file"
    
    # Group findings by category
    local -A category_findings
    while IFS= read -r line; do
        if [[ $line =~ ^\[(.*?)\](.*) ]]; then
            category="${BASH_REMATCH[1]}"
            finding="${BASH_REMATCH[2]}"
            category_findings[$category]+="$finding\n"
        fi
    done < "$findings_file"
    
    # Output findings by category
    for category in "${!category_findings[@]}"; do
        echo -e "\n## 📑 $category" >> "$output_file"
        echo -e "${category_findings[$category]}" >> "$output_file"
    done
}

# Function to generate a visual timeline
generate_timeline() {
    local events_file=$1
    local output_file=$2
    
    echo -e "\n=== ⏱️ Audit Timeline ===" > "$output_file"
    
    while IFS= read -r line; do
        if [[ $line =~ ^\[(.*?)\](.*) ]]; then
            timestamp="${BASH_REMATCH[1]}"
            event="${BASH_REMATCH[2]}"
            echo -e "🕒 $timestamp: $event" >> "$output_file"
        fi
    done < "$events_file"
}

# Function to generate a recommendations section
generate_recommendations() {
    local findings_file=$1
    local output_file=$2
    
    echo -e "\n=== 💡 Recommendations ===" > "$output_file"
    
    # Extract recommendations based on findings
    while IFS= read -r line; do
        if [[ $line =~ ^(CRITICAL|HIGH|MEDIUM|LOW): ]]; then
            severity="${BASH_REMATCH[1]}"
            message="${line#*: }"
            emoji=${SEVERITY_EMOJIS[$severity]}
            echo -e "$emoji $message" >> "$output_file"
            echo -e "   └─ Recommendation: $(get_recommendation "$message")" >> "$output_file"
        fi
    done < "$findings_file"
}

# Function to get recommendations based on findings
get_recommendation() {
    local finding=$1
    case "$finding" in
        *"CloudTrail"*"not enabled"*)
            echo "Enable CloudTrail logging and configure multi-region trail"
            ;;
        *"KMS key"*"not rotating"*)
            echo "Enable automatic key rotation for KMS keys"
            ;;
        *"security group"*"permissive"*)
            echo "Review and restrict security group rules to minimum required access"
            ;;
        *"S3 bucket"*"public"*)
            echo "Remove public access and enable bucket encryption"
            ;;
        *"IAM"*"password policy"*)
            echo "Implement strong password policy with rotation requirements"
            ;;
        *)
            echo "Review and address the security finding"
            ;;
    esac
}

# Function to generate a final report
generate_final_report() {
    local findings_file=$1
    local output_file=$2
    
    # Generate all report sections
    generate_summary_table "$findings_file" "${output_file}.summary"
    generate_detailed_report "$findings_file" "${output_file}.details"
    generate_timeline "$findings_file" "${output_file}.timeline"
    generate_recommendations "$findings_file" "${output_file}.recommendations"
    
    # Combine all sections
    cat "${output_file}.summary" "${output_file}.details" "${output_file}.timeline" "${output_file}.recommendations" > "$output_file"
    
    # Cleanup temporary files
    rm "${output_file}.summary" "${output_file}.details" "${output_file}.timeline" "${output_file}.recommendations"
} 