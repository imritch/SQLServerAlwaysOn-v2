# SQL Server AG in AWS - Quick Start Guide

**Estimated Time:** 2-3 hours  
**Cost:** ~$0.38/hour (~$275/month if left running)

---

## Step 0: Prepare Scripts (First Time Only)

**⚠️ IMPORTANT:** Before using the scripts, fix line endings for Windows compatibility:

```bash
cd SQLServerAlwaysOn/AWS/Scripts
./Fix-LineEndings.sh
```

This converts scripts from Unix (LF) to Windows (CRLF) line endings, preventing PowerShell parsing errors.

**You only need to do this once!** After conversion, the scripts will work correctly on Windows.

---

## Step 1: Deploy CloudFormation Stack

### Option A: Using AWS Console

1. **Go to CloudFormation** in AWS Console
2. **Create Stack** → Upload `SQL-AG-CloudFormation.yaml`
3. **Parameters:**
   - Stack Name: `sql-ag-demo`
   - KeyPairName: Select your existing key pair (or create one first)
   - YourIPAddress: Enter your IP with /32 (e.g., `203.0.113.45/32`)
4. **Create Stack** (takes ~5 minutes)
5. **Note the Outputs** tab for instance IPs

## Actual Command Executed While Creating the Stack

```bash

aws cloudformation create-stack   --stack-name sql-ag-demo   --template-body file://SQL-AG-CloudFormation.yaml   --parameters     ParameterKey=KeyPairName,ParameterValue=sql-ag-demo-key     ParameterKey=YourIPAddress,ParameterValue=$MY_IP   --region us-east-1

```

## Get the outputs after stack creation in a nice table format

```bash

# Get all outputs in a nice table
aws cloudformation describe-stacks \
  --stack-name sql-ag-demo \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

```

### Option B: Using AWS CLI

```bash
# Get your public IP (choose based on your OS)
# Linux/WSL:
MY_IP=$(curl -s ifconfig.me)/32

# macOS (if above fails):
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32

# Verify your IP
echo $MY_IP

# Deploy stack
# Replace YOUR_KEY_NAME with your actual EC2 key pair name (without .pem extension)
# To check available key pairs: aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output table
aws cloudformation create-stack \
  --stack-name sql-ag-demo \
  --template-body file://SQL-AG-CloudFormation.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=YOUR_KEY_NAME \
    ParameterKey=YourIPAddress,ParameterValue=$MY_IP \
  --region us-east-1

# Track stack creation progress (run in separate terminal)
watch -n 5 'aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query "Stacks[0].StackStatus" --output text'

# Or use this command to see detailed events
while true; do clear; aws cloudformation describe-stack-events --stack-name sql-ag-demo --region us-east-1 --max-items 15 --query 'StackEvents[*].[Timestamp,ResourceStatus,LogicalResourceId]' --output table; sleep 5; done

# Wait for completion (blocks until done)
aws cloudformation wait stack-create-complete \
  --stack-name sql-ag-demo \
  --region us-east-1

# Get outputs in table format
aws cloudformation describe-stacks \
  --stack-name sql-ag-demo \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

---

## Step 2: Get Instance Details

From CloudFormation Outputs, note:
- **DC01PrivateIP**: (e.g., 172.31.10.100) - needed for DNS config
- **DC01PublicIP**: (e.g., 54.x.x.x) - for RDP
- **SQL01PublicIP**: (e.g., 54.y.y.y) - for RDP
- **SQL02PublicIP**: (e.g., 54.z.z.z) - for RDP

---

## Step 3: Setup Domain Controller

### 3.1: RDP to DC01

## Steps Before You can RDP to DC01

1. Get the IP Addresses from the CloudFormation outputs

```bash

# Get all outputs in a nice table
aws cloudformation describe-stacks \
  --stack-name sql-ag-demo \
  --region us-east-1 \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table

```


2. Get the Windows password for DC01, and other instances. 

```bash

# Get instance IDs
DC01_ID=$(aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`DC01InstanceId`].OutputValue' --output text)
SQL01_ID=$(aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`SQL01InstanceId`].OutputValue' --output text)
SQL02_ID=$(aws cloudformation describe-stacks --stack-name sql-ag-demo --region us-east-1 --query 'Stacks[0].Outputs[?OutputKey==`SQL02InstanceId`].OutputValue' --output text)

