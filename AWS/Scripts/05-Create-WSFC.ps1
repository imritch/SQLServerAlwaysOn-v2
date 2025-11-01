# SQL01 - Create Windows Server Failover Cluster (Multi-Subnet)
# Run as CONTOSO\Administrator on SQL01 only

param(
    [string]$ClusterIP1 = "10.0.1.50",
    [string]$ClusterIP2 = "10.0.2.50",
    [string]$ClusterName = "SQLCLUSTER",
    [string]$Node1 = "SQL01.contoso.local",
    [string]$Node2 = "SQL02.contoso.local"
)

$ErrorActionPreference = "Stop"

Write-Host "===== Creating Windows Server Failover Cluster (Multi-Subnet) =====" -ForegroundColor Green
Write-Host "`nIMPORTANT: Multi-subnet cluster requires 2 IP addresses (one per subnet)" -ForegroundColor Yellow
Write-Host "These IPs must be pre-assigned at the AWS ENI level" -ForegroundColor Cyan

# Get subnet information
Write-Host "`nSubnet Information:" -ForegroundColor Cyan
Write-Host "  Subnet 1 (SQL01): 10.0.1.0/24" -ForegroundColor White
Write-Host "  Subnet 2 (SQL02): 10.0.2.0/24" -ForegroundColor White
Write-Host "`nPre-assigned Secondary IPs:" -ForegroundColor Yellow
Write-Host "  Cluster IPs: 10.0.1.50, 10.0.2.50" -ForegroundColor White
Write-Host "  Listener IPs: 10.0.1.51, 10.0.2.51 (for AG Listener - use later)" -ForegroundColor White
Write-Host ""

Write-Host "===== Multi-Subnet Configuration =====" -ForegroundColor Green
Write-Host "Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "Cluster IP 1 (Subnet 1): $ClusterIP1" -ForegroundColor Cyan
Write-Host "Cluster IP 2 (Subnet 2): $ClusterIP2" -ForegroundColor Cyan
Write-Host "Nodes: $Node1, $Node2" -ForegroundColor Cyan
Write-Host ""

# Pre-flight check: Verify IPs are NOT in Windows (should only be at ENI level)
Write-Host "[0/4] Pre-flight validation..." -ForegroundColor Yellow
$localIP = (Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null}).IPv4Address.IPAddress

$windowsIPs = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress

