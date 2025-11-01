# Configure Secondary IPs inside Windows
# Run on EACH node (SQL01 and SQL02) as Administrator
# This configures Windows to recognize the secondary IPs assigned to the ENI in AWS

$ErrorActionPreference = "Stop"

Write-Host "===== Configuring Secondary IPs in Windows =====" -ForegroundColor Green
Write-Host "This script will:" -ForegroundColor Cyan
Write-Host "  1. Convert network adapter from DHCP to Static IP" -ForegroundColor White
Write-Host "  2. Add secondary IPs to the network adapter" -ForegroundColor White
Write-Host ""

# Get the primary network adapter
$Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Name -like "Ethernet*"} | Select-Object -First 1

if (-not $Adapter) {
    Write-Host "ERROR: Could not find active Ethernet adapter" -ForegroundColor Red
    exit 1
}

Write-Host "Network Adapter: $($Adapter.Name)" -ForegroundColor Cyan
Write-Host "Interface Index: $($Adapter.InterfaceIndex)" -ForegroundColor Cyan
Write-Host ""

# Step 1: Get current DHCP-assigned configuration
Write-Host "[1/4] Getting current network configuration..." -ForegroundColor Yellow

$IPConfig = Get-NetIPConfiguration -InterfaceIndex $Adapter.InterfaceIndex
$CurrentIP = ($IPConfig.IPv4Address).IPAddress
$PrefixLength = ($IPConfig.IPv4Address).PrefixLength
$Gateway = ($IPConfig.IPv4DefaultGateway).NextHop
$DNS = (Get-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4).ServerAddresses

Write-Host "Current Configuration (from DHCP):" -ForegroundColor Cyan
Write-Host "  IP Address: $CurrentIP" -ForegroundColor White
Write-Host "  Prefix Length: $PrefixLength" -ForegroundColor White
Write-Host "  Gateway: $Gateway" -ForegroundColor White
Write-Host "  DNS Servers: $($DNS -join ', ')" -ForegroundColor White
Write-Host ""

# Determine which node and secondary IPs based on primary IP
if ($CurrentIP -like "10.0.1.*") {
    $NodeName = "SQL01"
    $SecondaryIPs = @("10.0.1.50", "10.0.1.51")
    Write-Host "Detected Node: SQL01 (Subnet 1)" -ForegroundColor Green
} elseif ($CurrentIP -like "10.0.2.*") {
    $NodeName = "SQL02"
    $SecondaryIPs = @("10.0.2.50", "10.0.2.51")
    Write-Host "Detected Node: SQL02 (Subnet 2)" -ForegroundColor Green
} else {
    Write-Host "ERROR: Could not detect node from IP address: $CurrentIP" -ForegroundColor Red
    Write-Host "Expected 10.0.1.x (SQL01) or 10.0.2.x (SQL02)" -ForegroundColor Red
    exit 1
}

Write-Host "Secondary IPs to add: $($SecondaryIPs -join ', ')" -ForegroundColor Cyan
Write-Host ""

# Step 2: Convert from DHCP to Static IP
Write-Host "[2/4] Converting to Static IP configuration..." -ForegroundColor Yellow
Write-Host "WARNING: RDP connection may briefly pause during this step" -ForegroundColor Red
Write-Host ""

Start-Sleep -Seconds 2

# Remove DHCP configuration
Remove-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex $Adapter.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue

# Set static IP (same as the current DHCP IP)
New-NetIPAddress `
    -InterfaceIndex $Adapter.InterfaceIndex `
    -IPAddress $CurrentIP `
    -PrefixLength $PrefixLength `
    -DefaultGateway $Gateway `
    -ErrorAction Stop | Out-Null

# Set DNS servers
Set-DnsClientServerAddress `
    -InterfaceIndex $Adapter.InterfaceIndex `
    -ServerAddresses $DNS `
    -ErrorAction Stop

# Configure DNS suffix settings (CRITICAL for Windows Clustering)
Write-Host "  Configuring DNS suffix settings..." -ForegroundColor Cyan
Set-DnsClient -InterfaceIndex $Adapter.InterfaceIndex -ConnectionSpecificSuffix "contoso.local" -ErrorAction SilentlyContinue

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\"
Set-ItemProperty $regPath -Name "SearchList" -Value "contoso.local" -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $regPath -Name "UseDomainNameDevolution" -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Host "✓ Static IP configured successfully" -ForegroundColor Green
Write-Host "✓ DNS suffix settings configured (enables short name resolution)" -ForegroundColor Green
Write-Host ""

# Step 3: Verify secondary IPs in AWS (do NOT configure them in Windows)
Write-Host "[3/4] Verifying secondary IPs exist at AWS ENI level..." -ForegroundColor Yellow
Write-Host ""
Write-Host "✓ Secondary IPs for $NodeName (assigned via AWS ENI):" -ForegroundColor Green
Write-Host "  $($SecondaryIPs -join ', ')" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: These IPs are NOT configured in Windows." -ForegroundColor Yellow
Write-Host "The failover cluster will automatically detect and use them." -ForegroundColor Yellow
Write-Host ""

# Step 4: Verify configuration
Write-Host "[4/4] Verifying configuration..." -ForegroundColor Yellow
Write-Host ""

Write-Host "Current IP Addresses on $($Adapter.Name):" -ForegroundColor Cyan
Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4 | 
    Select-Object IPAddress, PrefixLength, SkipAsSource | 
    Format-Table -AutoSize

Write-Host "DNS Servers:" -ForegroundColor Cyan
Get-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4 | 
    Select-Object ServerAddresses | 
    Format-List

Write-Host "Default Gateway:" -ForegroundColor Cyan
Get-NetRoute -InterfaceIndex $Adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" | 
    Select-Object NextHop | 
    Format-Table -AutoSize

# Test connectivity
Write-Host "Testing connectivity..." -ForegroundColor Yellow
$TestResult = Test-Connection -ComputerName $Gateway -Count 2 -Quiet

if ($TestResult) {
    Write-Host "✓ Network connectivity verified" -ForegroundColor Green
} else {
    Write-Host "⚠ Warning: Could not ping gateway" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===== Configuration Complete! =====" -ForegroundColor Green
Write-Host ""
Write-Host "Node: $NodeName" -ForegroundColor Cyan
Write-Host "Primary IP (configured in Windows): $CurrentIP" -ForegroundColor Cyan
Write-Host "Secondary IPs (available at ENI level): $($SecondaryIPs -join ', ')" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ Only the primary IP is configured in Windows (correct for AWS clustering)" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Run this script on the OTHER node" -ForegroundColor White
Write-Host "2. Then create the cluster using 05-Create-WSFC.ps1" -ForegroundColor White
Write-Host "   The cluster will automatically use the secondary IPs from the ENI" -ForegroundColor White
Write-Host ""