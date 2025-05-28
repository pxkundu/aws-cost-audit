# AWS Cost Audit

A modular Bash script for auditing AWS costs, designed for enterprise use with interactive profile selection.

## Prerequisites
- AWS CLI v2 installed and configured with credentials
- `jq` for JSON parsing
- Bash 4.0+
- AWS permissions for EC2, S3, RDS, CloudWatch, Budgets, and ELB
- Optional: AWS SES for notifications

## Setup
1. Run the setup script:
   ```bash
   ./setup-project.sh
   cd aws-cost-audit
   ```
2. Configure AWS CLI with at least one profile.
3. Edit `settings.sh` to set thresholds and notification settings.
4. Ensure scripts are executable:
   ```bash
   chmod +x run-audit.sh checks/*.sh
   ```

## Usage
Run the audit script:
```bash
./run-audit.sh
```

The script will prompt you to select an AWS profile. Output is logged to `reports/audit_aws_YYYYMMDD_HHMMSS.log` and a summary is saved to `reports/summary_report_YYYYMMDD_HHMMSS.txt`.

## Customization
- Modify `settings.sh` for thresholds (e.g., `CPU_THRESHOLD`, `MAX_SNAPSHOT_AGE_DAYS`).
- Enable notifications by setting `SEND_NOTIFICATIONS=true` and configuring `NOTIFY_EMAIL`.
- Add new checks in the `checks/` directory and update the `CHECKS` array in `run-audit.sh`.

## Checks Included
- Budget Alerts
- Untagged Resources
- Idle EC2 Instances
- S3 Lifecycle Policies
- Old RDS Snapshots
- Forgotten EBS Volumes
- Data Transfer Risks
- On-Demand EC2 Instances
- Idle Load Balancers
- Unused AMIs

## Output
- Interactive terminal output with emojis
- Detailed log file in `reports/`
- Summary report with findings for each check

## Contributing
Contributions are welcome! Please submit a pull request or open an issue.

## License
MIT License
