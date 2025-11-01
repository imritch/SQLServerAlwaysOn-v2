# Troubleshoot Windows Failover Clustering Connectivity
# Run this on SQL01 to diagnose connectivity issues with SQL02
# Run as CONTOSO\Administrator

param(
    [string]$TargetNode = "SQL02"
)

$ErrorActionPreference = "Continue"

Write-Host "===== Windows Failover Cluster Connectivity Troubleshooter =====" -ForegroundColor Green
Write-Host "Testing connectivity from $env:COMPUTERNAME to $TargetNode" -ForegroundColor Cyan
Write-Host ""

$issues = @()
$targetFQDN = "$TargetNode.contoso.local"

# Test 1: Basic Network Connectivity
Write-Host "[Test 1/10] Basic Network Connectivity (Ping)" -ForegroundColor Yellow
try {
    $pingResult = Test-Connection -ComputerName $TargetNode -Count 2 -Quiet
    if ($pingResult) {
        Write-Host "  ✓ Ping to $TargetNode successful" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Ping to $TargetNode FAILED" -ForegroundColor Red
        $issues += "Cannot ping $TargetNode"
    }
} catch {
    Write-Host "  ✗ Ping test failed: $_" -ForegroundColor Red
    $issues += "Ping test error"
}
Write-Host ""

# Test 2: DNS Resolution
Write-Host "[Test 2/10] DNS Resolution" -ForegroundColor Yellow
try {
    $dnsResult = Resolve-DnsName -Name $TargetNode -ErrorAction Stop
    Write-Host "  ✓ DNS resolution successful:" -ForegroundColor Green
    Write-Host "    Short name: $TargetNode -> $($dnsResult.IPAddress)" -ForegroundColor Cyan
    
    $dnsFQDN = Resolve-DnsName -Name $targetFQDN -ErrorAction Stop
    Write-Host "    FQDN: $targetFQDN -> $($dnsFQDN.IPAddress)" -ForegroundColor Cyan
} catch {
    Write-Host "  ✗ DNS resolution FAILED: $_" -ForegroundColor Red
    $issues += "DNS resolution failed for $TargetNode"
}
Write-Host ""

# Test 3: Reverse DNS Lookup
Write-Host "[Test 3/10] Reverse DNS Lookup" -ForegroundColor Yellow
try {
    $targetIP = (Resolve-DnsName -Name $TargetNode).IPAddress
    $reverseResult = Resolve-DnsName -Name $targetIP -ErrorAction Stop
    Write-Host "  ✓ Reverse DNS: $targetIP -> $($reverseResult.NameHost)" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Reverse DNS lookup failed (may not be critical)" -ForegroundColor Yellow
}
Write-Host ""

# Test 4: Windows Firewall Status
Write-Host "[Test 4/10] Windows Firewall Status (Local)" -ForegroundColor Yellow
$firewallProfiles = Get-NetFirewallProfile
foreach ($profile in $firewallProfiles) {
    $status = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
    $color = if ($profile.Enabled) { "Yellow" } else { "Green" }
    Write-Host "  $($profile.Name): $status" -ForegroundColor $color
}
Write-Host ""

# Test 5: Failover Clustering Firewall Rules (Local)
Write-Host "[Test 5/10] Failover Clustering Firewall Rules (Local)" -ForegroundColor Yellow
$clusterRules = Get-NetFirewallRule | Where-Object {$_.DisplayGroup -like "*Failover Cluster*"}
if ($clusterRules) {
    $enabledCount = ($clusterRules | Where-Object {$_.Enabled -eq $true}).Count
    $totalCount = $clusterRules.Count
    Write-Host "  Cluster firewall rules: $enabledCount enabled out of $totalCount total" -ForegroundColor Cyan
    
    if ($enabledCount -eq 0) {
        Write-Host "  ⚠ WARNING: No cluster firewall rules are enabled!" -ForegroundColor Red
        Write-Host "    Run: Enable-NetFirewallRule -DisplayGroup 'Failover Cluster Manager'" -ForegroundColor Yellow
        $issues += "Cluster firewall rules not enabled"
    } else {
        Write-Host "  ✓ Cluster firewall rules are enabled" -ForegroundColor Green
    }
} else {
    Write-Host "  ⚠ No Failover Clustering firewall rules found" -ForegroundColor Yellow
    Write-Host "    This means the Failover Clustering feature may not be installed" -ForegroundColor Yellow
}
Write-Host ""

