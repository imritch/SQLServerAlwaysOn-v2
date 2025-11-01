# SQL Server Availability Group Setup in AWS - Complete Guide

## Overview
This guide walks you through creating a 2-node SQL Server Availability Group in AWS using:
- 3 EC2 instances (1 Domain Controller + 2 SQL Servers)
- Windows Server 2019
- Multi-subnet deployment across 2 availability zones
- gMSA for SQL Server service accounts
- SQL Server 2022 Developer Edition
- Windows Server Failover Cluster (WSFC) with multi-subnet support

**Estimated Setup Time:** 2-3 hours

---

## Multi-Subnet Architecture Overview

This setup implements a **production-ready multi-subnet Availability Group** configuration:

### Why Multi-Subnet?

- **High Availability:** Nodes in different availability zones survive AZ-level failures
- **Best Practice:** Recommended by Microsoft for production SQL Server AG deployments
- **Disaster Recovery:** Geographic separation of replicas
- **AWS Native:** Leverages AWS multi-AZ architecture

### Key Multi-Subnet Components

1. **Two Subnets in Different AZs:**
   - Subnet 1 (10.0.1.0/24) in AZ1: DC01 + SQL01
   - Subnet 2 (10.0.2.0/24) in AZ2: SQL02

2. **Cluster Name Object (CNO) with 2 IPs:**
   - IP 1: 10.0.1.50 (Subnet 1)
   - IP 2: 10.0.2.50 (Subnet 2)
   - Windows Cluster uses OR dependency (both IPs, one must be online)

3. **AG Listener with 2 IPs:**
   - IP 1: 10.0.1.51 (Subnet 1)
   - IP 2: 10.0.2.51 (Subnet 2)
   - Clients must use `MultiSubnetFailover=True` connection parameter

4. **Enhanced Failover Settings:**
   - CrossSubnetDelay: 1000ms (faster cross-subnet detection)
   - CrossSubnetThreshold: 5 (balanced sensitivity)

### Connection String Requirements

**CRITICAL:** Always use `MultiSubnetFailover=True` for multi-subnet AG:

```
Server=SQLAGL01,59999;Database=AGTestDB;Integrated Security=True;MultiSubnetFailover=True;
```

Without this parameter, failover to the other subnet can take 20-30 seconds instead of 1-2 seconds.

---

## Architecture

```
VPC (10.0.0.0/16) - SQL-AG-VPC
│
├─── Subnet 1 (10.0.1.0/24) - AZ1 (us-east-1a)
│    │
│    ├── Domain Controller (DC01) - t3.medium
│    │   └── Windows Server 2019
│    │   └── Active Directory Domain Services
│    │   └── IP: 10.0.1.x
│    │
│    ├── SQL Node 1 (SQL01) - t3.xlarge
│    │   └── Windows Server 2019
│    │   └── SQL Server 2022 Developer
│    │   └── Primary Replica
│    │   └── IP: 10.0.1.x
│    │
│    ├── Cluster CNO IP 1: 10.0.1.50
│    └── AG Listener IP 1: 10.0.1.51
│
└─── Subnet 2 (10.0.2.0/24) - AZ2 (us-east-1b)
     │
     ├── SQL Node 2 (SQL02) - t3.xlarge
     │   └── Windows Server 2019
     │   └── SQL Server 2022 Developer
     │   └── Secondary Replica
     │   └── IP: 10.0.2.x
     │
     ├── Cluster CNO IP 2: 10.0.2.50
     └── AG Listener IP 2: 10.0.2.51
```

**Domain:** contoso.local  
**AG Name:** SQLAOAG01  
**Listener Name:** SQLAGL01  
**Listener Port:** 59999  
**Multi-Subnet:** Yes (2 IPs for CNO, 2 IPs for Listener)  

---

## Phase 1: AWS Infrastructure Setup

### Step 1.1: Prepare Security Group

**Note:** If using the provided CloudFormation template, the VPC, subnets, and security groups are automatically created. This section is for manual setup only.

1. **Go to EC2 Console** → Security Groups
2. **Create Security Group:**
   - Name: `SQL-AG-SG`
   - Description: `Security group for SQL Server Availability Group`
   - VPC: SQL-AG-VPC (or your chosen VPC)

3. **Add Inbound Rules:**

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| RDP | TCP | 3389 | My IP | RDP Access |
| Custom TCP | TCP | 5022 | 172.31.0.0/16 | SQL AG Endpoint |
| Custom TCP | TCP | 1433 | 172.31.0.0/16 | SQL Server |
| Custom TCP | TCP | 1434 | 172.31.0.0/16 | SQL Browser |
| Custom TCP | TCP | 59999 | 172.31.0.0/16 | AG Listener |
| Custom TCP | TCP | 58888 | 172.31.0.0/16 | Probe Port |
| All ICMP-IPv4 | ICMP | All | 172.31.0.0/16 | Ping |
| All Traffic | All | All | sg-xxxxx (itself) | Internal cluster communication |

**Note:** For the last rule, after creating the SG, edit it and add a rule allowing "All Traffic" from the security group itself.

