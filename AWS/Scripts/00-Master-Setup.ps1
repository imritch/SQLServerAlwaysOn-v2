# Master Setup Script - Run sections as appropriate on each server
# This script is designed for fully automated deployment

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('DC', 'SQL-Pre-Cluster', 'SQL-Post-Cluster')]
    [string]$Phase,
    
    [string]$DCPrivateIP = "",
    [string]$DomainPassword = "",
    [string]$ComputerName = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

Write-Host "===== SQL Server Always On - Master Setup Script =====" -ForegroundColor Green
Write-Host "Phase: $Phase" -ForegroundColor Cyan
Write-Host "Script Directory: $ScriptDir" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# PHASE 1: Domain Controller Setup
# =============================================================================
if ($Phase -eq 'DC') {
    Write-Host "===== PHASE 1: Domain Controller Setup =====" -ForegroundColor Yellow
    Write-Host ""
    
    # Step 1: Setup Domain Controller
    Write-Host "[1/3] Setting up Domain Controller..." -ForegroundColor Yellow
    & "$ScriptDir\01-Setup-DomainController.ps1"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Domain Controller setup failed" -ForegroundColor Red
        exit 1
    }
    
    # Check if restart is needed
    $needsRestart = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue) -ne $null
    
    if ($needsRestart) {
        Write-Host ""
        Write-Host "===== SERVER RESTART REQUIRED =====" -ForegroundColor Red
        Write-Host "After restart, run the following commands:" -ForegroundColor Yellow
        Write-Host "  cd $ScriptDir" -ForegroundColor Cyan
        Write-Host "  .\01-Setup-DomainController.ps1  # Run again after reboot" -ForegroundColor Cyan
        Write-Host "  .\02-Configure-AD.ps1" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Or use Master Setup:" -ForegroundColor Yellow
        Write-Host "  .\00-Master-Setup.ps1 -Phase DC  # Will run AD configuration" -ForegroundColor Cyan
        Write-Host ""
        Read-Host "Press Enter to restart now"
        Restart-Computer -Force
        exit 0
    }
    
    # Step 2: Configure Active Directory (only if no restart needed)
    Write-Host "[2/3] Configuring Active Directory..." -ForegroundColor Yellow
    & "$ScriptDir\02-Configure-AD.ps1"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: AD configuration failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "===== DC SETUP COMPLETE! =====" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Setup SQL nodes by running on each:" -ForegroundColor White
    Write-Host "   .\00-Master-Setup.ps1 -Phase SQL-Pre-Cluster -DCPrivateIP <DC_IP> -DomainPassword <password> -ComputerName SQL01" -ForegroundColor Cyan
    Write-Host ""
}

# =============================================================================
# PHASE 2: SQL Node Setup (Before Cluster Creation)
# =============================================================================
elseif ($Phase -eq 'SQL-Pre-Cluster') {
    Write-Host "===== PHASE 2: SQL Node Pre-Cluster Setup =====" -ForegroundColor Yellow
    Write-Host ""
    
    if ([string]::IsNullOrWhiteSpace($DCPrivateIP)) {
        $DCPrivateIP = Read-Host "Enter DC Private IP"
    }
    
    if ([string]::IsNullOrWhiteSpace($DomainPassword)) {
        $securePassword = Read-Host "Enter Domain Password" -AsSecureString
        $DomainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    }
    
    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        $ComputerName = Read-Host "Enter Computer Name (SQL01 or SQL02)"
    }
    
    # Step 1: Join Domain
    Write-Host "[1/1] Joining domain..." -ForegroundColor Yellow
    
    # Inline domain join to avoid interactive prompt
    Write-Host "Configuring DNS..." -ForegroundColor Cyan
    $Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses $DCPrivateIP
    
    Start-Sleep -Seconds 5
    
    Write-Host "Testing domain connectivity..." -ForegroundColor Cyan
    $domainTest = Test-Connection -ComputerName "contoso.local" -Count 2 -Quiet
    
    if (-not $domainTest) {
        Write-Host "ERROR: Cannot reach domain. Check DC IP and network." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Renaming computer to $ComputerName..." -ForegroundColor Cyan
    Rename-Computer -NewName $ComputerName -Force
    
    Write-Host "Joining domain..." -ForegroundColor Cyan
    $secPass = ConvertTo-SecureString $DomainPassword -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential ("CONTOSO\Administrator", $secPass)
    
    Add-Computer -DomainName "contoso.local" -Credential $cred -Force
    
    Write-Host ""
    Write-Host "===== DOMAIN JOIN COMPLETE! =====" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Server will restart now" -ForegroundColor White
    Write-Host "2. After restart, RDP as CONTOSO\Administrator" -ForegroundColor White
    Write-Host "3. On DC01, run: .\02b-Update-gMSA-Permissions.ps1" -ForegroundColor White
    Write-Host "4. Repeat SQL-Pre-Cluster phase on other SQL node" -ForegroundColor White
    Write-Host "5. Run AWS IP assignment script from your local machine:" -ForegroundColor White
    Write-Host "   ./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1" -ForegroundColor Cyan
    Write-Host "6. Then on SQL01 run: .\00-Master-Setup.ps1 -Phase SQL-Post-Cluster" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter to restart now"
    Restart-Computer -Force
    exit 0
}

