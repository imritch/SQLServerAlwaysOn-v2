# Quick Reference - Automated SQL AG Setup

## TL;DR - The Answer to Your Question

**Q: How do I avoid Failover Cluster Manager GUI for IP assignment?**

**A: You already do! The `New-Cluster` and `ADD LISTENER` commands automatically use ENI-assigned IPs. I just removed the interactive prompts.**

## Before vs After

### Before (Your Scripts)
```powershell
# Prompted for user input
$ClusterIP1 = Read-Host "Enter cluster IP for Subnet 1"
$ClusterIP2 = Read-Host "Enter cluster IP for Subnet 2"
New-Cluster -StaticAddress $ClusterIP1, $ClusterIP2  # ✅ Already correct!
```

### After (Enhanced)
```powershell
# No prompts - fully automated
param([string]$ClusterIP1 = "10.0.1.50", [string]$ClusterIP2 = "10.0.2.50")
New-Cluster -StaticAddress $ClusterIP1, $ClusterIP2  # ✅ Same command!
```

**Key Point:** The PowerShell command was already correct! I just made it non-interactive.

## Complete Automation Commands

### 1. AWS Infrastructure (Local Machine)

```bash
# Deploy everything
aws cloudformation create-stack \
  --stack-name sql-ag-demo \
  --template-body file://SQL-AG-CloudFormation.yaml \
  --parameters ParameterKey=KeyPairName,ParameterValue=your-key \
               ParameterKey=YourIPAddress,ParameterValue=$(curl -s ifconfig.me)/32

aws cloudformation wait stack-create-complete --stack-name sql-ag-demo

# Assign secondary IPs (CRITICAL STEP!)
cd AWS/Scripts
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1
```

### 2. Domain Controller (DC01)

```powershell
cd C:\SQLAGScripts
.\00-Master-Setup.ps1 -Phase DC
# Restart if needed, then run again
```

### 3. SQL Nodes (SQL01 and SQL02)

```powershell
cd C:\SQLAGScripts

# On SQL01
.\00-Master-Setup.ps1 -Phase SQL-Pre-Cluster `
  -DCPrivateIP "172.31.10.100" `
  -DomainPassword "YourPassword" `
  -ComputerName "SQL01"

# On SQL02
.\00-Master-Setup.ps1 -Phase SQL-Pre-Cluster `
  -DCPrivateIP "172.31.10.100" `
  -DomainPassword "YourPassword" `
  -ComputerName "SQL02"

# After both restart, on DC01:
.\02b-Update-gMSA-Permissions.ps1
```

### 4. Cluster and AG (SQL01 Only)

```powershell
cd C:\SQLAGScripts

# Option A: Use master script (mostly automated)
.\00-Master-Setup.ps1 -Phase SQL-Post-Cluster

# Option B: Individual scripts (fully automated)
.\04-Install-Failover-Clustering.ps1  # Run on both nodes
.\04d-Verify-Secondary-IPs.ps1        # Validation
.\05-Create-WSFC.ps1                  # Cluster - NO PROMPTS! ✅
.\06-Install-SQLServer-Prep.ps1
# <Install SQL Server GUI - only manual step>
.\07-Enable-AlwaysOn.ps1              # Run on both nodes
sqlcmd -S SQL01 -i .\08-Create-TestDatabase.sql
.\09-Create-AvailabilityGroup.ps1     # Listener - NO PROMPTS! ✅
```

## The AWS Secondary IP Magic

```
AWS ENI Level (assigned via AWS CLI):
┌─────────────────────────────────────┐
│ SQL01 ENI:                          │
│  • 10.0.1.10  ← Primary (in Windows)│
│  • 10.0.1.50  ← Secondary (NOT in Windows!)│
│  • 10.0.1.51  ← Secondary (NOT in Windows!)│
└─────────────────────────────────────┘
            ↓
Windows Failover Cluster auto-detects:
┌─────────────────────────────────────┐
│ When you run:                       │
│ New-Cluster -StaticAddress 10.0.1.50│
│                                     │
│ Cluster Manager:                    │
│ 1. Queries EC2 metadata             │
│ 2. Finds 10.0.1.50 on ENI          │
│ 3. Creates IP resource             │
│ 4. Brings it online                │
│ 5. NO GUI NEEDED! ✅               │
└─────────────────────────────────────┘
```

## IP Allocation Reference

| Purpose | Subnet 1 (SQL01) | Subnet 2 (SQL02) |
|---------|------------------|------------------|
| Primary IP (in Windows) | 10.0.1.10 | 10.0.2.10 |
| Cluster IP (ENI only) | 10.0.1.50 | 10.0.2.50 |
| Listener IP (ENI only) | 10.0.1.51 | 10.0.2.51 |

## Validation Commands

