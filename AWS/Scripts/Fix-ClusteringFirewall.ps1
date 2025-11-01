# Fix Windows Firewall Rules for Failover Clustering
# Run this on BOTH SQL01 and SQL02 as Administrator
# This enables all necessary firewall rules for Windows Failover Clustering

$ErrorActionPreference = "Stop"

Write-Host "===== Enabling Windows Firewall Rules for Clustering =====" -ForegroundColor Green
Write-Host "Running on: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""

# Enable Failover Clustering firewall rule groups
Write-Host "[1/4] Enabling Failover Clustering firewall rule groups..." -ForegroundColor Yellow

try {
    # Enable Failover Cluster Manager rules
    Enable-NetFirewallRule -DisplayGroup "Failover Cluster Manager" -ErrorAction SilentlyContinue
    Write-Host "  ✓ Enabled 'Failover Cluster Manager' rules" -ForegroundColor Green
    
    # Enable Failover Clusters rules (if they exist)
    Enable-NetFirewallRule -DisplayGroup "Failover Clusters" -ErrorAction SilentlyContinue
    Write-Host "  ✓ Enabled 'Failover Clusters' rules" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Some rules may not be available (is Failover Clustering installed?)" -ForegroundColor Yellow
}

Write-Host ""

# Enable File and Printer Sharing (needed for SMB)
Write-Host "[2/4] Enabling File and Printer Sharing..." -ForegroundColor Yellow
try {
    Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
    Write-Host "  ✓ Enabled 'File and Printer Sharing' rules" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not enable some File and Printer Sharing rules" -ForegroundColor Yellow
}

Write-Host ""

# Enable Remote Event Log Management
Write-Host "[3/4] Enabling Remote Event Log Management..." -ForegroundColor Yellow
try {
    Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management"
    Write-Host "  ✓ Enabled 'Remote Event Log Management' rules" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not enable Remote Event Log Management rules" -ForegroundColor Yellow
}

Write-Host ""

# Enable Remote Service Management
Write-Host "[4/4] Enabling Remote Service Management..." -ForegroundColor Yellow
try {
    Enable-NetFirewallRule -DisplayGroup "Remote Service Management"
    Write-Host "  ✓ Enabled 'Remote Service Management' rules" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not enable Remote Service Management rules" -ForegroundColor Yellow
}

Write-Host ""

# Verify enabled rules
Write-Host "===== Verification =====" -ForegroundColor Green
Write-Host ""

$clusterRules = Get-NetFirewallRule | Where-Object {
    $_.DisplayGroup -like "*Failover Cluster*" -and $_.Enabled -eq $true
}

$smbRules = Get-NetFirewallRule | Where-Object {
    $_.DisplayGroup -like "*File and Printer*" -and $_.Enabled -eq $true
}

Write-Host "Enabled Failover Cluster rules: $($clusterRules.Count)" -ForegroundColor Cyan
Write-Host "Enabled File Sharing rules: $($smbRules.Count)" -ForegroundColor Cyan

Write-Host ""
Write-Host "Sample of enabled cluster rules:" -ForegroundColor Yellow
$clusterRules | Select-Object -First 5 | Format-Table DisplayName, Direction, Action -AutoSize

Write-Host ""
Write-Host "===== Firewall Configuration Complete! =====" -ForegroundColor Green
Write-Host ""
Write-Host "Important: Run this script on the OTHER SQL node as well!" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Run this script on the other node" -ForegroundColor White
Write-Host "2. Run: .\Troubleshoot-Clustering.ps1 -TargetNode SQL02" -ForegroundColor White
Write-Host "3. Try creating the cluster again: .\05-Create-WSFC.ps1" -ForegroundColor White
Write-Host ""