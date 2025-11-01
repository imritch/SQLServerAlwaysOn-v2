# AWS SQL Server Always On - Full Automation Guide

## Overview

This guide explains how the automation works for creating SQL Server Always On Availability Groups in AWS, specifically addressing the **unique challenge of secondary IP assignment in AWS multi-subnet environments**.

## The AWS Secondary IP Challenge

### Why is this different from on-premises?

In traditional on-premises environments, Windows Failover Cluster Manager can assign any IP address to cluster resources and AG listeners dynamically. However, **AWS requires a different approach**:

1. **Secondary IPs must be pre-assigned at the AWS ENI (Elastic Network Interface) level**
2. **These IPs must NOT be configured inside Windows**
3. **Windows Cluster automatically detects and uses these ENI-level IPs**

### How the automation handles this:

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: Assign IPs at AWS ENI Level                            │
│  (04b-Assign-Secondary-IPs.sh - from your local machine)        │
│                                                                   │
│  ┌─────────────┐                      ┌─────────────┐           │
│  │   SQL01     │                      │   SQL02     │           │
│  │  Subnet 1   │                      │  Subnet 2   │           │
│  ├─────────────┤                      ├─────────────┤           │
│  │ 10.0.1.10   │ ← Primary (DHCP)     │ 10.0.2.10   │           │
│  │ 10.0.1.50   │ ← Secondary (ENI)    │ 10.0.2.50   │           │
│  │ 10.0.1.51   │ ← Secondary (ENI)    │ 10.0.2.51   │           │
│  └─────────────┘                      └─────────────┘           │
│                                                                   │
│  Note: Secondary IPs exist at AWS ENI level ONLY                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Step 2: Configure Windows (04c-Configure-Secondary-IPs.ps1)    │
│                                                                   │
│  - Converts from DHCP to Static IP                              │
│  - Keeps ONLY the primary IP in Windows                         │
│  - Does NOT add secondary IPs to Windows                        │
│                                                                   │
│  Windows sees:     10.0.1.10 (SQL01)  |  10.0.2.10 (SQL02)      │
│  AWS ENI has:      10.0.1.10           |  10.0.2.10              │
│                    10.0.1.50           |  10.0.2.50              │
│                    10.0.1.51           |  10.0.2.51              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Step 3: Create Cluster (05-Create-WSFC.ps1)                    │
│                                                                   │
│  New-Cluster -StaticAddress 10.0.1.50, 10.0.2.50                │
│                                                                   │
│  ✓ Cluster automatically detects IPs from ENI                   │
│  ✓ Brings both IPs online as cluster resources                  │
│  ✓ No GUI interaction required                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Step 4: Create AG Listener (09-Create-AvailabilityGroup.ps1)   │
│                                                                   │
│  ALTER AVAILABILITY GROUP ADD LISTENER                           │
│  WITH IP (('10.0.1.51', '255.255.255.0'),                       │
│           ('10.0.2.51', '255.255.255.0'))                       │
│                                                                   │
│  ✓ Listener automatically uses IPs from ENI                     │
│  ✓ Creates DNS entry: SQLAGL01.contoso.local                    │
│  ✓ No GUI interaction required                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Key Changes for Full Automation

### 1. **Updated `05-Create-WSFC.ps1` (Cluster Creation)**

**Before:**
```powershell
$ClusterIP1 = Read-Host "Enter cluster IP for Subnet 1"
$ClusterIP2 = Read-Host "Enter cluster IP for Subnet 2"
```

**After:**
```powershell
param(
    [string]$ClusterIP1 = "10.0.1.50",
    [string]$ClusterIP2 = "10.0.2.50"
)
```

**What changed:**
- Removed interactive prompts
- Added parameter support with sensible defaults
- Added pre-flight validation to ensure IPs are at ENI level only
- Added error handling and IP resource verification

**How it works:**
The `New-Cluster` cmdlet with `-StaticAddress` parameter **automatically discovers** these IPs from the ENI and brings them online. No manual GUI intervention needed!

### 2. **Updated `09-Create-AvailabilityGroup.ps1` (AG Listener)**

**Before:**
```powershell
$ListenerIP1 = Read-Host "Enter AG Listener IP for Subnet 1"
$ListenerIP2 = Read-Host "Enter AG Listener IP for Subnet 2"
```

**After:**
```powershell
param(
    [string]$ListenerIP1 = "10.0.1.51",
    [string]$ListenerIP2 = "10.0.2.51"
)
```

**What changed:**
- Removed interactive prompts
- Added parameter support with defaults
- Added validation to ensure IPs aren't in Windows
- Added comprehensive error handling
- Verifies both SQL and Cluster resource states

**How it works:**
The `ALTER AVAILABILITY GROUP ADD LISTENER` T-SQL command with multiple IPs **automatically uses** the ENI-assigned IPs. The Failover Cluster Manager brings these online without GUI interaction.

