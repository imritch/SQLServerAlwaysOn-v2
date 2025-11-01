# SQL01/SQL02 - Join to Domain
# Run as local Administrator

$ErrorActionPreference = "Stop"

# Configuration
$DomainName = "contoso.local"
$DomainUser = "CONTOSO\Administrator"

# Which node are we setting up?
$ComputerName = Read-Host "Enter computer name (SQL01 or SQL02)"
$CurrentName = $env:COMPUTERNAME

Write-Host "===== Joining $ComputerName to Domain =====" -ForegroundColor Green

# Check if computer needs to be renamed first
if ($CurrentName -ne $ComputerName) {
    Write-Host "`n[Stage 1: Rename Computer]" -ForegroundColor Yellow
    Write-Host "Current name: $CurrentName" -ForegroundColor Cyan
    Write-Host "Target name: $ComputerName" -ForegroundColor Cyan
    
    Rename-Computer -NewName $ComputerName -Force
    
    Write-Host "`nComputer renamed to $ComputerName" -ForegroundColor Green
    Write-Host "System will restart in 10 seconds..." -ForegroundColor Yellow
    Write-Host "After restart, run this script again to join domain." -ForegroundColor Cyan
    
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    exit
}

# Computer is already named correctly, proceed with domain join
Write-Host "`nComputer name: $ComputerName - OK" -ForegroundColor Green
Write-Host "`n[Stage 2: Join Domain]" -ForegroundColor Yellow

# Get DC IP and credentials
$DC_IP = Read-Host "Enter DC01 Private IP (e.g., 172.31.x.x)"
$DomainPassword = Read-Host "Enter CONTOSO\Administrator password" -AsSecureString
$DomainPasswordText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($DomainPassword))

# Step 1: Test DC connectivity first
Write-Host "`n[1/5] Testing connectivity to Domain Controller..." -ForegroundColor Yellow
$TestDC = Test-Connection -ComputerName $DC_IP -Count 2 -Quiet
if ($TestDC) {
    Write-Host "DC is reachable at $DC_IP" -ForegroundColor Green
} else {
    Write-Host "ERROR: Cannot reach DC at $DC_IP. Check security groups and network." -ForegroundColor Red
    exit
}

# Step 2: Set DNS to point to DC
Write-Host "`n[2/5] Configuring DNS to point to Domain Controller..." -ForegroundColor Yellow
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DC_IP
Write-Host "  Configured adapter: $($adapter.Name)" -ForegroundColor Cyan

# Set DNS suffix (CRITICAL - AWS sets it to ec2.internal by default)
Write-Host "  Setting DNS suffix to contoso.local..." -ForegroundColor Cyan
Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix $DomainName

# Set domain at registry level
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\"
Set-ItemProperty $regPath -Name "Domain" -Value $DomainName -ErrorAction SilentlyContinue
Set-ItemProperty $regPath -Name "NV Domain" -Value $DomainName -ErrorAction SilentlyContinue

# Configure DNS suffix search order (CRITICAL for Windows Clustering)
# This enables "Append primary and connection specific DNS suffixes" setting
Write-Host "  Configuring DNS suffix search order..." -ForegroundColor Cyan
Set-ItemProperty $regPath -Name "SearchList" -Value $DomainName -Type String -ErrorAction SilentlyContinue
Set-ItemProperty $regPath -Name "UseDomainNameDevolution" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Host "  Enabled: Append primary and connection specific DNS suffixes" -ForegroundColor Green

# Enable NetBIOS over TCP/IP
$adapterConfig = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.InterfaceIndex -eq $adapter.ifIndex}
$adapterConfig.SetTcpipNetbios(1) | Out-Null

# Clear DNS cache
Clear-DnsClientCache
ipconfig /flushdns | Out-Null
Write-Host "DNS and suffix configured" -ForegroundColor Green

# Wait for DNS to propagate
Write-Host "Waiting for DNS to update..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Step 3: Test domain connectivity
Write-Host "`n[3/5] Testing domain connectivity..." -ForegroundColor Yellow

# Try DNS resolution first
try {
    $resolved = Resolve-DnsName -Name $DomainName -Server $DC_IP -ErrorAction Stop
    Write-Host "Domain DNS resolution successful!" -ForegroundColor Green
} catch {
    Write-Host "WARNING: DNS resolution failed: $_" -ForegroundColor Yellow
    Write-Host "Attempting to continue anyway..." -ForegroundColor Yellow
}

# Test ping to domain
$TestDomain = Test-Connection -ComputerName $DomainName -Count 2 -Quiet
if ($TestDomain) {
    Write-Host "Domain is reachable!" -ForegroundColor Green
} else {
    Write-Host "WARNING: Cannot ping domain name, but will attempt join anyway" -ForegroundColor Yellow
}

# Test DC hostname resolution (CRITICAL)
Write-Host "Testing DC hostname resolution..." -ForegroundColor Yellow
$DCHostname = "dc01.$DomainName"
try {
    $dcResolved = Resolve-DnsName -Name $DCHostname -Server $DC_IP -ErrorAction Stop
    Write-Host "DC hostname resolves to: $($dcResolved.IPAddress)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Cannot resolve DC hostname: $DCHostname" -ForegroundColor Red
    Write-Host "Fix: On DC01, ensure DNS A record exists for dc01" -ForegroundColor Yellow
    exit 1
}

# Step 4: Rename computer
Write-Host "`n[4/5] Renaming computer to $ComputerName..." -ForegroundColor Yellow
$CurrentName = $env:COMPUTERNAME
if ($CurrentName -ne $ComputerName) {
    Rename-Computer -NewName $ComputerName -Force -PassThru
}

# Step 5: Join domain
Write-Host "`n[5/5] Joining domain $DomainName..." -ForegroundColor Yellow
$Password = ConvertTo-SecureString $DomainPasswordText -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($DomainUser, $Password)

# Use -Server parameter to explicitly specify the DC (more reliable)
$DCHostname = "dc01.$DomainName"

Write-Host "Joining domain via DC: $DCHostname" -ForegroundColor Cyan

try {
    Add-Computer -DomainName $DomainName -Server $DCHostname -Credential $Credential -Force -ErrorAction Stop
    
    # Install RSAT AD PowerShell tools (needed for gMSA and AD cmdlets later)
    Write-Host "`n Installing RSAT Active Directory PowerShell module..." -ForegroundColor Yellow
    try {
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
        Write-Host "RSAT AD PowerShell module installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "Warning: Could not install RSAT AD PowerShell module: $_" -ForegroundColor Yellow
        Write-Host "You can install it later from Server Manager" -ForegroundColor Cyan
    }
    
    Write-Host "`n===== Domain Join Complete! =====" -ForegroundColor Green
    Write-Host "Computer will restart in 15 seconds..." -ForegroundColor Yellow
    Write-Host "After restart, login as: CONTOSO\Administrator" -ForegroundColor Cyan
    
    Start-Sleep -Seconds 15
    Restart-Computer -Force
    
} catch {
    Write-Host "`nERROR: Domain join failed!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Verify DC is accessible: Test-NetConnection -ComputerName $DC_IP -Port 389" -ForegroundColor Cyan
    Write-Host "2. Check DNS resolution: nslookup $DCHostname" -ForegroundColor Cyan
    Write-Host "3. Verify credentials are correct" -ForegroundColor Cyan
    Write-Host "4. Check if computer account exists on DC and delete it if stale" -ForegroundColor Cyan
    exit 1
}

