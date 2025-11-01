# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a complete automation package for deploying a 2-node SQL Server Always On Availability Group on AWS EC2, spanning multiple availability zones. The setup demonstrates high availability architecture with Windows Server Failover Clustering (WSFC), Active Directory integration using gMSA (Group Managed Service Accounts), and multi-subnet AG deployment.

**Target Environment:** AWS EC2 instances running Windows Server 2019 and SQL Server 2022 Developer Edition

## Architecture

### Infrastructure Components

1. **DC01** (t3.medium): Active Directory Domain Controller
   - Domain: contoso.local
   - Hosts gMSA accounts for SQL services (sqlsvc$, sqlagent$)
   - Provides DNS and authentication

2. **SQL01** (t3.xlarge): Primary SQL Server node in Subnet 1 (10.0.1.0/24, AZ1)
   - Primary replica for Availability Group
   - Hosts backup share for AG seeding

3. **SQL02** (t3.xlarge): Secondary SQL Server node in Subnet 2 (10.0.2.0/24, AZ2)
   - Secondary replica with synchronous commit
   - Automatic failover enabled

### Critical AWS-Specific Requirement: Secondary IP Assignment

**This is the most important architectural distinction from on-premises deployments.**

AWS requires secondary private IPs for cluster resources (cluster IPs and AG listener IPs) to be assigned at the **ENI (Elastic Network Interface) level** BEFORE cluster/AG creation. These IPs must NOT be configured within Windows itself.

**IP Allocation:**
- **SQL01 Secondary IPs:** 10.0.1.50 (cluster), 10.0.1.51 (listener)
- **SQL02 Secondary IPs:** 10.0.2.50 (cluster), 10.0.2.51 (listener)

**Why this matters:** Windows Failover Cluster automatically detects and brings online IPs that exist at the ENI level. Manual IP assignment in Windows will break networking. The scripts `04b-Assign-Secondary-IPs.sh` (AWS CLI) and validation in `04d-Verify-Secondary-IPs.ps1` enforce this architecture.

