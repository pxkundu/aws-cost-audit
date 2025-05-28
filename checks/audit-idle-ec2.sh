#!/bin/bash

source ../lib/helpers.sh
source ../settings.sh

display_info "🔎 Checking for idle EC2 instances (CPU < $CPU_THRESHOLD%)..."

instances=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,Name:Tags[?Key=='Name'].Value|[0]}" \
    --output json)

idle_instances=()
while IFS= read -r instance; do
    instance_id=$(echo "$instance" | jq -r '.ID')
    instance_name=$(echo "$instance" | jq -r '.Name // "Unnamed"')
    cpu_metrics=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/EC2 \
        --metric-name CPUUtilization \
        --dimensions Name=InstanceId,Value="$instance_id" \
        --start-time "$(date -u -d '7 days ago' +%FT%TZ)" \
        --end-time "$(date -u +%FT%TZ)" \
        --period 86400 \
        --statistics Average \
        --output json)
    avg_cpu=$(echo "$cpu_metrics" | jq '.Datapoints[] | .Average' | head -1)
    if [ -n "$avg_cpu" ] && (( $(echo "$avg_cpu < $CPU_THRESHOLD" | bc -l) )); then
        idle_instances+=("$instance_id ($instance_name): Avg CPU $avg_cpu%")
    fi
done <<< "$(echo "$instances" | jq -c '.[]')"

if [ ${#idle_instances[@]} -eq 0 ]; then
    echo "✅ No idle EC2 instances found."
else
    echo "⚠️ Idle EC2 instances (CPU < $CPU_THRESHOLD%):"
    for instance in "${idle_instances[@]}"; do
        echo "- $instance"
    done
    send_notification "AWS Cost Audit: Idle EC2 Instances" "Found ${#idle_instances[@]} idle EC2 instances."
fi
