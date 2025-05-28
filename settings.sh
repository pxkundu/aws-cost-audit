#!/bin/bash

# Configuration for AWS Cost Audit
# Customize thresholds and settings here

# General settings
export OUTPUT_FORMAT="table"  # Options: table, json
export MAX_SNAPSHOT_AGE_DAYS=90  # Threshold for old RDS snapshots
export CPU_THRESHOLD=5.0  # CPU utilization threshold for idle EC2 instances (%)
export DATA_TRANSFER_THRESHOLD_GB=100  # Data transfer threshold in GB
export INACTIVITY_DAYS=30  # Days of inactivity for idle resources

# Email notification settings (optional, requires AWS SES setup)
export NOTIFY_EMAIL="cost-audit@example.com"
export SEND_NOTIFICATIONS=false