# =============================================================================
# PHASE 3: SQL Cluster and AG Setup (Run on SQL01 only)
# =============================================================================
elseif ($Phase -eq 'SQL-Post-Cluster') {
    Write-Host "===== PHASE 3: SQL Cluster and AG Setup =====" -ForegroundColor Yellow
    Write-Host ""
    
    $currentComputer = $env:COMPUTERNAME
    if ($currentComputer -ne "SQL01") {
        Write-Host "WARNING: This phase should be run on SQL01 only!" -ForegroundColor Red
        $continue = Read-Host "Continue anyway? (yes/no)"
        if ($continue -ne "yes") {
            exit 1
        }
    }
    
    # Step 1: Install Failover Clustering on both nodes
    Write-Host "[1/7] Installing Failover Clustering feature..." -ForegroundColor Yellow
    Write-Host "Installing on SQL01..." -ForegroundColor Cyan
    & "$ScriptDir\04-Install-Failover-Clustering.ps1"
    
    Write-Host "Installing on SQL02 remotely..." -ForegroundColor Cyan
    Invoke-Command -ComputerName SQL02 -ScriptBlock {
        param($scriptPath)
        & $scriptPath
    } -ArgumentList "$ScriptDir\04-Install-Failover-Clustering.ps1"
    
    Write-Host "Clustering feature installed on both nodes" -ForegroundColor Green
    Write-Host ""
    
    # Step 2: Verify Secondary IPs
    Write-Host "[2/7] Verifying secondary IP assignment..." -ForegroundColor Yellow
    & "$ScriptDir\04d-Verify-Secondary-IPs.ps1"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Secondary IP verification failed" -ForegroundColor Red
        Write-Host "Run this from your local machine first:" -ForegroundColor Yellow
        Write-Host "  ./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1" -ForegroundColor Cyan
        exit 1
    }
    
    # Step 3: Create WSFC
    Write-Host "[3/7] Creating Windows Failover Cluster..." -ForegroundColor Yellow
    & "$ScriptDir\05-Create-WSFC.ps1" -ClusterIP1 "10.0.1.50" -ClusterIP2 "10.0.2.50"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Cluster creation failed" -ForegroundColor Red
        exit 1
    }
    
    # Step 4: Prepare for SQL Installation
    Write-Host "[4/7] Preparing for SQL Server installation..." -ForegroundColor Yellow
    & "$ScriptDir\06-Install-SQLServer-Prep.ps1"
    
    Write-Host ""
    Write-Host "===== MANUAL STEP REQUIRED =====" -ForegroundColor Red
    Write-Host ""
    Write-Host "You must now install SQL Server 2022 on BOTH SQL01 and SQL02:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Download SQL Server 2022 Developer Edition from:" -ForegroundColor White
    Write-Host "   https://www.microsoft.com/sql-server/sql-server-downloads" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Run setup.exe on both nodes with these settings:" -ForegroundColor White
    Write-Host "   - Features: Database Engine, Replication, Full-Text" -ForegroundColor Cyan
    Write-Host "   - Instance: MSSQLSERVER (default)" -ForegroundColor Cyan
    Write-Host "   - SQL Server service account: CONTOSO\sqlsvc$ (gMSA - leave password blank)" -ForegroundColor Cyan
    Write-Host "   - SQL Agent service account: CONTOSO\sqlagent$ (gMSA - leave password blank)" -ForegroundColor Cyan
    Write-Host "   - Authentication: Windows" -ForegroundColor Cyan
    Write-Host "   - Add Administrators: CONTOSO\sqladmin and BUILTIN\Administrators" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "3. After SQL installation completes on BOTH nodes, run:" -ForegroundColor White
    Write-Host "   .\07-Enable-AlwaysOn.ps1 on BOTH SQL01 and SQL02" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "4. Then continue with AG creation:" -ForegroundColor White
    Write-Host "   On SQL01: sqlcmd -S SQL01 -i .\08-Create-TestDatabase.sql" -ForegroundColor Cyan
    Write-Host "   On SQL01: .\09-Create-AvailabilityGroup.ps1" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "Press Enter after SQL installation is complete on both nodes"
    
    # Step 5: Enable AlwaysOn
    Write-Host "[5/7] Enabling AlwaysOn on both nodes..." -ForegroundColor Yellow
    & "$ScriptDir\07-Enable-AlwaysOn.ps1"
    
    Invoke-Command -ComputerName SQL02 -ScriptBlock {
        param($scriptPath)
        & $scriptPath
    } -ArgumentList "$ScriptDir\07-Enable-AlwaysOn.ps1"
    
    Write-Host "AlwaysOn enabled on both nodes" -ForegroundColor Green
    Write-Host ""
    
    # Step 6: Create Test Database
    Write-Host "[6/7] Creating test database..." -ForegroundColor Yellow
    sqlcmd -S SQL01 -i "$ScriptDir\08-Create-TestDatabase.sql"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Database creation failed" -ForegroundColor Red
        exit 1
    }
    
    # Step 7: Create Availability Group
    Write-Host "[7/7] Creating Availability Group..." -ForegroundColor Yellow
    & "$ScriptDir\09-Create-AvailabilityGroup.ps1" -ListenerIP1 "10.0.1.51" -ListenerIP2 "10.0.2.51"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: AG creation failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "===== SETUP COMPLETE! =====" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your SQL Server Always On Availability Group is now ready!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Validate the setup:" -ForegroundColor Yellow
    Write-Host "  sqlcmd -S SQL01 -i .\10-Validate-AG.sql" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Test the listener:" -ForegroundColor Yellow
    Write-Host "  sqlcmd -S SQLAGL01,59999 -Q `"SELECT @@SERVERNAME, DB_NAME()`"" -ForegroundColor Cyan
    Write-Host ""
}

else {
    Write-Host "ERROR: Invalid phase specified" -ForegroundColor Red
    Write-Host "Valid phases: DC, SQL-Pre-Cluster, SQL-Post-Cluster" -ForegroundColor Yellow
    exit 1
}