### Step 1.2: Create EC2 Instances

#### Domain Controller (DC01)

1. **Launch Instance:**
   - Name: `DC01`
   - AMI: Windows Server 2019 Base (latest)
   - Instance type: `t3.medium`
   - Key pair: Create or select existing
   - Network: Default VPC
   - Subnet: Any availability zone
   - Security Group: `SQL-AG-SG`
   - Storage: 50 GB gp3

2. **After launch, note the Private IP** (e.g., 172.31.x.x)

#### SQL Server Nodes

Repeat for SQL01 and SQL02:

1. **Launch Instance:**
   - Name: `SQL01` (then `SQL02`)
   - AMI: Windows Server 2019 Base (latest)
   - Instance type: `t3.xlarge`
   - Key pair: Same as DC01
   - Network: Default VPC
   - Subnet: **Different AZ from each other** (for HA)
   - Security Group: `SQL-AG-SG`
   - Storage: 100 GB gp3 (Root) + 50 GB gp3 (Data - add as D: drive)

2. **Add secondary network interface** (for cluster communication):
   - Go to Network & Security → Network Interfaces
   - Create network interface in the same subnet
   - Attach to SQL01/SQL02

3. **Disable Source/Destination Check:**
   - Select each instance → Actions → Networking → Change Source/Dest Check → Disable

### Step 1.3: Allocate Elastic IPs (Optional but Recommended)

For easier management during setup:
1. Allocate 3 Elastic IPs
2. Associate with DC01, SQL01, SQL02

**Note:** Release these after setup to save costs if you don't need persistent public IPs.

---

## Phase 2: Domain Controller Setup

### Step 2.1: Connect to DC01

1. Get Windows password using your key pair
2. RDP to DC01 using public IP
3. Login as `Administrator`

### Step 2.2: Configure DC01

**PowerShell Script: `01-Setup-DomainController.ps1`**

Save this script and run on DC01:

```powershell
# DC01 - Domain Controller Setup Script
# Run as Administrator

$ErrorActionPreference = "Stop"

# Configuration
$DomainName = "contoso.local"
$DomainNetBIOSName = "CONTOSO"
$SafeModePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

Write-Host "===== Domain Controller Setup for SQL AG =====" -ForegroundColor Green

# Step 1: Set static IP and rename computer
Write-Host "`n[1/6] Setting computer name..." -ForegroundColor Yellow
$CurrentName = $env:COMPUTERNAME
if ($CurrentName -ne "DC01") {
    Rename-Computer -NewName "DC01" -Force
    Write-Host "Computer renamed to DC01. Restart required after all steps." -ForegroundColor Cyan
}

# Step 2: Install AD DS Role
Write-Host "`n[2/6] Installing Active Directory Domain Services..." -ForegroundColor Yellow
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Step 3: Promote to Domain Controller
Write-Host "`n[3/6] Promoting to Domain Controller (this takes 5-10 minutes)..." -ForegroundColor Yellow
Write-Host "Domain: $DomainName" -ForegroundColor Cyan

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetBIOSName `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDns `
    -NoRebootOnCompletion `
    -Force

Write-Host "`n[4/6] Domain Controller installation complete!" -ForegroundColor Green
Write-Host "`nThe server will restart automatically in 30 seconds..." -ForegroundColor Yellow
Write-Host "After restart, run: 02-Configure-AD.ps1" -ForegroundColor Cyan

Start-Sleep -Seconds 30
Restart-Computer -Force
```

**After DC01 restarts (~5 minutes), RDP back in as `CONTOSO\Administrator`**

### Step 2.3: Configure Active Directory

**PowerShell Script: `02-Configure-AD.ps1`**

```powershell
# DC01 - Configure Active Directory for SQL AG
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

$DomainName = "contoso.local"
$DomainDN = "DC=contoso,DC=local"

Write-Host "===== Configuring Active Directory =====" -ForegroundColor Green

# Step 1: Create OUs
Write-Host "`n[1/5] Creating Organizational Units..." -ForegroundColor Yellow

$OUs = @("Servers", "ServiceAccounts", "SQLServers")
foreach ($OU in $OUs) {
    try {
        New-ADOrganizationalUnit -Name $OU -Path $DomainDN -ProtectedFromAccidentalDeletion $true
        Write-Host "Created OU: $OU" -ForegroundColor Green
    } catch {
        Write-Host "OU $OU may already exist: $_" -ForegroundColor Yellow
    }
}

# Step 2: Create KDS Root Key for gMSA
Write-Host "`n[2/5] Creating KDS Root Key for gMSA..." -ForegroundColor Yellow
Write-Host "Note: In production, this takes 10 hours to replicate. We're forcing immediate availability." -ForegroundColor Cyan