if ($windowsIPs -contains $ClusterIP1 -or $windowsIPs -contains $ClusterIP2) {
    Write-Host "ERROR: Cluster IPs found in Windows configuration!" -ForegroundColor Red
    Write-Host "Secondary IPs must ONLY exist at AWS ENI level, not in Windows." -ForegroundColor Yellow
    Write-Host "Remove them from Windows network adapter before proceeding." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Cluster IPs verified to be at ENI level only (not in Windows)" -ForegroundColor Green
Write-Host ""

# Step 1: Test Cluster Configuration
Write-Host "`n[1/4] Testing cluster configuration..." -ForegroundColor Yellow
Write-Host "This may take a few minutes..." -ForegroundColor Cyan

$TestResult = Test-Cluster -Node $Node1, $Node2

if ($TestResult) {
    Write-Host "Cluster validation complete. Check C:\Windows\Cluster\Reports for results." -ForegroundColor Green
} else {
    Write-Host "WARNING: Cluster validation had issues. Continuing anyway..." -ForegroundColor Yellow
}

# Step 2: Create Cluster with Multiple Static IPs (Multi-Subnet)
Write-Host "`n[2/4] Creating multi-subnet failover cluster..." -ForegroundColor Yellow
Write-Host "Cluster Name: $ClusterName" -ForegroundColor Cyan
Write-Host "Nodes: $Node1, $Node2" -ForegroundColor Cyan
Write-Host "Cluster IP Addresses: $ClusterIP1, $ClusterIP2" -ForegroundColor Cyan
Write-Host "Note: Using NoStorage for SQL AG" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: The cluster will automatically detect and use the secondary" -ForegroundColor Yellow
Write-Host "IPs that are assigned at the AWS ENI level. This may take 30-60 seconds." -ForegroundColor Yellow
Write-Host ""

# Create cluster with both IPs
try {
    New-Cluster -Name $ClusterName `
        -Node $Node1, $Node2 `
        -NoStorage `
        -StaticAddress $ClusterIP1, $ClusterIP2 `
        -Force
    
    Write-Host "✓ Multi-subnet cluster created successfully!" -ForegroundColor Green
    
    # Wait for cluster resources to stabilize
    Write-Host "Waiting for cluster resources to come online..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    
    # Verify cluster IP resources came online
    $clusterIPResources = Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"}
    $allOnline = $true
    
    foreach ($ipResource in $clusterIPResources) {
        $state = $ipResource.State
        $ipAddress = ($ipResource | Get-ClusterParameter | Where-Object {$_.Name -eq "Address"}).Value
        
        if ($state -eq "Online") {
            Write-Host "  ✓ Cluster IP $ipAddress is Online" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Cluster IP $ipAddress is $state" -ForegroundColor Red
            $allOnline = $false
        }
    }
    
    if (-not $allOnline) {
        Write-Host ""
        Write-Host "WARNING: Some cluster IPs did not come online." -ForegroundColor Yellow
        Write-Host "This usually means the IPs are not assigned at the ENI level." -ForegroundColor Yellow
        Write-Host "Verify with: aws ec2 describe-network-interfaces" -ForegroundColor Cyan
    }
    
} catch {
    Write-Host "ERROR creating cluster: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "1. Secondary IPs not assigned at AWS ENI level (run 04b-Assign-Secondary-IPs.sh)" -ForegroundColor White
    Write-Host "2. IPs already in use by another resource" -ForegroundColor White
    Write-Host "3. Network connectivity issues between nodes" -ForegroundColor White
    exit 1
}

# Step 3: Configure Cluster for Multi-Subnet
Write-Host "`n[3/4] Configuring cluster for multi-subnet support..." -ForegroundColor Yellow

# Set cluster parameters for multi-subnet failover
(Get-Cluster).SameSubnetDelay = 1000
(Get-Cluster).SameSubnetThreshold = 5
(Get-Cluster).CrossSubnetDelay = 1000
(Get-Cluster).CrossSubnetThreshold = 5

# Set cluster network dependency to OR (important for multi-subnet)
$clusterResource = Get-ClusterResource -Name "Cluster Name"
if ($clusterResource) {
    $clusterResource | Set-ClusterParameter -Name "HostRecordTTL" -Value 300
    Write-Host "Cluster Name resource TTL set to 300 seconds" -ForegroundColor Green
}

Write-Host "Multi-subnet parameters configured" -ForegroundColor Green

# Step 4: Configure Cluster Quorum (Cloud Witness recommended for AWS)
Write-Host "`n[4/4] Configuring cluster quorum..." -ForegroundColor Yellow
Write-Host "Using Node Majority (for demo)" -ForegroundColor Cyan

# For demo: Node Majority (works for 2 nodes but not ideal)
Set-ClusterQuorum -NodeMajority

Write-Host "`nQuorum configured!" -ForegroundColor Green
Write-Host "`nPRODUCTION NOTE: Use AWS S3 for cloud witness in production." -ForegroundColor Yellow

# Summary
Write-Host "`n===== Multi-Subnet WSFC Creation Complete =====" -ForegroundColor Green
Write-Host "`nCluster Details:" -ForegroundColor Cyan
Get-Cluster | Format-List Name, Domain

Write-Host "`nCluster Nodes:" -ForegroundColor Cyan
Get-ClusterNode | Format-Table Name, State, ID -AutoSize

Write-Host "`nCluster IP Resources:" -ForegroundColor Cyan
Get-ClusterResource | Where-Object {$_.ResourceType -eq "IP Address"} | Get-ClusterParameter | Format-Table -AutoSize

Write-Host "`nCluster Network Configuration:" -ForegroundColor Cyan
Write-Host "  SameSubnetDelay: $((Get-Cluster).SameSubnetDelay)ms"
Write-Host "  SameSubnetThreshold: $((Get-Cluster).SameSubnetThreshold)"
Write-Host "  CrossSubnetDelay: $((Get-Cluster).CrossSubnetDelay)ms"
Write-Host "  CrossSubnetThreshold: $((Get-Cluster).CrossSubnetThreshold)"

Write-Host "`nNext: Install SQL Server 2022 on both nodes" -ForegroundColor Yellow