# Get passwords (wait 5-10 minutes after instance launch for password to be available)
# Note - Change the path to the pem file to the one you used when creating the stack

aws ec2 get-password-data --instance-id $DC01_ID --priv-launch-key ~/sql-ag-demo-key.pem --region us-east-1
aws ec2 get-password-data --instance-id $SQL01_ID --priv-launch-key ~/sql-ag-demo-key.pem --region us-east-1
aws ec2 get-password-data --instance-id $SQL02_ID --priv-launch-key ~/sql-ag-demo-key.pem --region us-east-1

```




```powershell
# Get Windows password
# EC2 Console → DC01 → Connect → RDP → Get Password (upload your .pem key)

# Or via AWS CLI
aws ec2 get-password-data \
  --instance-id i-xxxxx \
  --priv-launch-key your-key.pem
```

RDP to DC01 public IP as `Administrator`

### 3.2: Copy Scripts

1. Copy all files from `Scripts/` folder to `C:\SQLAGScripts\` on DC01
2. Or download from your repo/storage

### 3.3: Run DC Setup

```powershell
# In PowerShell on DC01
cd C:\SQLAGScripts
.\01-Setup-DomainController.ps1
```

**Wait for automatic restart (~5 minutes)**
### Execute the script again after first reboot to continue the setup

```powershell
# In PowerShell on DC01
cd C:\SQLAGScripts
.\01-Setup-DomainController.ps1
```



### 3.4: Configure Active Directory

After DC01 restarts, RDP back as `CONTOSO\Administrator`:

```powershell
cd C:\SQLAGScripts
.\02-Configure-AD.ps1
```

✅ **Checkpoint:** AD is ready with gMSA accounts

---

## Step 4: Setup SQL Nodes

### 4.1: Copy Scripts to SQL Nodes

1. RDP to SQL01 and SQL02
2. Copy `Scripts/` folder to `C:\SQLAGScripts\` on each

### 4.2: Join SQL01 to Domain

On SQL01:

```powershell
cd C:\SQLAGScripts
.\03-Join-Domain.ps1

# When prompted:
# DC IP: <DC01PrivateIP from Step 2>
# Domain Password: <your CONTOSO\Administrator password>
# Its the password you got when you created the EC2 instances and used aws ec2 get-password-data to get the password for the DC01 instance. 
# Computer Name: SQL01
# When you execute the script 03-Join-Domain.ps1, it will automatically rename the computer to SQL01 and reboot the machine. 
# After the machine reboots, you need to execute the script again to join the domain.
```

### 4.3: Join SQL02 to Domain

On SQL02:

```powershell
cd C:\SQLAGScripts
.\03-Join-Domain.ps1

# When prompted:
# DC IP: <DC01PrivateIP from Step 2>
# Domain Password: <your CONTOSO\Administrator password>
# Computer Name: SQL02
# When you execute the script 03-Join-Domain.ps1, it will automatically rename the computer to SQL02 and reboot the machine. 
# After the machine reboots, you need to execute the script again to join the domain.
```

**Wait for restart**

### 4.4: RDP Back as Domain User

From now on, RDP to SQL01 and SQL02 as:
- User: `CONTOSO\Administrator`
- Password: <your domain password>

✅ **Checkpoint:** All machines joined to domain

**✨ What Just Happened Automatically:**

The `03-Join-Domain.ps1` script automatically configured:
1. ✅ **DNS suffix settings** - Enables short name resolution (e.g., "SQL02" works)
2. ✅ **RSAT AD PowerShell tools** - Installs Active Directory cmdlets for gMSA
3. ✅ **Domain membership** - Joins node to contoso.local

**⚠️ IMPORTANT - DNS Suffix Configuration:**

The updated `03-Join-Domain.ps1` script automatically configures DNS suffix settings required for clustering. This enables short name resolution (e.g., "SQL02" instead of "SQL02.contoso.local"), which is **CRITICAL** for Windows Failover Clustering.

If you joined the domain before this update, or if you encounter "Computer SQL02 could not be reached" errors during cluster creation, run this on **BOTH** nodes:

```powershell
cd C:\SQLAGScripts
.\Configure-DNS-Suffix.ps1
```

Verify short name resolution works:
```powershell
nslookup SQL01
nslookup SQL02
# Both should resolve successfully
```

See `DNS-SUFFIX-ISSUE.md` for detailed explanation.

## Step 4.5: Update gMSA Permissions

On DC01:

```powershell
cd C:\SQLAGScripts
.\02b-Update-gMSA-Permissions.ps1
```


✅ **Checkpoint:** gMSA permissions updated


---

## Step 5: Assign Secondary IPs (AWS Requirement)

**⚠️ CRITICAL STEP for AWS Multi-Subnet AG**

Before creating the Windows Failover Cluster, you MUST assign secondary private IPs to your SQL nodes. Windows Cluster and AG Listener require these IPs to be pre-assigned at the AWS ENI level.

### 5.1: Run IP Assignment Script

On **your local machine** (not on the Windows servers):

```bash
cd /path/to/SQLServerAlwaysOn/AWS/Scripts

