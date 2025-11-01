# Remove Secondary IPs from Windows Network Adapter
# Run on BOTH SQL01 and SQL02 if you previously added secondary IPs to Windows
# These IPs should only exist at the ENI level, not configured in Windows

$ErrorActionPreference = "Stop"

Write-Host "===== Removing Secondary IPs from Windows =====" -ForegroundColor Green
Write-Host "Secondary IPs should only exist at the AWS ENI level." -ForegroundColor Cyan
Write-Host "The cluster will automatically detect and use them." -ForegroundColor Cyan
Write-Host ""

# Get adapter
$Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.Name -like "Ethernet*"} | Select-Object -First 1

if (-not $Adapter) {
    Write-Host "ERROR: Could not find active Ethernet adapter" -ForegroundColor Red
    exit 1
}

Write-Host "Network Adapter: $($Adapter.Name)" -ForegroundColor Cyan
Write-Host ""

# Get all IPv4 addresses
$AllIPs = Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4

Write-Host "Current IP addresses:" -ForegroundColor Yellow
$AllIPs | Select-Object IPAddress, PrefixLength | Format-Table -AutoSize

# Find secondary IPs (ending in .50 or .51)
$SecondaryIPs = $AllIPs | Where-Object {$_.IPAddress -like "*.50" -or $_.IPAddress -like "*.51"}

if ($SecondaryIPs) {
    Write-Host "Removing secondary IPs:" -ForegroundColor Yellow
    foreach ($IP in $SecondaryIPs) {
        Write-Host "  Removing: $($IP.IPAddress)" -ForegroundColor Cyan
        Remove-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -IPAddress $IP.IPAddress -Confirm:$false
        Write-Host "    ✓ Removed" -ForegroundColor Green
    }
} else {
    Write-Host "✓ No secondary IPs found (already clean)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Final configuration:" -ForegroundColor Cyan
Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4 | 
    Select-Object IPAddress, PrefixLength | 
    Format-Table -AutoSize

Write-Host "✓ Cleanup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "You can now create the cluster using 05-Create-WSFC.ps1" -ForegroundColor Yellow
Write-Host ""

