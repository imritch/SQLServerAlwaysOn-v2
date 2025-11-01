# Test Active Directory Web Services (ADWS) Connectivity
# Run this on SQL nodes to verify ADWS connectivity to DC01
# ADWS is required for AD PowerShell cmdlets like Install-ADServiceAccount

param(
    [string]$DomainController = "DC01.contoso.local"
)

$ErrorActionPreference = "Continue"

Write-Host "===== ADWS Connectivity Test =====" -ForegroundColor Green
Write-Host "Testing from: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "Target DC: $DomainController" -ForegroundColor Cyan
Write-Host ""

$issues = @()

# Test 1: DNS Resolution
Write-Host "[1/6] Testing DNS resolution..." -ForegroundColor Yellow
try {
    $dcIP = (Resolve-DnsName $DomainController -ErrorAction Stop).IPAddress
    Write-Host "  ✓ $DomainController resolves to $dcIP" -ForegroundColor Green
} catch {
    Write-Host "  ✗ DNS resolution failed: $_" -ForegroundColor Red
    $issues += "DNS resolution failed"
}
Write-Host ""

# Test 2: Network Connectivity
Write-Host "[2/6] Testing network connectivity..." -ForegroundColor Yellow
$ping = Test-Connection -ComputerName $DomainController -Count 2 -Quiet
if ($ping) {
    Write-Host "  ✓ Can ping $DomainController" -ForegroundColor Green
} else {
    Write-Host "  ✗ Cannot ping $DomainController" -ForegroundColor Red
    $issues += "Ping failed"
}
Write-Host ""

# Test 3: LDAP Connectivity (port 389)
Write-Host "[3/6] Testing LDAP connectivity (port 389)..." -ForegroundColor Yellow
$ldapTest = Test-NetConnection -ComputerName $DomainController -Port 389 -WarningAction SilentlyContinue
if ($ldapTest.TcpTestSucceeded) {
    Write-Host "  ✓ LDAP port 389 is accessible" -ForegroundColor Green
} else {
    Write-Host "  ✗ LDAP port 389 is NOT accessible" -ForegroundColor Red
    $issues += "LDAP port blocked"
}
Write-Host ""

# Test 4: ADWS Connectivity (port 9389) - THE KEY TEST
Write-Host "[4/6] Testing ADWS connectivity (port 9389)..." -ForegroundColor Yellow
$adwsTest = Test-NetConnection -ComputerName $DomainController -Port 9389 -WarningAction SilentlyContinue
if ($adwsTest.TcpTestSucceeded) {
    Write-Host "  ✓ ADWS port 9389 is accessible" -ForegroundColor Green
} else {
    Write-Host "  ✗ ADWS port 9389 is NOT accessible" -ForegroundColor Red
    Write-Host "  This is the problem! AD PowerShell cmdlets need ADWS." -ForegroundColor Red
    $issues += "ADWS port 9389 blocked or service not running"
}
Write-Host ""

# Test 5: AD PowerShell Module
Write-Host "[5/6] Checking AD PowerShell module..." -ForegroundColor Yellow
$adModule = Get-Module -ListAvailable -Name ActiveDirectory
if ($adModule) {
    Write-Host "  ✓ Active Directory PowerShell module is available" -ForegroundColor Green
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
} else {
    Write-Host "  ✗ Active Directory PowerShell module not found" -ForegroundColor Red
    Write-Host "  Install with: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    $issues += "AD PowerShell module not installed"
}
Write-Host ""

# Test 6: Try to query AD
Write-Host "[6/6] Testing AD query via ADWS..." -ForegroundColor Yellow
if ($adModule) {
    try {
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Host "  ✓ Successfully queried AD domain: $($domain.DNSRoot)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Failed to query AD: $($_.Exception.Message)" -ForegroundColor Red
        $issues += "Cannot query AD (ADWS likely not working)"
    }
} else {
    Write-Host "  - Skipped (AD module not available)" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "===== Summary =====" -ForegroundColor Green
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "✓ All tests passed! ADWS connectivity is working." -ForegroundColor Green
    Write-Host ""
    Write-Host "You can proceed with:" -ForegroundColor Cyan
    Write-Host "  .\06-Install-SQLServer-Prep.ps1" -ForegroundColor White
} else {
    Write-Host "✗ Found $($issues.Count) issue(s):" -ForegroundColor Red
    Write-Host ""
    foreach ($issue in $issues) {
        Write-Host "  • $issue" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "===== Recommended Fixes =====" -ForegroundColor Yellow
    Write-Host ""
    
    if ($issues -match "ADWS port 9389") {
        Write-Host "[Fix 1] On DC01 - Ensure ADWS service is running:" -ForegroundColor Cyan
        Write-Host "  .\Fix-ADWS.ps1" -ForegroundColor White
        Write-Host ""
        
        Write-Host "[Fix 2] On your local machine - Add ADWS port to security group:" -ForegroundColor Cyan
        Write-Host "  ./add-security-group-rules.sh sql-ag-demo us-east-1" -ForegroundColor White
        Write-Host ""
        
        Write-Host "[Fix 3] Verify port is open:" -ForegroundColor Cyan
        Write-Host "  Test-NetConnection -ComputerName DC01 -Port 9389" -ForegroundColor White
        Write-Host ""
    }
    
    if ($issues -match "AD PowerShell module") {
        Write-Host "[Fix 4] Install AD PowerShell module:" -ForegroundColor Cyan
        Write-Host "  Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor White
        Write-Host ""
    }
    
    if ($issues -match "DNS") {
        Write-Host "[Fix 5] Check DNS configuration:" -ForegroundColor Cyan
        Write-Host "  ipconfig /all" -ForegroundColor White
        Write-Host "  nslookup DC01.contoso.local" -ForegroundColor White
        Write-Host ""
    }
}

Write-Host "===== Technical Details =====" -ForegroundColor Yellow
Write-Host ""
Write-Host "ADWS (Active Directory Web Services):" -ForegroundColor Cyan
Write-Host "  • Port: TCP 9389" -ForegroundColor White
Write-Host "  • Service: ADWS (on DC01)" -ForegroundColor White
Write-Host "  • Required for: AD PowerShell cmdlets from remote machines" -ForegroundColor White
Write-Host "  • Used by: Install-ADServiceAccount, Test-ADServiceAccount, etc." -ForegroundColor White
Write-Host ""
Write-Host "Without ADWS, you'll see errors like:" -ForegroundColor Cyan
Write-Host "  'Unable to contact the server. This may be because this server" -ForegroundColor White
Write-Host "   does not exist, it is currently down, or it does not have the" -ForegroundColor White
Write-Host "   Active Directory Web Services running.'" -ForegroundColor White
Write-Host ""

