#!/bin/bash

source ../lib/helpers.sh
source ../settings.sh

# Constants
MAX_RETRIES=3
RETRY_DELAY=2
TIMEOUT=30
MIN_INSTANCE_HOURS=720  # 30 days of continuous usage
SPOT_DISCOUNT_THRESHOLD=70  # Minimum discount percentage to recommend Spot

# Function to make AWS API calls with retry mechanism
aws_api_call() {
    local command="$1"
    local retry_count=0
    local output=""
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        output=$(timeout $TIMEOUT aws $command 2>&1)
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "$output"
            return 0
        elif [ $exit_code -eq 124 ]; then
            display_warning "⚠️ AWS API call timed out. Retrying... (Attempt $((retry_count + 1))/$MAX_RETRIES)"
        else
            display_warning "⚠️ AWS API call failed. Retrying... (Attempt $((retry_count + 1))/$MAX_RETRIES)"
        fi
        
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
    done
    
    display_error "🚨 AWS API call failed after $MAX_RETRIES attempts"
    return 1
}

# Function to analyze Reserved Instance opportunities
analyze_ri_opportunities() {
    display_info "🔍 Analyzing Reserved Instance opportunities..."
    
    # Get current EC2 instances
    local instances=$(aws_api_call "ec2 describe-instances --filters 'Name=instance-state-name,Values=running' --query 'Reservations[].Instances[]'")
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to retrieve EC2 instances"
        return 1
    fi
    
    # Get current RIs
    local ris=$(aws_api_call "ec2 describe-reserved-instances --filters 'Name=state,Values=active'")
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to retrieve Reserved Instances"
        return 1
    fi
    
    # Process each instance
    echo "$instances" | jq -c '.[]' | while read -r instance; do
        local instance_id=$(echo "$instance" | jq -r '.InstanceId')
        local instance_type=$(echo "$instance" | jq -r '.InstanceType')
        local launch_time=$(echo "$instance" | jq -r '.LaunchTime')
        
        # Calculate instance age
        local instance_age=$(( $(date +%s) - $(date -d "$launch_time" +%s) ))
        local instance_hours=$(( instance_age / 3600 ))
        
        if [ $instance_hours -ge $MIN_INSTANCE_HOURS ]; then
            # Check if instance is already covered by RI
            local is_covered=$(echo "$ris" | jq --arg type "$instance_type" '.ReservedInstances[] | select(.InstanceType == $type and .State == "active")')
            
            if [ -z "$is_covered" ]; then
                # Get RI recommendations
                local recommendations=$(aws_api_call "ce get-reservation-recommendations --service AmazonEC2 --lookback-period-in-days 30")
                if [ $? -eq 0 ]; then
                    local savings=$(echo "$recommendations" | jq --arg type "$instance_type" '.Recommendations[] | select(.InstanceType == $type) | .EstimatedSavingsAmount')
                    if [ -n "$savings" ] && [ "$savings" != "null" ]; then
                        display_warning "⚠️ RI Opportunity: Instance $instance_id ($instance_type) could save $(format_currency $savings) with Reserved Instance"
                        echo "WARNING: RI Opportunity for $instance_id ($instance_type) - Potential savings: $(format_currency $savings)" >> "$SUMMARY_FILE"
                    fi
                fi
            fi
        fi
    done
}