```powershell
# Verify secondary IPs assigned (before cluster)
.\04d-Verify-Secondary-IPs.ps1

# Check cluster IPs (after cluster creation)
Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"} | 
  Get-ClusterParameter | Where-Object {$_.Name -eq "Address"} | 
  Format-Table ClusterObject, Value, State -AutoSize

# Check listener IPs (after AG creation)
Get-ClusterResource | Where-Object {$_.OwnerGroup -like "*SQLAOAG*"} |
  Format-Table Name, ResourceType, State -AutoSize

# Test listener connection
sqlcmd -S SQLAGL01,59999 -Q "SELECT @@SERVERNAME, DB_NAME()"

# Validate AG health
sqlcmd -S SQL01 -i .\10-Validate-AG.sql
```

## Common Issues and Fixes

### Issue 1: "Cluster IPs fail to come online"
```powershell
# Cause: IPs not assigned at ENI level
# Fix: Run from local machine
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1

# Verify assignment
aws ec2 describe-network-interfaces \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=sql-ag-demo" \
  --query 'NetworkInterfaces[*].PrivateIpAddresses' --output table
```

### Issue 2: "ERROR: Cluster IPs found in Windows configuration"
```powershell
# Cause: Someone manually added IPs to Windows adapter
# Fix: Remove them (keep only primary)
Get-NetIPAddress -InterfaceIndex X | Where-Object {$_.IPAddress -like "10.0.*.50"} | 
  Remove-NetIPAddress -Confirm:$false
```

### Issue 3: "Listener creation timeout"
```powershell
# Cause: AG not healthy or IPs not available
# Check AG health first
SELECT replica_server_name, 
       synchronization_health_desc,
       connected_state_desc
FROM sys.dm_hadr_availability_replica_states;

# If healthy, manually create listener
ALTER AVAILABILITY GROUP SQLAOAG01
ADD LISTENER N'SQLAGL01' (
    WITH IP (
        (N'10.0.1.51', N'255.255.255.0'),
        (N'10.0.2.51', N'255.255.255.0')
    ),
    PORT = 59999
);
```

## Files You Need to Know

### Core Scripts (Updated for Automation)
- `05-Create-WSFC.ps1` - Creates cluster (no prompts!)
- `09-Create-AvailabilityGroup.ps1` - Creates listener (no prompts!)

### New Scripts
- `04d-Verify-Secondary-IPs.ps1` - Pre-flight validation
- `00-Master-Setup.ps1` - End-to-end orchestration

### Documentation
- `README-Automation.md` - Detailed guide
- `QUICK-REFERENCE.md` - This file
- `../Quick-Start-Guide.md` - Step-by-step walkthrough

## Connection Strings

```csharp
// Always use MultiSubnetFailover=True for AWS multi-subnet AG!
"Server=SQLAGL01,59999;Database=AGTestDB;Integrated Security=True;MultiSubnetFailover=True;"

// Or with DNS suffix
"Server=SQLAGL01.contoso.local,59999;Database=AGTestDB;Integrated Security=True;MultiSubnetFailover=True;"
```

## What's Still Manual?

Only one thing: **SQL Server Installation GUI**

Everything else is automated:
- ✅ CloudFormation deployment
- ✅ Secondary IP assignment
- ✅ Domain controller setup
- ✅ Domain join
- ✅ Cluster creation
- ✅ AG creation
- ✅ Listener creation

## Pro Tips

1. **Always run 04b-Assign-Secondary-IPs.sh BEFORE creating the cluster**
2. **Never add secondary IPs to Windows network adapter** (breaks everything)
3. **Use 04d-Verify-Secondary-IPs.ps1 before cluster creation** (saves debugging time)
4. **Keep cluster IPs (.50) separate from listener IPs (.51)** (clarity)
5. **Use MultiSubnetFailover=True in connection strings** (required for fast failover)

## Time Estimates

- CloudFormation deployment: 5-7 minutes
- DC setup: 10-15 minutes (with restart)
- SQL node setup (each): 5 minutes + restart
- SQL Server installation (each): 15-20 minutes (GUI)
- Cluster creation: 2-3 minutes ✅ Automated!
- AG creation: 3-5 minutes ✅ Automated!

**Total: ~2 hours** (mostly waiting for installations/restarts)

## Success Criteria

```powershell
# All should return "Online"
Get-ClusterNode | Select-Object Name, State
Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"} | Select-Object Name, State
Get-ClusterResource | Where-Object {$_.OwnerGroup -like "*SQLAOAG*"} | Select-Object Name, State

# Should connect successfully
sqlcmd -S SQLAGL01,59999 -Q "SELECT @@SERVERNAME"

# Should show SYNCHRONIZED
sqlcmd -S SQL01 -Q "SELECT synchronization_state_desc FROM sys.dm_hadr_database_replica_states"
```

---

**Bottom Line:** Your original scripts were architecturally correct! I just removed the interactive prompts and added validation. Windows Failover Cluster automatically handles ENI IPs without any GUI interaction. ✅