### 3. **New `04d-Verify-Secondary-IPs.ps1` (Validation)**

This new script validates that:
- Secondary IPs are assigned at AWS ENI level
- Secondary IPs are NOT configured in Windows
- Provides clear next-step instructions

Can optionally use AWS CLI from Windows to verify ENI configuration.

### 4. **New `00-Master-Setup.ps1` (Orchestration)**

Three phases:
- **Phase DC**: Domain Controller setup
- **Phase SQL-Pre-Cluster**: Domain join and preparation
- **Phase SQL-Post-Cluster**: Cluster and AG creation

## Fully Automated Workflow

### Local Machine (macOS/Linux/Windows with AWS CLI)

```bash
# Step 1: Deploy CloudFormation stack
aws cloudformation create-stack \
  --stack-name sql-ag-demo \
  --template-body file://SQL-AG-CloudFormation.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=your-key \
    ParameterKey=YourIPAddress,ParameterValue=$(curl -s ifconfig.me)/32

# Wait for stack creation
aws cloudformation wait stack-create-complete --stack-name sql-ag-demo

# Step 2: Assign secondary IPs to ENIs
cd AWS/Scripts
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1
```

### On DC01 (via RDP)

```powershell
cd C:\SQLAGScripts

# Automated DC setup
.\00-Master-Setup.ps1 -Phase DC

# After restart (if needed), run again or manually:
.\01-Setup-DomainController.ps1  # If needed after restart
.\02-Configure-AD.ps1
```

### On SQL01 and SQL02 (via RDP)

```powershell
cd C:\SQLAGScripts

# Automated domain join (run on each node)
.\00-Master-Setup.ps1 -Phase SQL-Pre-Cluster `
  -DCPrivateIP 172.31.10.100 `
  -DomainPassword "YourPassword" `
  -ComputerName SQL01  # or SQL02

# After restart, on DC01:
.\02b-Update-gMSA-Permissions.ps1
```

### Back to Local Machine

```bash
# Verify secondary IPs were assigned
aws ec2 describe-network-interfaces \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=sql-ag-demo" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,PrivateIpAddresses[*].PrivateIpAddress]' \
  --output table
```

### On SQL01 Only (via RDP)

```powershell
cd C:\SQLAGScripts

# Run the post-cluster phase
# This will:
# 1. Install clustering on both nodes
# 2. Verify secondary IPs
# 3. Create cluster (fully automated!)
# 4. Prepare for SQL install
# 5. Enable AlwaysOn (after you install SQL)
# 6. Create test database
# 7. Create AG and Listener (fully automated!)

.\00-Master-Setup.ps1 -Phase SQL-Post-Cluster
```

**Note:** SQL Server installation still requires GUI setup (steps 4-5 in the phase), but everything else is automated!

## Individual Script Usage (Non-Interactive)

If you prefer to run scripts individually instead of using the master script:

```powershell
# Cluster creation with explicit IPs
.\05-Create-WSFC.ps1 -ClusterIP1 "10.0.1.50" -ClusterIP2 "10.0.2.50"

# AG creation with explicit IPs
.\09-Create-AvailabilityGroup.ps1 -ListenerIP1 "10.0.1.51" -ListenerIP2 "10.0.2.51"

# Or use defaults (recommended for standard setup)
.\05-Create-WSFC.ps1
.\09-Create-AvailabilityGroup.ps1
```

## How Windows Failover Cluster Uses ENI IPs

This is the **magic** that makes it work without GUI:

1. **IP Assignment at ENI Level:**
   ```bash
   aws ec2 assign-private-ip-addresses \
     --network-interface-id eni-xxx \
     --private-ip-addresses 10.0.1.50 10.0.1.51
   ```
   
2. **Windows Detects ENI IPs:**
   When you run `New-Cluster -StaticAddress 10.0.1.50, 10.0.2.50`, Windows Failover Cluster:
   - Queries the EC2 instance metadata
   - Discovers all IPs assigned to the ENI
   - Finds the requested IPs (10.0.1.50, 10.0.2.50)
   - Creates cluster IP resources
   - Brings them online automatically

3. **What Happens Behind the Scenes:**
   ```powershell
   # Failover Cluster Manager does this automatically:
   # 1. Creates IP Address resources
   # 2. Configures them with ENI-detected IPs
   # 3. Sets dependency to OR (for multi-subnet)
   # 4. Brings resources online
   # 5. Registers DNS entries
   ```

4. **Same for AG Listener:**
   The `ADD LISTENER` command works the same way - Failover Cluster automatically detects the IPs from the ENI.

## Validation and Troubleshooting

### Verify Secondary IPs

```powershell
# Run before cluster creation
.\04d-Verify-Secondary-IPs.ps1
```

### Check Cluster IP Resources

```powershell
# After cluster creation
Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"} | 
  ForEach-Object {
    $ip = ($_ | Get-ClusterParameter | Where-Object {$_.Name -eq "Address"}).Value
    Write-Host "$($_.Name): $ip - State: $($_.State)"
  }