# Make script executable (if not already)
chmod +x 04b-Assign-Secondary-IPs.sh

# Run the script (adjust stack name if different)
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1
```

**What this does:**
- Assigns 10.0.1.50 and 10.0.1.51 to SQL01 (for Cluster IP and Listener IP)
- Assigns 10.0.2.50 and 10.0.2.51 to SQL02 (for Cluster IP and Listener IP)

**Expected output:**
```
✅ SQL01 now has: Primary IP + 10.0.1.50 + 10.0.1.51
✅ SQL02 now has: Primary IP + 10.0.2.50 + 10.0.2.51
```

**IP Allocation:**
- **Cluster IPs:** 10.0.1.50 (Subnet 1), 10.0.2.50 (Subnet 2)
- **Listener IPs:** 10.0.1.51 (Subnet 1), 10.0.2.51 (Subnet 2)

### 5.2: Important Note About Windows Configuration

**⚠️ DO NOT manually configure these IPs in Windows!**

The secondary IPs are assigned at the AWS ENI level only. Windows Failover Cluster will automatically configure them when it brings cluster resources online. Manually adding them to Windows will break network connectivity.

**Important Note:**
This is a critical distinction in the way SQL Server Availability Groups are configured in AWS. 
Go through the following article and the video given at the link below to know more about this.

[article](https://docs.aws.amazon.com/sql-server-ec2/latest/userguide/aws-sql-ec2-clustering.html#sql-ip-assignment) 

[video](https://www.youtube.com/watch?v=9CqhH03vLeo)

**AUTOMATED APPROACH:** See `Scripts/README-Automation.md` for fully automated setup with zero GUI interaction for cluster/AG creation!



✅ **Checkpoint:** Secondary IPs assigned in AWS (Windows Cluster will handle the rest)

---

## Step 6: Create Windows Failover Cluster

### 6.1: Install Clustering Feature

On **both SQL01 and SQL02**:

```powershell
cd C:\SQLAGScripts
.\04-Install-Failover-Clustering.ps1
```

### 6.2: Create Cluster

#### Option A: Automated (No Prompts - Recommended)

On **SQL01 only**:

```powershell
cd C:\SQLAGScripts

# Verify secondary IPs are assigned (optional but recommended)
.\04d-Verify-Secondary-IPs.ps1

# Create cluster with automatic IP detection
.\05-Create-WSFC.ps1

# Or explicitly specify IPs
.\05-Create-WSFC.ps1 -ClusterIP1 "10.0.1.50" -ClusterIP2 "10.0.2.50"
```

**What happens:** The script automatically uses the secondary IPs assigned at the AWS ENI level. No GUI interaction needed!

#### Option B: Interactive (Original)

On **SQL01 only**:

```powershell
cd C:\SQLAGScripts
.\05-Create-WSFC.ps1