**Reference:** [AWS Documentation on SQL Server Clustering](https://docs.aws.amazon.com/sql-server-ec2/latest/userguide/aws-sql-ec2-clustering.html#sql-ip-assignment) and [YouTube video](https://www.youtube.com/watch?v=9CqhH03vLeo)

## Repository Structure

```
AWS/
├── Scripts/                      # PowerShell automation scripts (numbered execution order)
│   ├── 00-Master-Setup.ps1      # Orchestration script for automated phases
│   ├── 01-Setup-DomainController.ps1
│   ├── 02-Configure-AD.ps1
│   ├── 02b-Update-gMSA-Permissions.ps1
│   ├── 03-Join-Domain.ps1
│   ├── 04-Install-Failover-Clustering.ps1
│   ├── 04b-Assign-Secondary-IPs.sh    # AWS CLI - CRITICAL for multi-subnet
│   ├── 04c-Configure-Secondary-IPs-Windows.ps1
│   ├── 04d-Verify-Secondary-IPs.ps1   # Pre-flight validation
│   ├── 05-Create-WSFC.ps1              # Cluster creation (multi-subnet)
│   ├── 06-Install-SQLServer-Prep.ps1
│   ├── 07-Enable-AlwaysOn.ps1
│   ├── 08-Create-TestDatabase.sql
│   ├── 09-Create-AvailabilityGroup.ps1 # AG and listener creation
│   ├── 10-Validate-AG.sql
│   ├── 11-Test-Failover.sql
│   ├── Fix-LineEndings.sh              # Convert LF to CRLF for Windows
│   ├── Fix-ADWS.ps1                    # Troubleshooting AD Web Services
│   ├── add-security-group-rules.sh     # Security group configuration
│   └── README.md
├── Quick-Start-Guide.md          # Primary execution guide (start here)
├── SQL-AG-Setup-Guide.md         # Detailed explanations and architecture
├── Setup-Checklist.md            # Interactive tracking checklist
├── OutstandingItems.md           # Known issues and fixes
└── SQL-AG-CloudFormation.yaml    # Infrastructure deployment template
```

## Common Development Tasks

### Testing Script Changes

Before executing PowerShell scripts on Windows, ensure proper line endings:
```bash
cd AWS/Scripts
./Fix-LineEndings.sh
```

**Known Issue:** PowerShell scripts sometimes fail with "terminator expected" errors even with correct CRLF endings. Workaround: Open the script in an editor, add a blank line at the end, save, and remove it. This forces a proper file encoding refresh.

### Infrastructure Deployment

```bash
# Get your public IP
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32

# Deploy CloudFormation stack
aws cloudformation create-stack \
  --stack-name sql-ag-demo \
  --template-body file://AWS/SQL-AG-CloudFormation.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=YOUR_KEY_NAME \
    ParameterKey=YourIPAddress,ParameterValue=$MY_IP \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name sql-ag-demo \
  --region us-east-1

# Get outputs (instance IPs, IDs)
aws cloudformation describe-stacks \
  --stack-name sql-ag-demo \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

### Assign Secondary IPs (Critical Step)

After cluster feature installation but BEFORE cluster creation:
```bash
cd AWS/Scripts
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1
```

### Retrieve Instance Passwords

```bash
# Get instance IDs from CloudFormation outputs
DC01_ID=$(aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`DC01InstanceId`].OutputValue' --output text)
SQL01_ID=$(aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`SQL01InstanceId`].OutputValue' --output text)
SQL02_ID=$(aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`SQL02InstanceId`].OutputValue' --output text)

# Decrypt passwords (wait 5-10 minutes after instance launch)
aws ec2 get-password-data --instance-id $DC01_ID --priv-launch-key ~/YOUR_KEY.pem --region us-east-1
aws ec2 get-password-data --instance-id $SQL01_ID --priv-launch-key ~/YOUR_KEY.pem --region us-east-1
aws ec2 get-password-data --instance-id $SQL02_ID --priv-launch-key ~/YOUR_KEY.pem --region us-east-1
```

### Cleanup

```bash
# Stop instances (preserves configuration, stops compute charges)
aws ec2 stop-instances --instance-ids i-xxx i-yyy i-zzz --region us-east-1

# Complete teardown (deletes everything)
aws cloudformation delete-stack --stack-name sql-ag-demo --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name sql-ag-demo --region us-east-1
```

## Execution Workflow

### Phase 1: Domain Controller (DC01)
```powershell
cd C:\SQLAGScripts\Scripts
.\01-Setup-DomainController.ps1
# Server restarts automatically
.\01-Setup-DomainController.ps1  # Run again after reboot
.\02-Configure-AD.ps1
```

### Phase 2: SQL Nodes (SQL01, SQL02)
```powershell
cd C:\SQLAGScripts\Scripts
.\03-Join-Domain.ps1
# Prompts for DC IP, domain password, computer name
# Server restarts automatically
.\03-Join-Domain.ps1  # Run again after reboot to complete domain join

# After domain join on BOTH nodes, return to DC01
.\02b-Update-gMSA-Permissions.ps1  # On DC01 only
```

### Phase 3: Clustering
```powershell
# On both SQL01 and SQL02
.\04-Install-Failover-Clustering.ps1

# From local machine (AWS CLI)
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1

# Verify secondary IPs (optional but recommended)
.\04d-Verify-Secondary-IPs.ps1  # On SQL01 or SQL02

# On SQL01 only
.\05-Create-WSFC.ps1
# Uses default IPs: -ClusterIP1 10.0.1.50 -ClusterIP2 10.0.2.50
```

### Phase 4: SQL Server Installation
```powershell
# On both SQL01 and SQL02
.\06-Install-SQLServer-Prep.ps1

# Manual GUI installation of SQL Server 2022 Developer Edition
# Download: https://www.microsoft.com/sql-server/sql-server-downloads
# Use gMSA accounts: CONTOSO\sqlsvc$ and CONTOSO\sqlagent$ (no password)

.\07-Enable-AlwaysOn.ps1
```

### Phase 5: Availability Group
```powershell
# On SQL01 only
sqlcmd -S SQL01 -i C:\SQLAGScripts\Scripts\08-Create-TestDatabase.sql
.\09-Create-AvailabilityGroup.ps1
# Uses default IPs: -ListenerIP1 10.0.1.51 -ListenerIP2 10.0.2.51

# Validation
sqlcmd -S SQL01 -i C:\SQLAGScripts\Scripts\10-Validate-AG.sql
```

## Key Script Behaviors

### 05-Create-WSFC.ps1 (Cluster Creation)
- Accepts `-ClusterIP1` and `-ClusterIP2` parameters (defaults: 10.0.1.50, 10.0.2.50)
- Pre-flight validation ensures IPs are NOT in Windows (must be ENI-only)
- Uses `New-Cluster -StaticAddress` which auto-detects ENI IPs
- Verifies cluster IP resources come online
- No GUI interaction required

### 09-Create-AvailabilityGroup.ps1 (AG and Listener)
- Accepts `-ListenerIP1` and `-ListenerIP2` parameters (defaults: 10.0.1.51, 10.0.2.51)
- Pre-flight validation ensures listener IPs are NOT in Windows
- Creates mirroring endpoints on both replicas
- Creates AG with synchronous commit and automatic failover
- Uses T-SQL `ADD LISTENER` with multi-subnet support
- Restores database backups on secondary
- No GUI interaction required for listener creation

## Known Issues and Solutions

### Issue 1: PowerShell Line Ending Errors
**Symptom:** "Missing closing '}'" or "terminator expected" errors
**Solution:** Run `Fix-LineEndings.sh` or manually edit file (add/remove blank line)

### Issue 2: AD Web Services Unavailable
**Symptom:** "Unable to contact the server" when testing gMSA in `06-Install-SQLServer-Prep.ps1`
**Solution:**
```powershell
# On DC01
.\Fix-ADWS.ps1

# On local machine
./add-security-group-rules.sh
```
Required ports: TCP 9389 (ADWS), 88 (Kerberos), 389 (LDAP), 636 (LDAPS), 53 (DNS)

### Issue 3: SQL Server TCP Protocol Disabled
**Symptom:** `Test-NetConnection -ComputerName SQL02 -Port 1433` fails
**Solution:** Enable TCP/IP in SQL Server Configuration Manager on both nodes, restart SQL Server service

### Issue 4: AG Database Join Failure - "Connection to primary replica is not active"
**Symptom:** Error at step [5/7] in `09-Create-AvailabilityGroup.ps1`
**Root Cause:** Timing issue where secondary replica hasn't fully synchronized before database join
**Solution:** Add delay between AG join and database restore, verify primary connection before proceeding

### Issue 5: DNS Suffix Not Configured
**Symptom:** "Computer SQL02 could not be reached" during cluster creation
**Solution:**
```powershell
# On both SQL01 and SQL02
.\Configure-DNS-Suffix.ps1

# Verify
nslookup SQL01
nslookup SQL02
```

## Default Credentials

- **Domain:** contoso.local
- **Domain Admin:** CONTOSO\Administrator (set during DC setup)
- **SQL Admin User:** CONTOSO\sqladmin / P@ssw0rd123!
- **SQL Service gMSA:** CONTOSO\sqlsvc$ (no password)
- **SQL Agent gMSA:** CONTOSO\sqlagent$ (no password)

**WARNING:** These are demo credentials. Change for production use.

## Testing and Validation

### Verify AG Health
```sql
-- Run on SQL01 in SSMS
SELECT * FROM sys.dm_hadr_availability_group_states;
SELECT * FROM sys.dm_hadr_database_replica_states;
```

### Test Listener Connection
```powershell
# DNS resolution
nslookup SQLAGL01.contoso.local

# SQL connection
sqlcmd -S SQLAGL01,1433 -Q "SELECT @@SERVERNAME, DB_NAME()"
```

### Test Failover
```sql
-- Manual failover (run on SQL01)
ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;

-- Or automatic failover (stop SQL service on primary)
Stop-Service MSSQLSERVER -Force
```

## Important File References

- **Quick-Start-Guide.md** - Primary execution guide with detailed commands
- **AUTOMATION-SUMMARY.md** - Explains how AWS ENI IP detection works and why GUI is not needed
- **OutstandingItems.md** - Tracks current issues and their resolutions
- **AWS/Scripts/README.md** - Script execution order and descriptions
- **AWS/Scripts/README-Automation.md** - Deep dive into automation approach

## Multi-Subnet AG Listener Configuration

The listener uses "OR" dependency mode where either IP can be online (active on current primary's subnet):
```sql
ALTER AVAILABILITY GROUP [SQLAOAG01]
ADD LISTENER N'SQLAGL01' (
    WITH IP ((N'10.0.1.51', N'255.255.255.0'), (N'10.0.2.51', N'255.255.255.0')),
    PORT = 1433
);
```

Connection string must include `MultiSubnetFailover=True` for fast cross-subnet failover.

## Performance Considerations

- **Synchronous commit** ensures zero data loss but adds latency proportional to network RTT between AZs
- **Automatic failover** typically completes in 10-30 seconds
- **Cross-subnet failover** requires MultiSubnetFailover=True in connection string for optimal performance
- **Backup preference:** Set to PRIMARY by default (can configure secondary for read-only routing)

## Cost Estimates (us-east-1)

- **Hourly:** ~$0.38/hour (DC01: $0.04, SQL01/02: $0.17 each)
- **Monthly (24/7):** ~$310 (compute: $275, storage: $35)
- **Stop instances when not in use** to eliminate compute charges (storage charges remain)
