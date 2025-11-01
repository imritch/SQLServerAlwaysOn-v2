# SQL01/SQL02 - Prepare for SQL Server Installation
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

# Configuration
$ComputerName = $env:COMPUTERNAME
$gMSASqlService = "CONTOSO\sqlsvc$"
$gMSASqlAgent = "CONTOSO\sqlagent$"
$SqlAdminAccount = "CONTOSO\sqladmin"

Write-Host "===== SQL Server Installation Preparation on $ComputerName =====" -ForegroundColor Green

# Step 0: Ensure RSAT AD PowerShell module is installed
Write-Host "`n[0/3] Checking RSAT AD PowerShell module..." -ForegroundColor Yellow
$adModule = Get-WindowsFeature -Name RSAT-AD-PowerShell
if (-not $adModule.Installed) {
    Write-Host "RSAT AD PowerShell module not found. Installing..." -ForegroundColor Cyan
    try {
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
        Write-Host "RSAT AD PowerShell module installed successfully" -ForegroundColor Green
        Import-Module ActiveDirectory
    } catch {
        Write-Host "ERROR: Could not install RSAT AD PowerShell module: $_" -ForegroundColor Red
        Write-Host "Install manually from Server Manager: AD DS and AD LDS Tools" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "RSAT AD PowerShell module already installed" -ForegroundColor Green
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
}

# Step 1: Install gMSA on this computer
Write-Host "`n[1/3] Installing gMSA accounts..." -ForegroundColor Yellow

try {
    Install-ADServiceAccount -Identity "sqlsvc"
    Install-ADServiceAccount -Identity "sqlagent"
    Write-Host "gMSAs installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Error installing gMSAs: $_" -ForegroundColor Red
    Write-Host "Make sure AD module is available and KDS key has replicated." -ForegroundColor Yellow
}

# Step 2: Test gMSA
Write-Host "`n[2/3] Testing gMSA..." -ForegroundColor Yellow
$testSqlSvc = Test-ADServiceAccount -Identity "sqlsvc"
$testSqlAgent = Test-ADServiceAccount -Identity "sqlagent"

if ($testSqlSvc -and $testSqlAgent) {
    Write-Host "gMSA test successful!" -ForegroundColor Green
} else {
    Write-Host "WARNING: gMSA test failed. Installation may fail." -ForegroundColor Red
    Write-Host "SqlSvc: $testSqlSvc, SqlAgent: $testSqlAgent" -ForegroundColor Yellow
}

# Step 3: Create SQL Server 2022 directories
Write-Host "`n[3/3] Creating SQL Server 2022 directories..." -ForegroundColor Yellow

$dirs = @(
    "D:\MSSQL\DATA",
    "D:\MSSQL\LOG",
    "D:\MSSQL\BACKUP"
)

foreach ($dir in $dirs) {
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue
}

Write-Host "`n===== Preparation Complete =====" -ForegroundColor Green
Write-Host "`nNow download and run SQL Server 2022 Developer Edition Setup:" -ForegroundColor Yellow
Write-Host "Download from: https://www.microsoft.com/sql-server/sql-server-downloads" -ForegroundColor Cyan
Write-Host "`nSetup configuration:" -ForegroundColor Yellow
Write-Host "1. Features: Database Engine, Replication, Full-Text" -ForegroundColor Cyan
Write-Host "2. Instance: MSSQLSERVER (default)" -ForegroundColor Cyan
Write-Host "3. SQL Service Account: $gMSASqlService (no password)" -ForegroundColor Cyan
Write-Host "4. Agent Service Account: $gMSASqlAgent (no password)" -ForegroundColor Cyan
Write-Host "5. SQL Admins: Add CONTOSO\sqladmin and BUILTIN\Administrators" -ForegroundColor Cyan
Write-Host "`nAfter SQL Server 2022 installation, run: 07-Enable-AlwaysOn.ps1" -ForegroundColor Yellow