# When prompted for Cluster IPs, use the ones assigned in Step 5:
# Cluster IP 1 (Subnet 1): 10.0.1.50
# Cluster IP 2 (Subnet 2): 10.0.2.50
```

✅ **Checkpoint:** Cluster created and both nodes online

**Note:** The cluster IPs should be `.50` addresses (10.0.1.50, 10.0.2.50), not `.100` as previously shown. The `.51` addresses are reserved for the AG Listener.

---

## Step 7: Install SQL Server

### 7.1: Download SQL Server

On **both SQL01 and SQL02**:

1. Open browser (Server Manager → Local Server → IE Enhanced Security: Off)
2. Go to: https://www.microsoft.com/sql-server/sql-server-downloads
3. Download **SQL Server 2022 Developer Edition**
4. Choose **Custom** install
5. Download media to: `C:\SQLInstall`

### 7.2: Prepare for Installation

###Note###
Before you proceed with executing the script 06-Install-SQLServer-Prep.ps1, you need to ensure that the AD Web Services is running on the DC01 and the required ports are opened on the Security Group.

1. .\Fix-ADWS.ps1 on DC01
2. .\add-security-group-rules.sh on your local machine


On **both SQL01 and SQL02**:

```powershell
cd C:\SQLAGScripts
.\06-Install-SQLServer-Prep.ps1
```

### 7.3: Run SQL Setup

On **both SQL01 and SQL02**:

1. Navigate to `C:\SQLInstall`
2. Run `setup.exe`
3. **Installation Type:** New SQL Server stand-alone installation
4. **Product Key:** Auto-selected (Developer Edition)
5. **Features:** Select:
   - Database Engine Services
   - SQL Server Replication
   - Full-Text and Semantic Extractions
6. **Instance:** MSSQLSERVER (default instance)
7. **Server Configuration:**
   - SQL Server Database Engine: `CONTOSO\sqlsvc$` (leave password blank)
   - SQL Server Agent: `CONTOSO\sqlagent$` (leave password blank)
   - Startup Type: Automatic
8. **Database Engine Configuration:**
   - Authentication: Windows authentication mode
   - SQL Administrators: Add `CONTOSO\sqladmin` and `BUILTIN\Administrators`
9. **Install** (~15-20 minutes)

### 7.4: Enable AlwaysOn

On **both SQL01 and SQL02** after SQL installation completes:

```powershell
cd C:\SQLAGScripts
.\07-Enable-AlwaysOn.ps1
```

✅ **Checkpoint:** SQL installed with AlwaysOn enabled on both nodes

---

## Step 8: Create Availability Group

### 8.1: Create Test Database

On **SQL01**, open **SQL Server Management Studio** (SSMS) and run:

```powershell
# Or from PowerShell
sqlcmd -S SQL01 -i C:\SQLAGScripts\08-Create-TestDatabase.sql
```

### 8.2: Copy Backup Files

On **SQL01**:

```powershell
# Share the backup folder (should already be done by script)
# SQL Server 2022 uses MSSQL16
$backupPath = "D:\MSSQL\BACKUP"
New-SmbShare -Name "SQLBackup" -Path $backupPath -FullAccess "Everyone"
```

### 8.3: Create Availability Group

#### Option A: Automated (No Prompts - Recommended)

On **SQL01**:

```powershell
cd C:\SQLAGScripts

# Create AG with automatic IP detection
.\09-Create-AvailabilityGroup.ps1

# Or explicitly specify IPs
.\09-Create-AvailabilityGroup.ps1 -ListenerIP1 "10.0.1.51" -ListenerIP2 "10.0.2.51"
```

**What happens:** The script automatically uses the secondary IPs assigned at the AWS ENI level. The listener IPs will be brought online by Windows Failover Cluster without any GUI interaction!

#### Option B: Interactive (Original)

On **SQL01**:

```powershell
cd C:\SQLAGScripts
.\09-Create-AvailabilityGroup.ps1

# When prompted for Listener IPs, use the ones assigned in Step 5:
# Listener IP 1 (Subnet 1): 10.0.1.51
# Listener IP 2 (Subnet 2): 10.0.2.51
```

✅ **Checkpoint:** Availability Group created with listener

**Note:** The listener IPs should be `.51` addresses (10.0.1.51, 10.0.2.51), not `.101` as previously shown. These match the IPs assigned in Step 5.

---

## Step 9: Validate Setup

### 9.1: Check AG Health

On **SQL01** in SSMS:

```sql
-- Run validation script
:r C:\SQLAGScripts\Scripts\10-Validate-AG.sql
```

**Expected Results:**
- Both replicas: ONLINE, CONNECTED, HEALTHY
- Database: SYNCHRONIZED
- Listener: Shows DNS name and IP

### 9.2: Test Listener Connection

From any domain-joined machine:

```powershell
# Test DNS
nslookup SQLAGL01.contoso.local

# Test SQL connection
sqlcmd -S SQLAGL01,1433 -Q "SELECT @@SERVERNAME, DB_NAME()"
```

### 9.3: Test Failover

On **SQL02** in SSMS:

```sql
-- Manual failover to SQL02
ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;