# Function to analyze Spot Instance opportunities
analyze_spot_opportunities() {
    display_info "🔍 Analyzing Spot Instance opportunities..."
    
    # Get current EC2 instances
    local instances=$(aws_api_call "ec2 describe-instances --filters 'Name=instance-state-name,Values=running' --query 'Reservations[].Instances[]'")
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to retrieve EC2 instances"
        return 1
    fi
    
    # Process each instance
    echo "$instances" | jq -c '.[]' | while read -r instance; do
        local instance_id=$(echo "$instance" | jq -r '.InstanceId')
        local instance_type=$(echo "$instance" | jq -r '.InstanceType')
        local platform=$(echo "$instance" | jq -r '.Platform // "linux"')
        
        # Get Spot price history
        local spot_prices=$(aws_api_call "ec2 describe-spot-price-history --instance-types $instance_type --product-descriptions $platform --start-time $(date -d "7 days ago" +%Y-%m-%dT%H:%M:%S)")
        if [ $? -eq 0 ]; then
            local on_demand_price=$(aws_api_call "ec2 describe-spot-price-history --instance-types $instance_type --product-descriptions $platform --start-time $(date +%Y-%m-%dT%H:%M:%S) --end-time $(date +%Y-%m-%dT%H:%M:%S)" | jq -r '.SpotPriceHistory[0].SpotPrice')
            local avg_spot_price=$(echo "$spot_prices" | jq -r '[.SpotPriceHistory[].SpotPrice | tonumber] | add / length')
            
            if [ -n "$on_demand_price" ] && [ -n "$avg_spot_price" ]; then
                local discount_percentage=$(echo "scale=2; (($on_demand_price - $avg_spot_price) / $on_demand_price) * 100" | bc)
                
                if (( $(echo "$discount_percentage >= $SPOT_DISCOUNT_THRESHOLD" | bc -l) )); then
                    display_warning "⚠️ Spot Opportunity: Instance $instance_id ($instance_type) could save $discount_percentage% with Spot Instance"
                    echo "WARNING: Spot Opportunity for $instance_id ($instance_type) - Potential savings: $discount_percentage%" >> "$SUMMARY_FILE"
                fi
            fi
        fi
    done
}

# Function to analyze instance utilization
analyze_instance_utilization() {
    display_info "🔍 Analyzing instance utilization..."
    
    # Get CloudWatch metrics for the last 14 days
    local end_time=$(date +%Y-%m-%dT%H:%M:%S)
    local start_time=$(date -d "14 days ago" +%Y-%m-%dT%H:%M:%S)
    
    # Get current EC2 instances
    local instances=$(aws_api_call "ec2 describe-instances --filters 'Name=instance-state-name,Values=running' --query 'Reservations[].Instances[]'")
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to retrieve EC2 instances"
        return 1
    fi
    
    # Process each instance
    echo "$instances" | jq -c '.[]' | while read -r instance; do
        local instance_id=$(echo "$instance" | jq -r '.InstanceId')
        local instance_type=$(echo "$instance" | jq -r '.InstanceType')
        
        # Get CPU utilization
        local cpu_metrics=$(aws_api_call "cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=$instance_id --start-time $start_time --end-time $end_time --period 86400 --statistics Average")
        if [ $? -eq 0 ]; then
            local avg_cpu=$(echo "$cpu_metrics" | jq -r '[.Datapoints[].Average] | add / length')
            
            if [ -n "$avg_cpu" ] && [ "$avg_cpu" != "null" ]; then
                if (( $(echo "$avg_cpu < 20" | bc -l) )); then
                    display_warning "⚠️ Low Utilization: Instance $instance_id ($instance_type) has average CPU utilization of ${avg_cpu}%"
                    echo "WARNING: Low CPU utilization for $instance_id ($instance_type) - Average: ${avg_cpu}%" >> "$SUMMARY_FILE"
                fi
            fi
        fi
    done
}

# Main audit function
audit_instance_optimization() {
    display_info "🔎 Running instance optimization audit..."
    
    # Create temporary directory for data
    local temp_dir=$(create_temp_dir)
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to create temporary directory"
        return 1
    fi
    
    # Run analyses
    analyze_ri_opportunities
    analyze_spot_opportunities
    analyze_instance_utilization
    
    # Cleanup
    cleanup "$temp_dir"
    
    display_info "✅ Instance optimization audit completed"
    return 0
}

# Execute the audit
audit_instance_optimization
exit_code=$?

# Update summary file with overall status
if [ $exit_code -eq 0 ]; then
    echo "✅ Instance optimization audit completed successfully" >> "$SUMMARY_FILE"
else
    echo "🚨 Instance optimization audit encountered errors" >> "$SUMMARY_FILE"
fi

exit $exit_code 