# Fix Active Directory Web Services (ADWS)
# Run this on DC01 as Administrator
# ADWS is required for AD PowerShell cmdlets to work from remote machines

$ErrorActionPreference = "Stop"

Write-Host "===== Active Directory Web Services (ADWS) Fix =====" -ForegroundColor Green
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if ADWS service exists
Write-Host "[1/4] Checking ADWS service..." -ForegroundColor Yellow
$adwsService = Get-Service -Name "ADWS" -ErrorAction SilentlyContinue

if (-not $adwsService) {
    Write-Host "  ✗ ADWS service not found!" -ForegroundColor Red
    Write-Host "  This should be installed with AD Domain Services." -ForegroundColor Yellow
    Write-Host "  Run: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Cyan
    exit 1
}

Write-Host "  ✓ ADWS service found: $($adwsService.DisplayName)" -ForegroundColor Green
Write-Host "    Status: $($adwsService.Status)" -ForegroundColor Cyan
Write-Host "    Startup Type: $($adwsService.StartType)" -ForegroundColor Cyan
Write-Host ""

# Step 2: Start ADWS if stopped
Write-Host "[2/4] Starting ADWS service..." -ForegroundColor Yellow

if ($adwsService.Status -ne "Running") {
    try {
        Start-Service -Name "ADWS"
        Write-Host "  ✓ ADWS service started" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to start ADWS: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ✓ ADWS service already running" -ForegroundColor Green
}

# Step 3: Set to automatic startup
Write-Host ""
Write-Host "[3/4] Setting ADWS to automatic startup..." -ForegroundColor Yellow

try {
    Set-Service -Name "ADWS" -StartupType Automatic
    Write-Host "  ✓ ADWS startup type set to Automatic" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not set startup type: $_" -ForegroundColor Yellow
}

# Step 4: Enable firewall rule for ADWS
Write-Host ""
Write-Host "[4/4] Enabling firewall rule for ADWS..." -ForegroundColor Yellow

try {
    # Enable the built-in ADWS firewall rule
    Enable-NetFirewallRule -DisplayName "Active Directory Web Services (TCP-In)" -ErrorAction Stop
    Write-Host "  ✓ ADWS firewall rule enabled" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not enable firewall rule (may not exist): $_" -ForegroundColor Yellow
    
    # Create a custom rule if the built-in one doesn't exist
    Write-Host "  Creating custom ADWS firewall rule..." -ForegroundColor Cyan
    try {
        New-NetFirewallRule -DisplayName "Active Directory Web Services (ADWS)" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 9389 `
            -Action Allow `
            -Enabled True `
            -ErrorAction Stop | Out-Null
        Write-Host "  ✓ Custom ADWS firewall rule created" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠ Could not create custom rule: $_" -ForegroundColor Yellow
    }
}

# Verification
Write-Host ""
Write-Host "===== Verification =====" -ForegroundColor Green
Write-Host ""

$adwsServiceCheck = Get-Service -Name "ADWS"
Write-Host "ADWS Service Status:" -ForegroundColor Cyan
Write-Host "  Status: $($adwsServiceCheck.Status)" -ForegroundColor White
Write-Host "  Startup Type: $($adwsServiceCheck.StartType)" -ForegroundColor White
Write-Host ""

# Check if port 9389 is listening
Write-Host "Checking ADWS port (9389)..." -ForegroundColor Cyan
$tcpConnection = Get-NetTCPConnection -LocalPort 9389 -ErrorAction SilentlyContinue

if ($tcpConnection) {
    Write-Host "  ✓ Port 9389 is listening" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Port 9389 is not listening (ADWS may still be starting)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===== ADWS Configuration Complete! =====" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Add port 9389 to AWS Security Group (run add-security-group-rules.sh)" -ForegroundColor White
Write-Host "2. Test from SQL node: Test-NetConnection -ComputerName DC01 -Port 9389" -ForegroundColor White
Write-Host "3. Try running 06-Install-SQLServer-Prep.ps1 again" -ForegroundColor White
Write-Host ""

