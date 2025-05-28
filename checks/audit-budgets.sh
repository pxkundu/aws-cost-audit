#!/bin/bash

source ../lib/helpers.sh
source ../settings.sh

# Constants
MAX_RETRIES=3
RETRY_DELAY=2
TIMEOUT=30

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

# Function to check budget alerts
check_budget_alerts() {
    local budget_name="$1"
    local budget_data="$2"
    
    # Extract budget amount and current spend
    local budget_amount=$(echo "$budget_data" | jq -r '.BudgetLimit.Amount')
    local current_spend=$(echo "$budget_data" | jq -r '.CalculatedSpend.ActualSpend.Amount')
    local forecast_spend=$(echo "$budget_data" | jq -r '.CalculatedSpend.ForecastedSpend.Amount')
    
    # Calculate percentages
    local current_percentage=$(echo "scale=2; ($current_spend / $budget_amount) * 100" | bc)
    local forecast_percentage=$(echo "scale=2; ($forecast_spend / $budget_amount) * 100" | bc)
    
    # Check thresholds
    if (( $(echo "$current_percentage >= 80" | bc -l) )); then
        display_warning "⚠️ Budget '$budget_name' is at ${current_percentage}% of limit"
        echo "WARNING: Budget '$budget_name' is at ${current_percentage}% of limit" >> "$SUMMARY_FILE"
    fi
    
    if (( $(echo "$forecast_percentage >= 100" | bc -l) )); then
        display_error "🚨 Budget '$budget_name' is forecasted to exceed limit by ${forecast_percentage}%"
        echo "ERROR: Budget '$budget_name' is forecasted to exceed limit by ${forecast_percentage}%" >> "$SUMMARY_FILE"
    fi
}

# Main audit function
audit_budgets() {
    display_info "🔎 Running budget audit..."
    
    # Get all budgets
    local budgets=$(aws_api_call "budgets describe-budgets --account-id $ACCOUNT_ID")
    if [ $? -ne 0 ]; then
        display_error "🚨 Failed to retrieve budgets"
        return 1
    fi
    
    # Process each budget
    echo "$budgets" | jq -c '.Budgets[]' | while read -r budget; do
        local budget_name=$(echo "$budget" | jq -r '.BudgetName')
        local budget_type=$(echo "$budget" | jq -r '.BudgetType')
        
        # Get detailed budget information
        local budget_details=$(aws_api_call "budgets describe-budget --account-id $ACCOUNT_ID --budget-name '$budget_name'")
        if [ $? -eq 0 ]; then
            check_budget_alerts "$budget_name" "$budget_details"
        fi
        
        # Check budget notifications
        local notifications=$(aws_api_call "budgets describe-notifications-for-budget --account-id $ACCOUNT_ID --budget-name '$budget_name'")
        if [ $? -eq 0 ]; then
            local notification_count=$(echo "$notifications" | jq '.Notifications | length')
            if [ "$notification_count" -eq 0 ]; then
                display_warning "⚠️ Budget '$budget_name' has no notifications configured"
                echo "WARNING: Budget '$budget_name' has no notifications configured" >> "$SUMMARY_FILE"
            fi
        fi
    done
    
    # Check for cost anomalies
    local anomalies=$(aws_api_call "ce get-anomalies --time-period StartDate=$(date -d "30 days ago" +%Y-%m-%d),EndDate=$(date +%Y-%m-%d)")
    if [ $? -eq 0 ]; then
        local anomaly_count=$(echo "$anomalies" | jq '.Anomalies | length')
        if [ "$anomaly_count" -gt 0 ]; then
            display_warning "⚠️ Found $anomaly_count cost anomalies in the last 30 days"
            echo "$anomalies" | jq -r '.Anomalies[] | "WARNING: Cost anomaly detected: \(.AnomalyDetails.AnomalyType) - \(.AnomalyDetails.RootCauses[0].Service)"' >> "$SUMMARY_FILE"
        fi
    fi
    
    display_info "✅ Budget audit completed"
    return 0
}

# Execute the audit
audit_budgets
exit_code=$?

# Update summary file with overall status
if [ $exit_code -eq 0 ]; then
    echo "✅ Budget audit completed successfully" >> "$SUMMARY_FILE"
else
    echo "🚨 Budget audit encountered errors" >> "$SUMMARY_FILE"
fi

exit $exit_code
