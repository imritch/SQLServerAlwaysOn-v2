# DC01 - Add SQL Server Computer Accounts to gMSA Security Group
# Run as CONTOSO\Administrator AFTER SQL01 and SQL02 have joined the domain

$ErrorActionPreference = "Stop"

$SQLServersGroupName = "SQL-Servers-gMSA"

Write-Host "===== Adding SQL Servers to gMSA Security Group =====" -ForegroundColor Green

# Check if SQL servers have joined domain
Write-Host "`nChecking if SQL servers are in domain..." -ForegroundColor Yellow

$sql01Computer = Get-ADComputer -Filter {Name -eq "SQL01"} -ErrorAction SilentlyContinue
$sql02Computer = Get-ADComputer -Filter {Name -eq "SQL02"} -ErrorAction SilentlyContinue

if (-not $sql01Computer) {
    Write-Host "WARNING: SQL01 has not joined the domain yet!" -ForegroundColor Red
    Write-Host "Run this script after SQL01 and SQL02 join the domain." -ForegroundColor Yellow
    exit
}

if (-not $sql02Computer) {
    Write-Host "WARNING: SQL02 has not joined the domain yet!" -ForegroundColor Red
    Write-Host "Run this script after SQL01 and SQL02 join the domain." -ForegroundColor Yellow
    exit
}

Write-Host "SQL01: Found in domain" -ForegroundColor Green
Write-Host "SQL02: Found in domain" -ForegroundColor Green

# Get the security group
Write-Host "`nChecking for security group '$SQLServersGroupName'..." -ForegroundColor Yellow
$securityGroup = Get-ADGroup -Filter {Name -eq $SQLServersGroupName} -ErrorAction SilentlyContinue

if (-not $securityGroup) {
    Write-Host "ERROR: Security group '$SQLServersGroupName' not found!" -ForegroundColor Red
    Write-Host "Ensure 02-Configure-AD.ps1 was run successfully." -ForegroundColor Yellow
    exit
}

Write-Host "Security group found: $SQLServersGroupName" -ForegroundColor Green

# Add SQL01 to security group
Write-Host "`n[1/2] Adding SQL01 computer account to '$SQLServersGroupName'..." -ForegroundColor Yellow

try {
    # Check if already a member
    $currentMembers = Get-ADGroupMember -Identity $SQLServersGroupName | Select-Object -ExpandProperty Name
    if ($currentMembers -contains "SQL01") {
        Write-Host "SQL01 is already a member of $SQLServersGroupName" -ForegroundColor Yellow
    } else {
        Add-ADGroupMember -Identity $SQLServersGroupName -Members $sql01Computer
        Write-Host "SQL01 added to $SQLServersGroupName successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "Error adding SQL01 to group: $_" -ForegroundColor Red
}

# Add SQL02 to security group
Write-Host "`n[2/2] Adding SQL02 computer account to '$SQLServersGroupName'..." -ForegroundColor Yellow

try {
    # Check if already a member
    $currentMembers = Get-ADGroupMember -Identity $SQLServersGroupName | Select-Object -ExpandProperty Name
    if ($currentMembers -contains "SQL02") {
        Write-Host "SQL02 is already a member of $SQLServersGroupName" -ForegroundColor Yellow
    } else {
        Add-ADGroupMember -Identity $SQLServersGroupName -Members $sql02Computer
        Write-Host "SQL02 added to $SQLServersGroupName successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "Error adding SQL02 to group: $_" -ForegroundColor Red
}

# Verify
Write-Host "`n===== Verification =====" -ForegroundColor Green

Write-Host "`nMembers of '$SQLServersGroupName':" -ForegroundColor Cyan
Get-ADGroupMember -Identity $SQLServersGroupName | ForEach-Object { 
    Write-Host "  - $($_.Name)" -ForegroundColor White
}

Write-Host "`ngMSA Principals:" -ForegroundColor Cyan
$sqlsvcPrincipals = (Get-ADServiceAccount -Identity "sqlsvc" -Properties PrincipalsAllowedToRetrieveManagedPassword).PrincipalsAllowedToRetrieveManagedPassword
$sqlagentPrincipals = (Get-ADServiceAccount -Identity "sqlagent" -Properties PrincipalsAllowedToRetrieveManagedPassword).PrincipalsAllowedToRetrieveManagedPassword

Write-Host "  sqlsvc can be retrieved by:" -ForegroundColor White
$sqlsvcPrincipals | ForEach-Object { 
    $principal = Get-ADObject -Identity $_ -ErrorAction SilentlyContinue
    Write-Host "    - $($principal.Name) ($($principal.ObjectClass))" -ForegroundColor Gray
}

Write-Host "  sqlagent can be retrieved by:" -ForegroundColor White
$sqlagentPrincipals | ForEach-Object { 
    $principal = Get-ADObject -Identity $_ -ErrorAction SilentlyContinue
    Write-Host "    - $($principal.Name) ($($principal.ObjectClass))" -ForegroundColor Gray
}

Write-Host "`n===== SQL Servers Added to gMSA Group Successfully! =====" -ForegroundColor Green
Write-Host "Next: Install SQL Server on SQL01 and SQL02" -ForegroundColor Yellow