# Test 6: SMB/File Sharing (Port 445)
Write-Host "[Test 6/10] SMB/File Sharing Connectivity (Port 445)" -ForegroundColor Yellow
try {
    $smbTest = Test-NetConnection -ComputerName $TargetNode -Port 445 -WarningAction SilentlyContinue
    if ($smbTest.TcpTestSucceeded) {
        Write-Host "  ✓ SMB port 445 is accessible" -ForegroundColor Green
    } else {
        Write-Host "  ✗ SMB port 445 is NOT accessible" -ForegroundColor Red
        $issues += "SMB port 445 blocked"
    }
} catch {
    Write-Host "  ✗ SMB test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 7: RPC Endpoint Mapper (Port 135)
Write-Host "[Test 7/10] RPC Endpoint Mapper (Port 135)" -ForegroundColor Yellow
try {
    $rpcTest = Test-NetConnection -ComputerName $TargetNode -Port 135 -WarningAction SilentlyContinue
    if ($rpcTest.TcpTestSucceeded) {
        Write-Host "  ✓ RPC port 135 is accessible" -ForegroundColor Green
    } else {
        Write-Host "  ✗ RPC port 135 is NOT accessible" -ForegroundColor Red
        $issues += "RPC port 135 blocked"
    }
} catch {
    Write-Host "  ✗ RPC test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 8: Cluster Service Port (3343)
Write-Host "[Test 8/10] Cluster Service Port (3343)" -ForegroundColor Yellow
try {
    $clusterPortTest = Test-NetConnection -ComputerName $TargetNode -Port 3343 -WarningAction SilentlyContinue
    if ($clusterPortTest.TcpTestSucceeded) {
        Write-Host "  ✓ Cluster port 3343 is accessible" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Cluster port 3343 is NOT accessible" -ForegroundColor Red
        $issues += "Cluster port 3343 blocked"
    }
} catch {
    Write-Host "  ✗ Cluster port test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 9: WinRM Connectivity (for remote management)
Write-Host "[Test 9/10] WinRM Connectivity (Remote Management)" -ForegroundColor Yellow
try {
    $winrmTest = Test-WSMan -ComputerName $targetFQDN -ErrorAction Stop
    Write-Host "  ✓ WinRM is accessible" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ WinRM is NOT accessible (may not be critical for clustering)" -ForegroundColor Yellow
}
Write-Host ""

# Test 10: Computer Account in AD
Write-Host "[Test 10/10] Active Directory Computer Object" -ForegroundColor Yellow
try {
    $adComputer = Get-ADComputer -Identity $TargetNode -ErrorAction Stop
    Write-Host "  ✓ Computer object found in AD: $($adComputer.DistinguishedName)" -ForegroundColor Green
    Write-Host "    DNS Hostname: $($adComputer.DNSHostName)" -ForegroundColor Cyan
    Write-Host "    Enabled: $($adComputer.Enabled)" -ForegroundColor Cyan
} catch {
    Write-Host "  ✗ Computer object NOT found in AD or not accessible" -ForegroundColor Red
    $issues += "Computer object not in AD"
}
Write-Host ""

# Summary
Write-Host "===== Troubleshooting Summary =====" -ForegroundColor Green
Write-Host ""

if ($issues.Count -eq 0) {
    Write-Host "✓ All tests passed! Cluster creation should work." -ForegroundColor Green
} else {
    Write-Host "✗ Found $($issues.Count) issue(s):" -ForegroundColor Red
    Write-Host ""
    foreach ($issue in $issues) {
        Write-Host "  • $issue" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "===== Recommended Fixes =====" -ForegroundColor Yellow
    Write-Host ""
    
    if ($issues -match "firewall") {
        Write-Host "[Fix 1] Enable Failover Clustering Firewall Rules on BOTH nodes:" -ForegroundColor Cyan
        Write-Host "  Enable-NetFirewallRule -DisplayGroup 'Failover Cluster Manager'" -ForegroundColor White
        Write-Host "  Enable-NetFirewallRule -DisplayGroup 'Failover Clusters'" -ForegroundColor White
        Write-Host ""
    }
    
    if ($issues -match "DNS") {
        Write-Host "[Fix 2] Check DNS Settings:" -ForegroundColor Cyan
        Write-Host "  • Verify DNS server points to DC01: ipconfig /all" -ForegroundColor White
        Write-Host "  • Flush DNS cache: ipconfig /flushdns" -ForegroundColor White
        Write-Host "  • Register DNS: ipconfig /registerdns" -ForegroundColor White
        Write-Host ""
    }
    
    if ($issues -match "SMB\|RPC\|Cluster port") {
        Write-Host "[Fix 3] Check AWS Security Group:" -ForegroundColor Cyan
        Write-Host "  • Run add-security-group-rules.sh from your local machine" -ForegroundColor White
        Write-Host "  • This adds missing NetBIOS and clustering ports" -ForegroundColor White
        Write-Host ""
    }
    
    if ($issues -match "AD") {
        Write-Host "[Fix 4] Verify Domain Join:" -ForegroundColor Cyan
        Write-Host "  • On SQL02, run: Test-ComputerSecureChannel -Verbose" -ForegroundColor White
        Write-Host "  • If failed, rejoin domain using 03-Join-Domain.ps1" -ForegroundColor White
        Write-Host ""
    }
}

Write-Host "===== Additional Diagnostic Commands =====" -ForegroundColor Yellow
Write-Host ""
Write-Host "Test cluster validation manually:" -ForegroundColor Cyan
Write-Host "  Test-Cluster -Node SQL01.contoso.local, SQL02.contoso.local" -ForegroundColor White
Write-Host ""
Write-Host "Check remote registry access:" -ForegroundColor Cyan
Write-Host "  Get-Service -ComputerName $TargetNode -Name 'RemoteRegistry'" -ForegroundColor White
Write-Host ""
Write-Host "Test Kerberos authentication:" -ForegroundColor Cyan
Write-Host "  klist get $targetFQDN" -ForegroundColor White
Write-Host ""
Write-Host "View cluster validation report:" -ForegroundColor Cyan
Write-Host "  Invoke-Item C:\Windows\Cluster\Reports\" -ForegroundColor White
Write-Host ""

