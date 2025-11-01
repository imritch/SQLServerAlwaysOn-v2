# DC01 - Domain Controller Setup Script
# Run as Administrator

$ErrorActionPreference = "Stop"

# Configuration
$DomainName = "contoso.local"
$DomainNetBIOSName = "CONTOSO"
$SafeModePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

Write-Host "===== Domain Controller Setup for SQL AG =====" -ForegroundColor Green

# Check if computer name needs to be changed
$CurrentName = $env:COMPUTERNAME
if ($CurrentName -ne "DC01") {
    Write-Host "`n[Step 1a] Renaming computer to DC01..." -ForegroundColor Yellow
    Rename-Computer -NewName "DC01" -Force
    
    Write-Host "`nComputer renamed to DC01" -ForegroundColor Green
    Write-Host "System will restart in 10 seconds..." -ForegroundColor Yellow
    Write-Host "After restart, run this script again to continue setup." -ForegroundColor Cyan
    
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    exit
}

# Computer is already named DC01, proceed with DC setup
Write-Host "`nComputer name: DC01 - OK" -ForegroundColor Green

# Step 2: Install AD DS Role
Write-Host "`n[1/3] Installing Active Directory Domain Services..." -ForegroundColor Yellow
$adInstalled = (Get-WindowsFeature AD-Domain-Services).Installed

if (-not $adInstalled) {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Write-Host "AD DS installed successfully" -ForegroundColor Green
} else {
    Write-Host "AD DS already installed" -ForegroundColor Green
}

# Step 3: Promote to Domain Controller
Write-Host "`n[2/3] Promoting to Domain Controller (this takes 5-10 minutes)..." -ForegroundColor Yellow
Write-Host "Domain: $DomainName" -ForegroundColor Cyan

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $DomainNetBIOSName `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDns `
    -NoRebootOnCompletion `
    -Force

Write-Host "`n[3/3] Domain Controller installation complete!" -ForegroundColor Green
Write-Host "`nThe server will restart automatically in 30 seconds..." -ForegroundColor Yellow
Write-Host "After restart, login as: CONTOSO\Administrator" -ForegroundColor Cyan
Write-Host "Then run script: 02-Configure-AD.ps1" -ForegroundColor Cyan

Start-Sleep -Seconds 30
Restart-Computer -Force
