# SQL01/SQL02 - Install Failover Clustering Feature
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

Write-Host "===== Installing Failover Clustering =====" -ForegroundColor Green

# Install Failover Clustering with Management Tools
Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools

Write-Host "`nFailover Clustering installed successfully!" -ForegroundColor Green

# Enable Firewall Rules for Clustering
Write-Host "`nEnabling firewall rules for clustering..." -ForegroundColor Yellow

Enable-NetFirewallRule -DisplayGroup "Failover Clusters"
Enable-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)"
Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management"

Write-Host "Firewall rules enabled successfully!" -ForegroundColor Green

Write-Host "`nReboot recommended but not required." -ForegroundColor Yellow
Write-Host "`nNext: Run this on both SQL01 and SQL02, then create the cluster from SQL01" -ForegroundColor Cyan

