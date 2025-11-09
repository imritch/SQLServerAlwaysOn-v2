# DC01 - Configure Active Directory for SQL AG
# Run as CONTOSO\Administrator

$ErrorActionPreference = "Stop"

$DomainName = "contoso.local"
$DomainDN = "DC=contoso,DC=local"

Write-Host "===== Configuring Active Directory =====" -ForegroundColor Green

# Step 1: Create OUs
Write-Host "`n[1/6] Creating Organizational Units..." -ForegroundColor Yellow

$OUs = @("Servers", "ServiceAccounts", "SQLServers", "Groups")
foreach ($OU in $OUs) {
    try {
        New-ADOrganizationalUnit -Name $OU -Path $DomainDN -ProtectedFromAccidentalDeletion $true
        Write-Host "Created OU: $OU" -ForegroundColor Green
    } catch {
        Write-Host "OU $OU may already exist: $_" -ForegroundColor Yellow
    }
}

# Step 2: Create Security Group for SQL Servers (for gMSA access)
Write-Host "`n[2/6] Creating Security Group for SQL Servers..." -ForegroundColor Yellow

$SQLServersGroupName = "SQL-Servers-gMSA"
try {
    $existingGroup = Get-ADGroup -Filter {Name -eq $SQLServersGroupName} -ErrorAction SilentlyContinue
    if ($existingGroup) {
        Write-Host "Security group '$SQLServersGroupName' already exists" -ForegroundColor Yellow
    } else {
        New-ADGroup -Name $SQLServersGroupName `
            -GroupScope Global `
            -GroupCategory Security `
            -Path "OU=Groups,$DomainDN" `
            -Description "SQL Server computer accounts for gMSA password retrieval"
        
        Write-Host "Security group '$SQLServersGroupName' created successfully" -ForegroundColor Green
        Write-Host "Computer accounts will be added after domain join (see 02b-Update-gMSA-Permissions.ps1)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "Error creating security group: $_" -ForegroundColor Red
}

# Step 3: Create KDS Root Key for gMSA
Write-Host "`n[3/6] Creating KDS Root Key for gMSA..." -ForegroundColor Yellow
Write-Host "Note: In production, this takes 10 hours to replicate. We're forcing immediate availability." -ForegroundColor Cyan

try {
    # Check if key already exists
    $existingKey = Get-KdsRootKey
    if ($existingKey) {
        Write-Host "KDS Root Key already exists" -ForegroundColor Yellow
    } else {
        # For lab/demo: EffectiveTime 10 hours ago (makes it immediately usable)
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
        Write-Host "KDS Root Key created successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "Error creating KDS Root Key: $_" -ForegroundColor Red
}

# Step 4: Create SQL Service gMSA (using security group for permissions)
Write-Host "`n[4/6] Creating gMSA for SQL Server Service..." -ForegroundColor Yellow

$gMSAName = "sqlsvc"
$gMSADNSHostName = "$gMSAName.$DomainName"

try {
    $existingGMSA = Get-ADServiceAccount -Filter {Name -eq $gMSAName} -ErrorAction SilentlyContinue
    if ($existingGMSA) {
        Write-Host "gMSA '$gMSAName' already exists" -ForegroundColor Yellow
        # Update to use security group if not already set
        try {
            Set-ADServiceAccount -Identity $gMSAName `
                -PrincipalsAllowedToRetrieveManagedPassword $SQLServersGroupName
            Write-Host "Updated gMSA to use security group: $SQLServersGroupName" -ForegroundColor Green
        } catch {
            Write-Host "Could not update gMSA permissions: $_" -ForegroundColor Yellow
        }
    } else {
        # Create with security group as principal
        New-ADServiceAccount -Name $gMSAName `
            -DNSHostName $gMSADNSHostName `
            -PrincipalsAllowedToRetrieveManagedPassword $SQLServersGroupName `
            -Path "OU=ServiceAccounts,$DomainDN" `
            -Enabled $true
        
        Write-Host "gMSA '$gMSAName' created successfully" -ForegroundColor Green
        Write-Host "Principals allowed: $SQLServersGroupName (group)" -ForegroundColor Cyan
        Write-Host "NOTE: Add SQL server computer accounts to '$SQLServersGroupName' after domain join" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error creating gMSA: $_" -ForegroundColor Red
}

# Step 5: Create SQL Agent gMSA (using security group for permissions)
Write-Host "`n[5/6] Creating gMSA for SQL Server Agent..." -ForegroundColor Yellow

$gMSAAgentName = "sqlagent"
$gMSAAgentDNSHostName = "$gMSAAgentName.$DomainName"

try {
    $existingGMSA = Get-ADServiceAccount -Filter {Name -eq $gMSAAgentName} -ErrorAction SilentlyContinue
    if ($existingGMSA) {
        Write-Host "gMSA '$gMSAAgentName' already exists" -ForegroundColor Yellow
        # Update to use security group if not already set
        try {
            Set-ADServiceAccount -Identity $gMSAAgentName `
                -PrincipalsAllowedToRetrieveManagedPassword $SQLServersGroupName
            Write-Host "Updated gMSA to use security group: $SQLServersGroupName" -ForegroundColor Green
        } catch {
            Write-Host "Could not update gMSA permissions: $_" -ForegroundColor Yellow
        }
    } else {
        # Create with security group as principal
        New-ADServiceAccount -Name $gMSAAgentName `
            -DNSHostName $gMSAAgentDNSHostName `
            -PrincipalsAllowedToRetrieveManagedPassword $SQLServersGroupName `
            -Path "OU=ServiceAccounts,$DomainDN" `
            -Enabled $true
        
        Write-Host "gMSA '$gMSAAgentName' created successfully" -ForegroundColor Green
        Write-Host "Principals allowed: $SQLServersGroupName (group)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "Error creating gMSA: $_" -ForegroundColor Red
}

# Step 6: Create SQL Admin User
Write-Host "`n[6/6] Creating SQL Admin user..." -ForegroundColor Yellow

$SqlAdminUser = "sqladmin"
$SqlAdminPassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

try {
    New-ADUser -Name $SqlAdminUser `
        -AccountPassword $SqlAdminPassword `
        -Path "OU=ServiceAccounts,$DomainDN" `
        -Enabled $true `
        -PasswordNeverExpires $true `
        -CannotChangePassword $false
    
    # Add to Domain Admins (for installation purposes)
    Add-ADGroupMember -Identity "Domain Admins" -Members $SqlAdminUser
    
    Write-Host "SQL Admin user created: $SqlAdminUser" -ForegroundColor Green
    Write-Host "Password: P@ssw0rd123!" -ForegroundColor Cyan
} catch {
    Write-Host "SQL Admin user may already exist: $_" -ForegroundColor Yellow
}

# Summary
Write-Host "`n===== Active Directory Configuration Complete =====" -ForegroundColor Green
Write-Host "`nCreated Resources:" -ForegroundColor Cyan
Write-Host "  - Security Group: $SQLServersGroupName (for gMSA access)"
Write-Host "  - gMSA: CONTOSO\$gMSAName$ (SQL Service)"
Write-Host "  - gMSA: CONTOSO\$gMSAAgentName$ (SQL Agent)"
Write-Host "  - User: CONTOSO\$SqlAdminUser (Password: P@ssw0rd123!)"
Write-Host "`nIMPORTANT: After joining SQL01 and SQL02 to domain, run 02b-Update-gMSA-Permissions.ps1" -ForegroundColor Yellow
Write-Host "This will add the computer accounts to the '$SQLServersGroupName' security group." -ForegroundColor Cyan

