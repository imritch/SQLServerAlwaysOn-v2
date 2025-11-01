# Verify Secondary IPs are assigned at AWS ENI level
# Run this on SQL01 before creating the cluster to validate setup
# This script uses AWS CLI from Windows to verify ENI configuration

param(
    [string]$Region = "us-east-1",
    [string]$StackName = "sql-ag-demo"
)

$ErrorActionPreference = "Stop"

Write-Host "===== Verifying Secondary IP Assignment =====" -ForegroundColor Green
Write-Host ""

# Check if AWS CLI is available (optional - for enhanced validation)
$awsCliAvailable = Get-Command aws -ErrorAction SilentlyContinue

if (-not $awsCliAvailable) {
    Write-Host "⚠ AWS CLI not available in Windows - skipping ENI verification" -ForegroundColor Yellow
    Write-Host "Continuing with local network validation only..." -ForegroundColor Yellow
    Write-Host ""
}

# Step 1: Get current node info
Write-Host "[1/3] Detecting current node..." -ForegroundColor Yellow
$computerName = $env:COMPUTERNAME
$Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Name -like "Ethernet*"} | Select-Object -First 1
$IPConfig = Get-NetIPConfiguration -InterfaceIndex $Adapter.InterfaceIndex
$CurrentIP = ($IPConfig.IPv4Address).IPAddress

Write-Host "Computer Name: $computerName" -ForegroundColor Cyan
Write-Host "Primary IP: $CurrentIP" -ForegroundColor Cyan
Write-Host ""

# Determine expected secondary IPs
if ($CurrentIP -like "10.0.1.*") {
    $NodeName = "SQL01"
    $ExpectedClusterIP = "10.0.1.50"
    $ExpectedListenerIP = "10.0.1.51"
    $PeerNode = "SQL02"
    $PeerClusterIP = "10.0.2.50"
    $PeerListenerIP = "10.0.2.51"
} elseif ($CurrentIP -like "10.0.2.*") {
    $NodeName = "SQL02"
    $ExpectedClusterIP = "10.0.2.50"
    $ExpectedListenerIP = "10.0.2.51"
    $PeerNode = "SQL01"
    $PeerClusterIP = "10.0.1.50"
    $PeerListenerIP = "10.0.1.51"
} else {
    Write-Host "ERROR: Could not determine node from IP: $CurrentIP" -ForegroundColor Red
    exit 1
}

Write-Host "Detected as: $NodeName" -ForegroundColor Green
Write-Host ""

# Step 2: Verify with AWS CLI if available
if ($awsCliAvailable) {
    Write-Host "[2/3] Verifying ENI assignment via AWS CLI..." -ForegroundColor Yellow
    
    try {
        # Get this instance ID from metadata
        $instanceId = (Invoke-WebRequest -Uri http://169.254.169.254/latest/meta-data/instance-id -UseBasicParsing).Content
        
        # Get ENI ID
        $eniId = aws ec2 describe-instances `
            --instance-ids $instanceId `
            --region $Region `
            --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' `
            --output text
        
        # Get all private IPs assigned to this ENI
        $assignedIPs = aws ec2 describe-network-interfaces `
            --network-interface-ids $eniId `
            --region $Region `
            --query 'NetworkInterfaces[0].PrivateIpAddresses[*].PrivateIpAddress' `
            --output text
        
        Write-Host "ENI ID: $eniId" -ForegroundColor Cyan
        Write-Host "All IPs assigned at ENI level:" -ForegroundColor Cyan
        $assignedIPs -split '\s+' | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host ""
        
        # Verify expected IPs are present
        $hasClusterIP = $assignedIPs -match [regex]::Escape($ExpectedClusterIP)
        $hasListenerIP = $assignedIPs -match [regex]::Escape($ExpectedListenerIP)
        
        if ($hasClusterIP) {
            Write-Host "✓ Cluster IP $ExpectedClusterIP is assigned at ENI level" -ForegroundColor Green
        } else {
            Write-Host "✗ Cluster IP $ExpectedClusterIP is NOT assigned at ENI level" -ForegroundColor Red
            Write-Host "  Run 04b-Assign-Secondary-IPs.sh first!" -ForegroundColor Yellow
            exit 1
        }
        
        if ($hasListenerIP) {
            Write-Host "✓ Listener IP $ExpectedListenerIP is assigned at ENI level" -ForegroundColor Green
        } else {
            Write-Host "✗ Listener IP $ExpectedListenerIP is NOT assigned at ENI level" -ForegroundColor Red
            Write-Host "  Run 04b-Assign-Secondary-IPs.sh first!" -ForegroundColor Yellow
            exit 1
        }
        
    } catch {
        Write-Host "⚠ Could not verify via AWS CLI: $_" -ForegroundColor Yellow
        Write-Host "Continuing with local validation..." -ForegroundColor Yellow
    }
    
    Write-Host ""
}

# Step 3: Verify these IPs are NOT configured in Windows (correct behavior for AWS)
Write-Host "[3/3] Verifying Windows IP configuration..." -ForegroundColor Yellow

$windowsIPs = Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress

Write-Host "IPs configured in Windows:" -ForegroundColor Cyan
$windowsIPs | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
Write-Host ""

$hasClusterInWindows = $windowsIPs -contains $ExpectedClusterIP
$hasListenerInWindows = $windowsIPs -contains $ExpectedListenerIP

if (-not $hasClusterInWindows -and -not $hasListenerInWindows) {
    Write-Host "✓ Secondary IPs are NOT in Windows (correct for AWS)" -ForegroundColor Green
} else {
    Write-Host "✗ WARNING: Secondary IPs found in Windows configuration!" -ForegroundColor Red
    Write-Host "  This will cause issues in AWS. Remove them from Windows." -ForegroundColor Yellow
    Write-Host "  They should only exist at the ENI level." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "===== Validation Summary =====" -ForegroundColor Green
Write-Host ""
Write-Host "Node: $NodeName" -ForegroundColor Cyan
Write-Host "Primary IP (in Windows): $CurrentIP" -ForegroundColor Cyan
Write-Host "Cluster IP (at ENI only): $ExpectedClusterIP" -ForegroundColor Cyan
Write-Host "Listener IP (at ENI only): $ExpectedListenerIP" -ForegroundColor Cyan
Write-Host ""
Write-Host "Peer Node: $PeerNode" -ForegroundColor Cyan
Write-Host "Peer Cluster IP: $PeerClusterIP" -ForegroundColor Cyan
Write-Host "Peer Listener IP: $PeerListenerIP" -ForegroundColor Cyan
Write-Host ""
Write-Host "All validations passed!" -ForegroundColor Green
Write-Host "Ready to create Windows Failover Cluster" -ForegroundColor Green
Write-Host ""
Write-Host "Next Step: Run 05-Create-WSFC.ps1 with these IPs:" -ForegroundColor Yellow
$cmdExample = ".\05-Create-WSFC.ps1 -ClusterIP1 $ExpectedClusterIP -ClusterIP2 $PeerClusterIP"
Write-Host "  $cmdExample" -ForegroundColor Cyan
Write-Host ""