-- Verify new primary
SELECT @@SERVERNAME AS CurrentPrimary;
```

Or test automatic failover:

```powershell
# On SQL01 (current primary)
Stop-Service MSSQLSERVER -Force

# Wait 10-15 seconds, then connect via listener
sqlcmd -S SQLAGL01,1433 -Q "SELECT @@SERVERNAME"
# Should show SQL02 as new primary
```

✅ **Checkpoint:** AG working with automatic failover

---

## Step 10: Cleanup

### When Done with Demo:

#### Option 1: Stop Instances (preserve setup)

```bash
# Get instance IDs from CloudFormation outputs
aws ec2 stop-instances --instance-ids i-xxx i-yyy i-zzz
```

#### Option 2: Delete Everything

```bash
# Delete CloudFormation stack (removes all resources)
aws cloudformation delete-stack --stack-name sql-ag-demo

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name sql-ag-demo
```

---

## Troubleshooting

### Issue: macOS - Can't get public IP
If `curl ifconfig.me` fails:
```bash
# Use AWS's service instead
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32
echo $MY_IP
```

### Issue: Can't track CloudFormation stack progress
Use these commands:
```bash
# Simple status check
aws cloudformation describe-stacks --stack-name sql-ag-demo --query "Stacks[0].StackStatus" --output text

# Detailed event stream (auto-refresh every 5 seconds)
while true; do clear; aws cloudformation describe-stack-events --stack-name sql-ag-demo --max-items 15 --query 'StackEvents[*].[Timestamp,ResourceStatus,LogicalResourceId]' --output table; sleep 5; done
```

### Issue: Can't RDP to instances
- Check your IP hasn't changed
- Update security group with new IP
- Verify instances are running

### Issue: Can't reach domain from SQL nodes
- Verify DC01 is running
- Check DNS on SQL nodes: `ipconfig /all`
- Should show DC01 private IP as DNS server
- Ping domain: `ping contoso.local`

### Issue: gMSA test fails
```powershell
# On SQL node
Test-ADServiceAccount -Identity sqlsvc

# If false, re-add computer account on DC01
Set-ADServiceAccount -Identity sqlsvc -PrincipalsAllowedToRetrieveManagedPassword SQL01$, SQL02$
```

### Issue: Cluster validation warnings
- Ignore storage warnings (we're not using shared storage)
- Network warnings are normal in AWS without multicast
- As long as both nodes are "Up", you're good

### Issue: Database won't synchronize
```sql
-- Check synchronization state
SELECT synchronization_state_desc FROM sys.dm_hadr_database_replica_states;

-- If SYNCHRONIZING and stuck, wait a few minutes
-- If NOT SYNCHRONIZING, resume:
ALTER DATABASE AGTestDB SET HADR RESUME;
```

---

## Quick Reference

### Connection Strings

```
# Via Listener (recommended)
Server=SQLAGL01,59999;Database=AGTestDB;Integrated Security=True;MultiSubnetFailover=True;

# Direct to primary
Server=SQL01;Database=AGTestDB;Integrated Security=True;
```

### Useful Commands

```sql
-- Check AG health
SELECT * FROM sys.dm_hadr_availability_group_states;

-- Force failover (emergency only)
ALTER AVAILABILITY GROUP SQLAOAG01 FORCE_FAILOVER_ALLOW_DATA_LOSS;

-- Change to async mode
ALTER AVAILABILITY GROUP SQLAOAG01
MODIFY REPLICA ON 'SQL02' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
```

```powershell
# Check cluster status
Get-ClusterNode
Get-ClusterResource

# Failover AG
Invoke-Sqlcmd -ServerInstance "SQL02" -Query "ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;"
```

### Default Credentials

- Domain: `contoso.local`
- Domain Admin: `CONTOSO\Administrator`
- SQL Admin: `CONTOSO\sqladmin` / `P@ssw0rd123!`
- SQL Service: `CONTOSO\sqlsvc$` (gMSA)
- SQL Agent: `CONTOSO\sqlagent$` (gMSA)

---

## Next Steps

1. **Add more databases** to the AG
2. **Configure backups** to S3
3. **Set up monitoring** with CloudWatch
4. **Test various failure scenarios**
5. **Practice restoring from AG**

For detailed explanations, see: **SQL-AG-Setup-Guide.md**