```

### Expected Output:
```
Cluster IP Address: 10.0.1.50 - State: Online
Cluster IP Address 1: 10.0.2.50 - State: Online
```

### Check AG Listener Resources

```powershell
# After AG creation
Get-ClusterResource | Where-Object {$_.OwnerGroup -like "*SQLAOAG*"} |
  Format-Table Name, ResourceType, State -AutoSize
```

### Expected Output:
```
Name                        ResourceType    State
----                        ------------    -----
SQLAGL01                   Network Name    Online
SQLAGL01_10.0.1.51         IP Address      Online
SQLAGL01_10.0.2.51         IP Address      Online
```

### Common Issues

**Issue 1: Cluster IPs fail to come online**

```powershell
# Cause: IPs not assigned at ENI level
# Solution: Run from local machine:
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1
```

**Issue 2: IPs found in Windows configuration**

```powershell
# Cause: Someone manually added IPs to Windows network adapter
# Solution: Remove them (keep only primary IP)
Get-NetIPAddress -InterfaceIndex X -IPAddress 10.0.1.50 | Remove-NetIPAddress
```

**Issue 3: Listener creation timeout**

```powershell
# Cause: IPs not available or AG not healthy
# Solution: Check AG state first
SELECT replica_server_name, synchronization_health_desc 
FROM sys.dm_hadr_availability_replica_states;
```

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                         AWS VPC (10.0.0.0/16)                     │
│                                                                    │
│  ┌─────────────────────┐          ┌─────────────────────┐        │
│  │  Subnet 1 (AZ-A)     │          │  Subnet 2 (AZ-B)     │        │
│  │  10.0.1.0/24         │          │  10.0.2.0/24         │        │
│  │                      │          │                      │        │
│  │  ┌───────────────┐  │          │  ┌───────────────┐  │        │
│  │  │    SQL01      │  │          │  │    SQL02      │  │        │
│  │  ├───────────────┤  │          │  ├───────────────┤  │        │
│  │  │ ENI:          │  │          │  │ ENI:          │  │        │
│  │  │ • 10.0.1.10   │◄─┼──────────┼──┤ • 10.0.2.10   │  │        │
│  │  │ • 10.0.1.50   │  │  Cluster │  │ • 10.0.2.50   │  │        │
│  │  │ • 10.0.1.51   │  │  Network │  │ • 10.0.2.51   │  │        │
│  │  └───────────────┘  │          │  └───────────────┘  │        │
│  │         ▲            │          │         ▲            │        │
│  └─────────┼────────────┘          └─────────┼────────────┘        │
│            │                                  │                     │
│            └──────────────┬───────────────────┘                     │
│                           │                                         │
│                  ┌────────▼────────┐                               │
│                  │  WSFC Cluster    │                               │
│                  │  Cluster IPs:    │                               │
│                  │  • 10.0.1.50     │                               │
│                  │  • 10.0.2.50     │                               │
│                  └────────┬────────┘                               │
│                           │                                         │
│                  ┌────────▼────────┐                               │
│                  │  AG Listener     │                               │
│                  │  SQLAGL01        │                               │
│                  │  IPs:            │                               │
│                  │  • 10.0.1.51     │                               │
│                  │  • 10.0.2.51     │                               │
│                  │  Port: 59999     │                               │
│                  └──────────────────┘                               │
│                                                                      │
└──────────────────────────────────────────────────────────────────┘

Client connects to: SQLAGL01.contoso.local,59999
  ↓
DNS resolves to both: 10.0.1.51 and 10.0.2.51
  ↓
Client tries active IP (MultiSubnetFailover=True)
  ↓
Connects to current primary replica
```

## References

- **AWS Documentation:** [SQL Server EC2 Clustering](https://docs.aws.amazon.com/sql-server-ec2/latest/userguide/aws-sql-ec2-clustering.html#sql-ip-assignment)
- **AWS Video Guide:** [SQL Server Always On in AWS](https://www.youtube.com/watch?v=9CqhH03vLeo)
- **Microsoft Docs:** [Always On Availability Groups](https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/always-on-availability-groups-sql-server)

## Summary

The key insight for automating SQL AG in AWS:

1. ✅ **Pre-assign secondary IPs at AWS ENI level** (via AWS CLI/API)
2. ✅ **Keep these IPs OUT of Windows configuration** (only primary IP in Windows)
3. ✅ **Windows Failover Cluster automatically detects and uses ENI IPs** (no GUI needed!)
4. ✅ **PowerShell scripts with parameters enable full automation** (no interactive prompts)

This approach is **completely code-driven** and requires **no Failover Cluster Manager GUI interaction** for IP assignment!