try {
    # Check if key already exists
    $existingKey = Get-KdsRootKey
    if ($existingKey) {
        Write-Host "KDS Root Key already exists" -ForegroundColor Yellow
    } else {
        # For lab/demo: EffectiveTime 10 hours ago (makes it immediately usable)
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
        Write-Host "KDS Root Key created successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "Error creating KDS Root Key: $_" -ForegroundColor Red
}

# Step 3: Create SQL Service gMSA
Write-Host "`n[3/5] Creating gMSA for SQL Server Service..." -ForegroundColor Yellow

$gMSAName = "sqlsvc"
$gMSADNSHostName = "$gMSAName.$DomainName"

try {
    New-ADServiceAccount -Name $gMSAName `
        -DNSHostName $gMSADNSHostName `
        -PrincipalsAllowedToRetrieveManagedPassword "SQL01$", "SQL02$" `
        -Path "OU=ServiceAccounts,$DomainDN" `
        -Enabled $true
    
    Write-Host "gMSA '$gMSAName' created successfully" -ForegroundColor Green
    Write-Host "Allowed principals: SQL01$, SQL02$" -ForegroundColor Cyan
} catch {
    Write-Host "gMSA may already exist: $_" -ForegroundColor Yellow
}

# Step 4: Create SQL Agent gMSA
Write-Host "`n[4/5] Creating gMSA for SQL Server Agent..." -ForegroundColor Yellow

$gMSAAgentName = "sqlagent"
$gMSAAgentDNSHostName = "$gMSAAgentName.$DomainName"

try {
    New-ADServiceAccount -Name $gMSAAgentName `
        -DNSHostName $gMSAAgentDNSHostName `
        -PrincipalsAllowedToRetrieveManagedPassword "SQL01$", "SQL02$" `
        -Path "OU=ServiceAccounts,$DomainDN" `
        -Enabled $true
    
    Write-Host "gMSA '$gMSAAgentName' created successfully" -ForegroundColor Green
} catch {
    Write-Host "gMSA may already exist: $_" -ForegroundColor Yellow
}

# Step 5: Create SQL Admin User
Write-Host "`n[5/5] Creating SQL Admin user..." -ForegroundColor Yellow

$SqlAdminUser = "sqladmin"
$SqlAdminPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

try {
    New-ADUser -Name $SqlAdminUser `
        -AccountPassword $SqlAdminPassword `
        -Path "OU=ServiceAccounts,$DomainDN" `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $false
    
    # Add to Domain Admins (for installation purposes)
    Add-ADGroupMember -Identity "Domain Admins" -Members $SqlAdminUser
    
    Write-Host "SQL Admin user created: $SqlAdminUser" -ForegroundColor Green
    Write-Host "Password: P@ssw0rd123!" -ForegroundColor Cyan
} catch {
    Write-Host "SQL Admin user may already exist: $_" -ForegroundColor Yellow
}

# Summary
Write-Host "`n===== Active Directory Configuration Complete =====" -ForegroundColor Green
Write-Host "`nCreated Resources:" -ForegroundColor Cyan
Write-Host "  - gMSA: CONTOSO\$gMSAName$ (SQL Service)"
Write-Host "  - gMSA: CONTOSO\$gMSAAgentName$ (SQL Agent)"
Write-Host "  - User: CONTOSO\$SqlAdminUser (Password: P@ssw0rd123!)"
Write-Host "`nNext: Join SQL01 and SQL02 to the domain" -ForegroundColor Yellow
```

---

## Phase 3: Join SQL Servers to Domain

### Step 3.1: Configure DNS on SQL Nodes

**Connect to SQL01 and SQL02** (do this on both)

**PowerShell Script: `03-Join-Domain.ps1`**

Run on both SQL01 and SQL02:

```powershell
# SQL01/SQL02 - Join to Domain
# Run as local Administrator

$ErrorActionPreference = "Stop"

# IMPORTANT: Update this with your DC01 private IP
$DC_IP = "172.31.X.X"  # <<< CHANGE THIS to your DC01 private IP
$DomainName = "contoso.local"
$DomainUser = "CONTOSO\Administrator"
$DomainPassword = "YourDCPassword"  # <<< CHANGE THIS

# Which node are we setting up?
$ComputerName = Read-Host "Enter computer name (SQL01 or SQL02)"

Write-Host "===== Joining $ComputerName to Domain =====" -ForegroundColor Green

# Step 1: Set DNS to point to DC
Write-Host "`n[1/4] Configuring DNS to point to Domain Controller..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DC_IP
Write-Host "DNS configured: $DC_IP" -ForegroundColor Green

# Step 2: Test domain connectivity
Write-Host "`n[2/4] Testing domain connectivity..." -ForegroundColor Yellow
$TestDomain = Test-Connection -ComputerName $DomainName -Count 2 -Quiet
if ($TestDomain) {
    Write-Host "Domain reachable!" -ForegroundColor Green
} else {
    Write-Host "ERROR: Cannot reach domain. Check DNS and DC status." -ForegroundColor Red
    exit
}

# Step 3: Rename computer
Write-Host "`n[3/4] Renaming computer to $ComputerName..." -ForegroundColor Yellow
$CurrentName = $env:COMPUTERNAME
if ($CurrentName -ne $ComputerName) {
    Rename-Computer -NewName $ComputerName -Force -PassThru
}

# Step 4: Join domain
Write-Host "`n[4/4] Joining domain $DomainName..." -ForegroundColor Yellow
$Password = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($DomainUser, $Password)

Add-Computer -DomainName $DomainName -Credential $Credential -Force

Write-Host "`n===== Domain Join Complete =====" -ForegroundColor Green
Write-Host "Computer will restart in 15 seconds..." -ForegroundColor Yellow
Write-Host "After restart, login as: CONTOSO\Administrator" -ForegroundColor Cyan

Start-Sleep -Seconds 15
Restart-Computer -Force
```

**After both servers restart, RDP as `CONTOSO\Administrator`**

---

## Phase 4: Install Failover Clustering

### Step 4.1: Install Required Features

**PowerShell Script: `04-Install-Failover-Clustering.ps1`**

Run on both SQL01 and SQL02:

```powershell
# SQL01/SQL02 - Install Failover Clustering Feature
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

Write-Host "===== Installing Failover Clustering =====" -ForegroundColor Green

# Install Failover Clustering with Management Tools
Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools

Write-Host "`nFailover Clustering installed successfully!" -ForegroundColor Green
Write-Host "Reboot recommended but not required." -ForegroundColor Yellow
Write-Host "`nNext: Run this on both SQL01 and SQL02, then create the cluster from SQL01" -ForegroundColor Cyan
```

### Step 4.2: Create Windows Failover Cluster

**Run on SQL01 only:**

**PowerShell Script: `05-Create-WSFC.ps1`**

```powershell
# SQL01 - Create Windows Server Failover Cluster
# Run as CONTOSO\Administrator on SQL01 only

$ErrorActionPreference = "Stop"

$ClusterName = "SQLCLUSTER"
$Node1 = "SQL01"
$Node2 = "SQL02"
$ClusterIP = "172.31.X.X"  # <<< CHANGE: Pick an unused IP in your subnet

Write-Host "===== Creating Windows Server Failover Cluster =====" -ForegroundColor Green

# Step 1: Test Cluster Configuration
Write-Host "`n[1/3] Testing cluster configuration..." -ForegroundColor Yellow
Write-Host "This may take a few minutes..." -ForegroundColor Cyan

$TestResult = Test-Cluster -Node $Node1, $Node2

if ($TestResult) {
    Write-Host "Cluster validation complete. Check C:\Windows\Cluster\Reports for results." -ForegroundColor Green
} else {
    Write-Host "WARNING: Cluster validation had issues. Continuing anyway..." -ForegroundColor Yellow
}

# Step 2: Create Cluster (No Storage)
Write-Host "`n[2/3] Creating failover cluster..." -ForegroundColor Yellow
Write-Host "Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "Nodes: $Node1, $Node2" -ForegroundColor Cyan
Write-Host "Note: Using NoStorage for SQL AG" -ForegroundColor Cyan

New-Cluster -Name $ClusterName `
    -Node $Node1, $Node2 `
    -NoStorage `
    -StaticAddress $ClusterIP `
    -Force

Write-Host "Cluster created successfully!" -ForegroundColor Green

# Step 3: Configure Cluster Quorum (Cloud Witness recommended for AWS)
Write-Host "`n[3/3] Configuring cluster quorum..." -ForegroundColor Yellow
Write-Host "Using Node and File Share Majority (for demo)" -ForegroundColor Cyan

# For demo: Node Majority (works for 2 nodes but not ideal)
Set-ClusterQuorum -NodeMajority

Write-Host "`nQuorum configured!" -ForegroundColor Green
Write-Host "`nPRODUCTION NOTE: Use AWS S3 for cloud witness in production." -ForegroundColor Yellow

# Summary
Write-Host "`n===== WSFC Creation Complete =====" -ForegroundColor Green
Write-Host "`nCluster Details:" -ForegroundColor Cyan
Get-Cluster | Format-List Name, Domain

Write-Host "`nCluster Nodes:" -ForegroundColor Cyan
Get-ClusterNode | Format-Table Name, State, ID -AutoSize

Write-Host "`nNext: Install SQL Server on both nodes" -ForegroundColor Yellow
```

---

## Phase 5: Install SQL Server

### Step 5.1: Download SQL Server Developer Edition

**On both SQL01 and SQL02:**

1. Open browser, go to: https://www.microsoft.com/en-us/sql-server/sql-server-downloads
2. Download **SQL Server 2022 Developer Edition**
3. Run the installer:
   - Choose "Custom" installation
   - Download media to: `C:\SQLInstall`

### Step 5.2: Install SQL Server

**PowerShell Script: `06-Install-SQLServer.ps1`**

Run on both SQL01 and SQL02:

```powershell
# SQL01/SQL02 - Install SQL Server with gMSA
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

# Configuration
$ComputerName = $env:COMPUTERNAME
$gMSASqlService = "CONTOSO\sqlsvc$"
$gMSASqlAgent = "CONTOSO\sqlagent$"
$SqlAdminAccount = "CONTOSO\sqladmin"

Write-Host "===== SQL Server Installation on $ComputerName =====" -ForegroundColor Green

# Step 1: Install gMSA on this computer
Write-Host "`n[1/4] Installing gMSA accounts..." -ForegroundColor Yellow

try {
    Install-ADServiceAccount -Identity "sqlsvc"
    Install-ADServiceAccount -Identity "sqlagent"
    Write-Host "gMSAs installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error installing gMSAs: $_" -ForegroundColor Red
    Write-Host "Make sure AD module is available and KDS key has replicated." -ForegroundColor Yellow
}

# Step 2: Test gMSA
Write-Host "`n[2/4] Testing gMSA..." -ForegroundColor Yellow
$testSqlSvc = Test-ADServiceAccount -Identity "sqlsvc"
$testSqlAgent = Test-ADServiceAccount -Identity "sqlagent"

if ($testSqlSvc -and $testSqlAgent) {
    Write-Host "gMSA test successful!" -ForegroundColor Green
} else {
    Write-Host "WARNING: gMSA test failed. Installation may fail." -ForegroundColor Red
    Write-Host "SqlSvc: $testSqlSvc, SqlAgent: $testSqlAgent" -ForegroundColor Yellow
}

# Step 3: Create SQL Data directories
Write-Host "`n[3/4] Creating SQL Server directories..." -ForegroundColor Yellow

# SQL Server 2022 uses MSSQL16
$dirs = @(
    "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA",
    "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\LOG",
    "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\BACKUP"
)

foreach ($dir in $dirs) {
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue
}

# Step 4: SQL Server Installation
Write-Host "`n[4/4] Installing SQL Server..." -ForegroundColor Yellow
Write-Host "This will take 15-20 minutes..." -ForegroundColor Cyan
Write-Host "`nIMPORTANT: Run the following command manually:" -ForegroundColor Red
Write-Host "Navigate to C:\SQLInstall and run setup.exe with these parameters:`n" -ForegroundColor Yellow

$installCmd = @"
setup.exe /Q /ACTION=Install /FEATURES=SQLENGINE,REPLICATION,FULLTEXT,CONN /INSTANCENAME=MSSQLSERVER /SQLSVCACCOUNT="$gMSASqlService" /AGTSVCACCOUNT="$gMSASqlAgent" /SQLSYSADMINACCOUNTS="$SqlAdminAccount" "BUILTIN\Administrators" /TCPENABLED=1 /IACCEPTSQLSERVERLICENSETERMS
"@

Write-Host $installCmd -ForegroundColor Cyan

Write-Host "`n===== After SQL Installation =====" -ForegroundColor Green
Write-Host "1. Restart SQL Service" -ForegroundColor Yellow
Write-Host "2. Enable AlwaysOn from SQL Server Configuration Manager" -ForegroundColor Yellow
Write-Host "3. Restart SQL Service again" -ForegroundColor Yellow
```

### Step 5.3: Manual SQL Installation Steps

Since gMSA requires specific handling:

1. **Navigate to:** `C:\SQLInstall`
2. **Run setup.exe**
3. **Select:** New SQL Server stand-alone installation
4. **Product Key:** Developer Edition (auto-selected)
5. **License Terms:** Accept
6. **Features:**
   - Database Engine Services
   - SQL Server Replication
   - Full-Text and Semantic Extractions
7. **Instance:** Default (MSSQLSERVER)
8. **Service Accounts:**
   - SQL Server Database Engine: `CONTOSO\sqlsvc$` (no password needed)
   - SQL Server Agent: `CONTOSO\sqlagent$` (no password needed)
9. **Server Configuration:**
   - Add `CONTOSO\sqladmin` as SQL Server Administrator
   - Add `BUILTIN\Administrators`
10. **Data Directories:** Use defaults or customize
11. **Install!**

### Step 5.4: Enable AlwaysOn

**On both SQL01 and SQL02:**

```powershell
# Enable AlwaysOn High Availability
# Run as Administrator

# Enable AlwaysOn using PowerShell
Enable-SqlAlwaysOn -ServerInstance $env:COMPUTERNAME -Force

# Restart SQL Service
Restart-Service MSSQLSERVER -Force

Write-Host "AlwaysOn enabled. SQL Service restarted." -ForegroundColor Green
```

Or manually:
1. Open **SQL Server Configuration Manager**
2. Right-click **SQL Server (MSSQLSERVER)** → Properties
3. **AlwaysOn High Availability** tab
4. Check **Enable AlwaysOn Availability Groups**
5. Click OK
6. **Restart SQL Server service**

---

## Phase 6: Create Availability Group

### Step 6.1: Create Test Database

**On SQL01, run in SSMS:**

```sql
-- Create sample database for AG
CREATE DATABASE AGTestDB;
GO

-- Set Recovery Model to FULL (required for AG)
ALTER DATABASE AGTestDB SET RECOVERY FULL;
GO

-- Create sample table
USE AGTestDB;
GO

CREATE TABLE dbo.TestData (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    DataValue NVARCHAR(100),
    CreatedDate DATETIME DEFAULT GETDATE()
);
GO

INSERT INTO dbo.TestData (DataValue)
VALUES ('Sample Data 1'), ('Sample Data 2'), ('Sample Data 3');
GO

-- Take full backup (required before adding to AG)
-- SQL Server 2022 uses MSSQL16
BACKUP DATABASE AGTestDB 
TO DISK = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\BACKUP\AGTestDB_Full.bak'
WITH FORMAT, INIT, COMPRESSION;
GO

-- Take log backup
BACKUP LOG AGTestDB 
TO DISK = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\BACKUP\AGTestDB_Log.trn'
WITH FORMAT, INIT, COMPRESSION;
GO
```

### Step 6.2: Create Availability Group

**PowerShell Script: `07-Create-AvailabilityGroup.ps1`**

Run on SQL01:

```powershell
# SQL01 - Create Availability Group
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

# Import SQL PowerShell module
Import-Module SqlServer

# Configuration
$AGName = "SQLAOAG01"
$ListenerName = "SQLAGL01"
$ListenerIP = "172.31.X.X"  # <<< CHANGE: Pick an unused IP
$ListenerPort = 59999
$EndpointPort = 5022
$DatabaseName = "AGTestDB"
$PrimaryReplica = "SQL01"
$SecondaryReplica = "SQL02"

Write-Host "===== Creating Availability Group =====" -ForegroundColor Green

# Step 1: Create Database Mirroring Endpoints on both replicas
Write-Host "`n[1/5] Creating database mirroring endpoints..." -ForegroundColor Yellow

# SQL01 Endpoint
$endpoint1Script = @"
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint')
BEGIN
    CREATE ENDPOINT Hadr_endpoint
    STATE = STARTED
    AS TCP (LISTENER_PORT = $EndpointPort)
    FOR DATABASE_MIRRORING (ROLE = ALL);
END
GO

GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [CONTOSO\sqlsvc$];
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $endpoint1Script
Write-Host "Endpoint created on $PrimaryReplica" -ForegroundColor Green

# SQL02 Endpoint
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $endpoint1Script
Write-Host "Endpoint created on $SecondaryReplica" -ForegroundColor Green

# Step 2: Create Availability Group on Primary
Write-Host "`n[2/5] Creating Availability Group on primary replica..." -ForegroundColor Yellow

$createAGScript = @"
CREATE AVAILABILITY GROUP [$AGName]
WITH (AUTOMATED_BACKUP_PREFERENCE = SECONDARY)
FOR DATABASE [$DatabaseName]
REPLICA ON 
    N'$PrimaryReplica' WITH (
        ENDPOINT_URL = N'TCP://$PrimaryReplica.contoso.local:$EndpointPort',
        FAILOVER_MODE = AUTOMATIC,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
        SEEDING_MODE = MANUAL
    ),
    N'$SecondaryReplica' WITH (
        ENDPOINT_URL = N'TCP://$SecondaryReplica.contoso.local:$EndpointPort',
        FAILOVER_MODE = AUTOMATIC,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
        SEEDING_MODE = MANUAL
    );
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createAGScript
Write-Host "Availability Group '$AGName' created on $PrimaryReplica" -ForegroundColor Green

# Step 3: Join Secondary Replica
Write-Host "`n[3/5] Joining secondary replica to AG..." -ForegroundColor Yellow

$joinAGScript = "ALTER AVAILABILITY GROUP [$AGName] JOIN;"
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinAGScript
Write-Host "$SecondaryReplica joined to AG" -ForegroundColor Green

# Step 4: Restore database on Secondary
Write-Host "`n[4/5] Restoring database on secondary replica..." -ForegroundColor Yellow

# Copy backup files to SQL02
# SQL Server 2022 uses MSSQL16
$backupPath = "\\SQL01\C$\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\BACKUP"
$localBackupPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\BACKUP"

Write-Host "Restoring full backup..." -ForegroundColor Cyan
$restoreFullScript = @"
RESTORE DATABASE [$DatabaseName]
FROM DISK = N'$localBackupPath\AGTestDB_Full.bak'
WITH NORECOVERY, REPLACE;
GO
"@
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $restoreFullScript

Write-Host "Restoring log backup..." -ForegroundColor Cyan
$restoreLogScript = @"
RESTORE LOG [$DatabaseName]
FROM DISK = N'$localBackupPath\AGTestDB_Log.trn'
WITH NORECOVERY;
GO
"@
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $restoreLogScript

# Join database to AG on secondary
Write-Host "Joining database to AG on secondary..." -ForegroundColor Cyan
$joinDBScript = "ALTER DATABASE [$DatabaseName] SET HADR AVAILABILITY GROUP = [$AGName];"
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinDBScript

Write-Host "Database joined to AG on $SecondaryReplica" -ForegroundColor Green

# Step 5: Create AG Listener
Write-Host "`n[5/5] Creating Availability Group Listener..." -ForegroundColor Yellow

$createListenerScript = @"
ALTER AVAILABILITY GROUP [$AGName]
ADD LISTENER N'$ListenerName' (
    WITH IP ((N'$ListenerIP', N'255.255.255.0')),
    PORT = $ListenerPort
);
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createListenerScript
Write-Host "Listener '$ListenerName' created" -ForegroundColor Green

# Summary
Write-Host "`n===== Availability Group Creation Complete! =====" -ForegroundColor Green
Write-Host "`nAG Details:" -ForegroundColor Cyan
Write-Host "  AG Name: $AGName"
Write-Host "  Listener: $ListenerName"
Write-Host "  Listener IP: $ListenerIP"
Write-Host "  Listener Port: $ListenerPort"
Write-Host "  Primary: $PrimaryReplica"
Write-Host "  Secondary: $SecondaryReplica"
Write-Host "  Database: $DatabaseName"

Write-Host "`nTest connection string:" -ForegroundColor Yellow
Write-Host "  Server=$ListenerName,$ListenerPort;Database=$DatabaseName;Integrated Security=True;" -ForegroundColor Cyan
```

### Step 6.3: Alternative - Create AG Using SSMS Wizard

If you prefer GUI:

1. **Connect to SQL01 in SSMS**
2. Expand **Always On High Availability**
3. Right-click **Availability Groups** → New Availability Group Wizard
4. **AG Name:** SQLAOAG01
5. **Select Database:** AGTestDB
6. **Specify Replicas:**
   - Add SQL01 (Primary)
   - Add SQL02 (Secondary)
   - Set both to Synchronous Commit, Automatic Failover
7. **Endpoints:** Use default settings (port 5022)
8. **Backup Preferences:** Secondary
9. **Listener:**
   - Name: SQLAGL01
   - Port: 59999
   - IP: Static IP in your subnet
10. **Data Synchronization:** Full
11. **Validation** → **Finish**

---

## Phase 7: Validation and Testing

### Step 7.1: Check AG Health

**Run on SQL01:**

```sql
-- Check AG status
SELECT 
    ag.name AS AGName,
    ar.replica_server_name AS ReplicaName,
    ar.availability_mode_desc AS AvailabilityMode,
    ar.failover_mode_desc AS FailoverMode,
    ars.role_desc AS Role,
    ars.operational_state_desc AS OperationalState,
    ars.connected_state_desc AS ConnectedState,
    ars.synchronization_health_desc AS SyncHealth
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ar.replica_server_name;

-- Check database synchronization
SELECT 
    db_name(drs.database_id) AS DatabaseName,
    ar.replica_server_name AS ReplicaName,
    drs.synchronization_state_desc AS SyncState,
    drs.synchronization_health_desc AS SyncHealth,
    drs.database_state_desc AS DatabaseState
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
ORDER BY DatabaseName, ReplicaName;

-- Check AG Listener
SELECT 
    listener_id,
    dns_name,
    port,
    ip_configuration_string_from_cluster
FROM sys.availability_group_listeners;
```

Expected results:
- Both replicas: ONLINE, CONNECTED, HEALTHY
- Database: SYNCHRONIZED
- Listener shows correct DNS name and IP

### Step 7.2: Test Listener Connection

**From any machine in the domain:**

```powershell
# Test DNS resolution
nslookup SQLAGL01.contoso.local

# Test SQL connection
sqlcmd -S SQLAGL01,59999 -Q "SELECT @@SERVERNAME, DB_NAME()"
```

### Step 7.3: Test Failover

**In SSMS on SQL01:**

```sql
-- Manual failover to SQL02
ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;
GO
```

Or in PowerShell:

```powershell
# Failover to SQL02
Invoke-Sqlcmd -ServerInstance "SQL02" -Query "ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;"

# Check new primary
Invoke-Sqlcmd -ServerInstance "SQLAGL01,59999" -Query "SELECT @@SERVERNAME AS CurrentPrimary;"
```

### Step 7.4: Test Automatic Failover

1. **Simulate failure:** Stop SQL Service on the primary node
2. **Observe:** AG should automatically failover to secondary
3. **Check:** Connect to listener should still work
4. **Verify:** Data is accessible

```powershell
# On current primary node
Stop-Service MSSQLSERVER

# Wait 10-15 seconds, then check from SQL02
Invoke-Sqlcmd -ServerInstance "SQLAGL01,59999" -Query "SELECT @@SERVERNAME AS NewPrimary;"
```

---

## Phase 8: AWS-Specific Considerations

### Load Balancer Configuration (Optional)

For production-like setup with health checks:

1. **Create Network Load Balancer:**
   - Type: Internal
   - Scheme: TCP
   - Port: 59999
   - Target Group: SQL01 and SQL02 on port 59999
   - Health Check: TCP on port 58888

2. **Configure probe port on SQL:**

```sql
-- On SQL01
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'clr enabled', 1;
RECONFIGURE;

-- Create health check script for NLB
-- (Not detailed here, but involves custom health check endpoint)
```

### Backup Configuration

```sql
-- Configure automated backups to S3 (requires SQL Server S3 integration)
-- Or use AWS Backup with VSS for EC2 EBS volumes

-- Set backup preference to secondary
ALTER AVAILABILITY GROUP SQLAOAG01
MODIFY REPLICA ON 'SQL02' 
WITH (BACKUP_PRIORITY = 100);
```

### Monitoring

Set up CloudWatch metrics:

```powershell
# Install CloudWatch agent on all nodes
# Monitor:
# - SQL Server performance counters
# - AG health metrics
# - Windows event logs
```

---

## Troubleshooting Guide

### Issue: Cannot join domain

**Solution:**
- Verify DNS is set to DC IP
- Ping DC from SQL node
- Check security groups allow all traffic between VMs

### Issue: gMSA test fails

**Solution:**
```powershell
# On SQL node
Test-ADServiceAccount -Identity sqlsvc

# Check principals
Get-ADServiceAccount -Identity sqlsvc -Properties PrincipalsAllowedToRetrieveManagedPassword

# Re-add computer account
Set-ADServiceAccount -Identity sqlsvc -PrincipalsAllowedToRetrieveManagedPassword SQL01$, SQL02$
```

### Issue: Cluster validation fails

**Solution:**
- Ignore storage warnings (we're not using shared storage)
- Verify network connectivity between nodes
- Check firewall rules allow cluster communication

### Issue: AG endpoint connection timeout

**Solution:**
```sql
-- Check endpoint status
SELECT name, state_desc, port FROM sys.tcp_endpoints WHERE type_desc = 'DATABASE_MIRRORING';

-- Grant connect permission
GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [CONTOSO\sqlsvc$];
```

### Issue: Database won't synchronize

**Solution:**
```sql
-- Check synchronization state
SELECT database_id, synchronization_state_desc, synchronization_health_desc
FROM sys.dm_hadr_database_replica_states;

-- If stuck, try resuming
ALTER DATABASE AGTestDB SET HADR RESUME;
```

### Issue: Listener not resolving

**Solution:**
```powershell
# Check DNS from client
nslookup SQLAGL01.contoso.local

# Check cluster network name resource
Get-ClusterResource | Where-Object {$_.ResourceType -eq "Network Name"}

# Bring listener online
Get-ClusterResource -Name "SQLAGL01" | Start-ClusterResource
```

---

## Cleanup Instructions

When you're done with the demo:

### Option 1: Stop Instances (preserves setup for restart)

```powershell
# From AWS CLI or Console
aws ec2 stop-instances --instance-ids i-xxx i-yyy i-zzz
```

### Option 2: Complete Teardown

1. **Delete AG:**
```sql
DROP AVAILABILITY GROUP SQLAOAG01;
```

2. **Remove Cluster:**
```powershell
Remove-Cluster -Force -CleanupAD
```

3. **Terminate EC2 Instances** (Console or CLI)

4. **Delete Security Group**

5. **Release Elastic IPs** (if allocated)

**Estimated monthly cost if left running:** ~$275
**Cost per hour:** ~$0.38

---

## Quick Reference

### Connection Strings

```
# Direct connection to primary
Server=SQL01;Database=AGTestDB;Integrated Security=True;

# Connection via listener (recommended)
Server=SQLAGL01,59999;Database=AGTestDB;Integrated Security=True;

# With failover partner (old-style)
Server=SQL01;Failover_Partner=SQL02;Database=AGTestDB;Integrated Security=True;

# Multi-subnet failover (recommended for AWS)
Server=SQLAGL01,59999;Database=AGTestDB;Integrated Security=True;MultiSubnetFailover=True;
```

### Useful Commands

```sql
-- Check AG health
SELECT * FROM sys.dm_hadr_availability_group_states;

-- Force failover (with data loss - emergency only)
ALTER AVAILABILITY GROUP SQLAOAG01 FORCE_FAILOVER_ALLOW_DATA_LOSS;

-- Add database to AG
ALTER AVAILABILITY GROUP SQLAOAG01 ADD DATABASE [NewDB];

-- Remove database from AG
ALTER AVAILABILITY GROUP SQLAOAG01 REMOVE DATABASE [OldDB];

-- Change to async mode (for latency issues)
ALTER AVAILABILITY GROUP SQLAOAG01
MODIFY REPLICA ON 'SQL02' WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);
```

```powershell
# Check cluster status
Get-ClusterNode
Get-ClusterResource
Get-ClusterGroup

# Test AG
Test-SqlAvailabilityGroup -Path "SQLSERVER:\SQL\SQL01\DEFAULT\AvailabilityGroups\SQLAOAG01"

# Get AG status
Get-ChildItem "SQLSERVER:\SQL\SQL01\DEFAULT\AvailabilityGroups\SQLAOAG01"
```

---

## Additional Resources

- [SQL Server AlwaysOn on AWS Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/sql-server-ec2-best-practices/high-availability.html)
- [gMSA Documentation](https://docs.microsoft.com/en-us/windows-server/security/group-managed-service-accounts/group-managed-service-accounts-overview)
- [SQL Server AG Documentation](https://docs.microsoft.com/en-us/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server)

---

## Document Version

**Version:** 2.0  
**Last Updated:** October 2025  
**Tested On:** AWS EC2, Windows Server 2019, SQL Server 2022 Developer, Multi-Subnet Deployment


