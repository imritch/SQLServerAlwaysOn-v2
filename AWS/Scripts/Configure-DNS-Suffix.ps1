# Configure DNS Suffix Search Order for Windows Clustering
# This enables "Append primary and connection specific DNS suffixes"
# Run as Administrator on both SQL nodes after domain join

$ErrorActionPreference = "Stop"

Write-Host "===== Configuring DNS Suffix Settings for Clustering =====" -ForegroundColor Green
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ""

# Get the primary network adapter
$Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Name -like "Ethernet*"} | Select-Object -First 1

if (-not $Adapter) {
    Write-Host "ERROR: Could not find active Ethernet adapter" -ForegroundColor Red
    exit 1
}

Write-Host "[1/4] Network Adapter: $($Adapter.Name)" -ForegroundColor Cyan
Write-Host "        Interface Index: $($Adapter.InterfaceIndex)" -ForegroundColor Cyan
Write-Host ""

# Step 1: Set connection-specific DNS suffix
Write-Host "[2/4] Setting connection-specific DNS suffix..." -ForegroundColor Yellow
try {
    Set-DnsClient -InterfaceIndex $Adapter.InterfaceIndex -ConnectionSpecificSuffix "contoso.local"
    Write-Host "  ✓ Connection-specific suffix set to: contoso.local" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Warning: Could not set connection-specific suffix: $_" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Configure DNS suffix search order via registry
Write-Host "[3/4] Configuring DNS suffix search order..." -ForegroundColor Yellow

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

try {
    # Set the DNS suffix search list (this enables the checkbox)
    Set-ItemProperty -Path $regPath -Name "SearchList" -Value "contoso.local" -Type String
    Write-Host "  ✓ DNS search list set to: contoso.local" -ForegroundColor Green
    
    # Enable "Append primary and connection specific DNS suffixes" (this is the default, but we ensure it)
    # UseDomainNameDevolution = 1 means "Append primary and connection specific DNS suffixes"
    # UseDomainNameDevolution = 0 means "Append these DNS suffixes (in order)"
    Set-ItemProperty -Path $regPath -Name "UseDomainNameDevolution" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    Write-Host "  ✓ Enabled 'Append primary and connection specific DNS suffixes'" -ForegroundColor Green
    
} catch {
    Write-Host "  ⚠ Warning: Could not configure registry settings: $_" -ForegroundColor Yellow
}
Write-Host ""

# Step 3: Flush DNS cache to apply changes
Write-Host "[4/4] Flushing DNS cache..." -ForegroundColor Yellow
try {
    ipconfig /flushdns | Out-Null
    Write-Host "  ✓ DNS cache flushed" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Warning: Could not flush DNS cache" -ForegroundColor Yellow
}
Write-Host ""

# Verification
Write-Host "===== Verification =====" -ForegroundColor Green
Write-Host ""

Write-Host "Current DNS Configuration:" -ForegroundColor Cyan
$dnsClient = Get-DnsClient -InterfaceIndex $Adapter.InterfaceIndex
Write-Host "  Connection-specific suffix: $($dnsClient.ConnectionSpecificSuffix)" -ForegroundColor White

Write-Host ""
Write-Host "Registry Settings:" -ForegroundColor Cyan
$searchList = Get-ItemProperty -Path $regPath -Name "SearchList" -ErrorAction SilentlyContinue
$devolution = Get-ItemProperty -Path $regPath -Name "UseDomainNameDevolution" -ErrorAction SilentlyContinue

if ($searchList) {
    Write-Host "  DNS Search List: $($searchList.SearchList)" -ForegroundColor White
}
if ($devolution) {
    $devStatus = if ($devolution.UseDomainNameDevolution -eq 1) { "Enabled (Append suffixes)" } else { "Disabled (Use explicit list)" }
    Write-Host "  Domain Name Devolution: $devStatus" -ForegroundColor White
}

Write-Host ""

# Test DNS resolution
Write-Host "===== Testing DNS Resolution =====" -ForegroundColor Green
Write-Host ""

$computerName = $env:COMPUTERNAME
$testNodes = @()

if ($computerName -eq "SQL01") {
    $testNodes = @("SQL02", "DC01")
} elseif ($computerName -eq "SQL02") {
    $testNodes = @("SQL01", "DC01")
} else {
    $testNodes = @("SQL01", "SQL02", "DC01")
}

foreach ($node in $testNodes) {
    Write-Host "Testing resolution of '$node' (short name):" -ForegroundColor Yellow
    try {
        $result = Resolve-DnsName -Name $node -ErrorAction Stop
        Write-Host "  ✓ $node resolves to: $($result.IPAddress)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to resolve $node" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "===== Configuration Complete! =====" -ForegroundColor Green
Write-Host ""
Write-Host "Summary of changes:" -ForegroundColor Cyan
Write-Host "  • Connection-specific DNS suffix: contoso.local" -ForegroundColor White
Write-Host "  • DNS suffix search list: contoso.local" -ForegroundColor White
Write-Host "  • Enabled: Append primary and connection specific DNS suffixes" -ForegroundColor White
Write-Host ""
Write-Host "This allows short names (SQL01, SQL02) to be resolved automatically!" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Run this script on the OTHER SQL node" -ForegroundColor White
Write-Host "  2. Test: nslookup SQL02 (should work now)" -ForegroundColor White
Write-Host "  3. Try cluster creation: .\05-Create-WSFC.ps1" -ForegroundColor White
Write-Host ""

