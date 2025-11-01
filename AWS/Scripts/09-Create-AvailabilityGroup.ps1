# SQL01 - Create Availability Group (Multi-Subnet)
# Run as CONTOSO\Administrator on SQL01

param(
    [string]$ListenerIP1 = "10.0.1.51",
    [string]$ListenerIP2 = "10.0.2.51",
    [string]$AGName = "SQLAOAG01",
    [string]$ListenerName = "SQLAGL01",
    [int]$ListenerPort = 1433,
    [int]$EndpointPort = 5022,
    [string]$DatabaseName = "AGTestDB",
    [string]$PrimaryReplica = "SQL01",
    [string]$SecondaryReplica = "SQL02"
)

$ErrorActionPreference = "Stop"

# Import SQL PowerShell module
Import-Module SqlServer

Write-Host "===== Creating Availability Group (Multi-Subnet) =====" -ForegroundColor Green
Write-Host "`nIMPORTANT: Multi-subnet AG Listener requires 2 IP addresses (one per subnet)" -ForegroundColor Yellow
Write-Host "These IPs must be pre-assigned at the AWS ENI level" -ForegroundColor Cyan

# Get subnet information
Write-Host "`nSubnet Information:" -ForegroundColor Cyan
Write-Host "  Subnet 1 (SQL01): 10.0.1.0/24" -ForegroundColor White
Write-Host "  Subnet 2 (SQL02): 10.0.2.0/24" -ForegroundColor White
Write-Host "`nPre-assigned Secondary IPs for Listener:" -ForegroundColor Yellow
Write-Host "  Listener IP 1: 10.0.1.51" -ForegroundColor White
Write-Host "  Listener IP 2: 10.0.2.51" -ForegroundColor White
Write-Host "`n(These were assigned in step 04b)" -ForegroundColor Cyan
Write-Host ""

Write-Host "===== Multi-Subnet AG Configuration =====" -ForegroundColor Green
Write-Host "AG Name: $AGName" -ForegroundColor Cyan
Write-Host "Listener Name: $ListenerName" -ForegroundColor Cyan
Write-Host "Listener IP 1 (Subnet 1): $ListenerIP1" -ForegroundColor Cyan
Write-Host "Listener IP 2 (Subnet 2): $ListenerIP2" -ForegroundColor Cyan
Write-Host "Listener Port: $ListenerPort" -ForegroundColor Cyan
Write-Host ""

# Pre-flight check: Verify IPs are NOT in Windows (should only be at ENI level)
Write-Host "[0/7] Pre-flight validation..." -ForegroundColor Yellow
$windowsIPs = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress

if ($windowsIPs -contains $ListenerIP1 -or $windowsIPs -contains $ListenerIP2) {
    Write-Host "ERROR: Listener IPs found in Windows configuration!" -ForegroundColor Red
    Write-Host "Secondary IPs must ONLY exist at AWS ENI level, not in Windows." -ForegroundColor Yellow
    Write-Host "Remove them from Windows network adapter before proceeding." -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ Listener IPs verified to be at ENI level only (not in Windows)" -ForegroundColor Green
Write-Host ""

# Step 0: Create SQL Server service account login on both servers
Write-Host "`n[0/7] Creating SQL Server service account logins..." -ForegroundColor Yellow

$createLoginScript = @"
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = N'CONTOSO\sqlsvc$')
BEGIN
    CREATE LOGIN [CONTOSO\sqlsvc$] FROM WINDOWS;
    PRINT 'Login created for CONTOSO\sqlsvc$';
END
ELSE
BEGIN
    PRINT 'Login already exists for CONTOSO\sqlsvc$';
END
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createLoginScript -TrustServerCertificate
Write-Host "Login verified/created on $PrimaryReplica" -ForegroundColor Green

Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $createLoginScript -TrustServerCertificate
Write-Host "Login verified/created on $SecondaryReplica" -ForegroundColor Green

# Step 1: Create Database Mirroring Endpoints on both replicas
Write-Host "`n[1/7] Creating database mirroring endpoints..." -ForegroundColor Yellow

# SQL01 Endpoint
$endpoint1Script = @"
IF NOT EXISTS (SELECT * FROM sys.endpoints WHERE name = 'Hadr_endpoint')
BEGIN
    CREATE ENDPOINT Hadr_endpoint
    STATE = STARTED
    AS TCP (LISTENER_PORT = $EndpointPort)
    FOR DATABASE_MIRRORING (ROLE = ALL);
END
GO

GRANT CONNECT ON ENDPOINT::Hadr_endpoint TO [CONTOSO\sqlsvc$];
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $endpoint1Script -TrustServerCertificate
Write-Host "Endpoint created on $PrimaryReplica" -ForegroundColor Green

# SQL02 Endpoint
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $endpoint1Script -TrustServerCertificate
Write-Host "Endpoint created on $SecondaryReplica" -ForegroundColor Green

# Step 2: Share backup folder on SQL01
Write-Host "`n[2/7] Setting up backup share..." -ForegroundColor Yellow

$backupPath = "D:\MSSQL\BACKUP"
$shareName = "SQLBackup"

try {
    New-SmbShare -Name $shareName -Path $backupPath -FullAccess "Everyone" -ErrorAction SilentlyContinue
    Write-Host "Backup share created: \\$PrimaryReplica\$shareName" -ForegroundColor Green
} catch {
    Write-Host "Share may already exist" -ForegroundColor Yellow
}

# Step 3: Create Availability Group on Primary
Write-Host "`n[3/7] Creating Availability Group on primary replica..." -ForegroundColor Yellow

$createAGScript = @"
CREATE AVAILABILITY GROUP [$AGName]
WITH (AUTOMATED_BACKUP_PREFERENCE = PRIMARY)
FOR DATABASE [$DatabaseName]
REPLICA ON 
    N'$PrimaryReplica' WITH (
        ENDPOINT_URL = N'TCP://$PrimaryReplica.contoso.local:$EndpointPort',
        FAILOVER_MODE = AUTOMATIC,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
        SEEDING_MODE = MANUAL
    ),
    N'$SecondaryReplica' WITH (
        ENDPOINT_URL = N'TCP://$SecondaryReplica.contoso.local:$EndpointPort',
        FAILOVER_MODE = AUTOMATIC,
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        BACKUP_PRIORITY = 50,
        SECONDARY_ROLE(ALLOW_CONNECTIONS = NO),
        SEEDING_MODE = MANUAL
    );
GO
"@

Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createAGScript -TrustServerCertificate
Write-Host "Availability Group '$AGName' created on $PrimaryReplica" -ForegroundColor Green

# Step 4: Join Secondary Replica
Write-Host "`n[4/7] Joining secondary replica to AG..." -ForegroundColor Yellow

$joinAGScript = "ALTER AVAILABILITY GROUP [$AGName] JOIN;"
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinAGScript -TrustServerCertificate
Write-Host "$SecondaryReplica joined to AG" -ForegroundColor Green

# Step 5: Restore database on Secondary
Write-Host "`n[5/7] Restoring database on secondary replica..." -ForegroundColor Yellow

$uncBackupPath = "\\$PrimaryReplica\$shareName"

Write-Host "Restoring full backup..." -ForegroundColor Cyan
$restoreFullScript = @"
RESTORE DATABASE [$DatabaseName]
FROM DISK = N'$uncBackupPath\AGTestDB_Full.bak'
WITH NORECOVERY, REPLACE;
GO
"@
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $restoreFullScript -TrustServerCertificate

Write-Host "Restoring log backup..." -ForegroundColor Cyan
$restoreLogScript = @"
RESTORE LOG [$DatabaseName]
FROM DISK = N'$uncBackupPath\AGTestDB_Log.trn'
WITH NORECOVERY;
GO
"@
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $restoreLogScript -TrustServerCertificate

# Join database to AG on secondary
Write-Host "Joining database to AG on secondary..." -ForegroundColor Cyan
$joinDBScript = "ALTER DATABASE [$DatabaseName] SET HADR AVAILABILITY GROUP = [$AGName];"
Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinDBScript -TrustServerCertificate

Write-Host "Database joined to AG on $SecondaryReplica" -ForegroundColor Green

# Step 6: Create AG Listener (Multi-Subnet with 2 IPs)
Write-Host "`n[6/7] Creating Availability Group Listener (Multi-Subnet)..." -ForegroundColor Yellow

$createListenerScript = @"
ALTER AVAILABILITY GROUP [$AGName]
ADD LISTENER N'$ListenerName' (
    WITH IP (
        (N'$ListenerIP1', N'255.255.255.0'),
        (N'$ListenerIP2', N'255.255.255.0')
    ),
    PORT = $ListenerPort
);
GO
"@

Write-Host "Creating listener with IPs: $ListenerIP1, $ListenerIP2" -ForegroundColor Cyan
Write-Host "The cluster will automatically detect and use the secondary" -ForegroundColor Yellow
Write-Host "IPs from the AWS ENI. This may take 30-60 seconds..." -ForegroundColor Yellow
Write-Host ""

try {
    Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $createListenerScript -QueryTimeout 120 -TrustServerCertificate
    Write-Host "✓ Multi-subnet listener '$ListenerName' created successfully" -ForegroundColor Green
    
    # Wait for listener to come online
    Write-Host "Waiting for listener resources to stabilize..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    
    # Verify listener is online
    $listenerCheck = @"
SELECT 
    dns_name,
    port,
    ip_configuration_string_from_cluster
FROM sys.availability_group_listeners
WHERE dns_name = N'$ListenerName';
"@
    
    $listenerInfo = Invoke-Sqlcmd -ServerInstance $PrimaryReplica -Query $listenerCheck -TrustServerCertificate
    if ($listenerInfo) {
        Write-Host "✓ Listener is online and registered in SQL Server" -ForegroundColor Green
        Write-Host ""
        Write-Host "Listener DNS: $($listenerInfo.dns_name)" -ForegroundColor Cyan
        Write-Host "Listener Port: $($listenerInfo.port)" -ForegroundColor Cyan
        Write-Host "Listener IPs: $($listenerInfo.ip_configuration_string_from_cluster)" -ForegroundColor Cyan
    }
    
    # Verify listener IPs in Failover Cluster
    Write-Host ""
    Write-Host "Verifying listener IPs in Windows Failover Cluster..." -ForegroundColor Yellow
    
    $listenerIPResources = Get-ClusterResource | Where-Object {
        $_.OwnerGroup -like "*$AGName*" -and $_.ResourceType -eq "IP Address"
    }
    
    if ($listenerIPResources) {
        $allOnline = $true
        foreach ($ipResource in $listenerIPResources) {
            $state = $ipResource.State
            $ipAddress = ($ipResource | Get-ClusterParameter | Where-Object {$_.Name -eq "Address"}).Value
            
            if ($state -eq "Online") {
                Write-Host "  ✓ Listener IP $ipAddress is Online" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Listener IP $ipAddress is $state" -ForegroundColor Red
                $allOnline = $false
            }
        }
        
        if (-not $allOnline) {
            Write-Host ""
            Write-Host "WARNING: Some listener IPs did not come online." -ForegroundColor Yellow
            Write-Host "This usually means the IPs are not assigned at the ENI level." -ForegroundColor Yellow
            Write-Host "Verify with: aws ec2 describe-network-interfaces" -ForegroundColor Cyan
        }
    }
    
} catch {
    Write-Host "ERROR creating listener: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "1. Secondary IPs not assigned at AWS ENI level (run 04b-Assign-Secondary-IPs.sh)" -ForegroundColor White
    Write-Host "2. IPs already in use by another cluster resource" -ForegroundColor White
    Write-Host "3. Availability Group not in healthy state" -ForegroundColor White
    Write-Host ""
    Write-Host "You can try creating the listener manually using:" -ForegroundColor Yellow
    Write-Host $createListenerScript -ForegroundColor Cyan
    exit 1
}

# Summary
Write-Host "`n===== Multi-Subnet Availability Group Creation Complete! =====" -ForegroundColor Green
Write-Host "`nAG Details:" -ForegroundColor Cyan
Write-Host "  AG Name: $AGName"
Write-Host "  Listener: $ListenerName"
Write-Host "  Listener IP 1 (Subnet 1): $ListenerIP1"
Write-Host "  Listener IP 2 (Subnet 2): $ListenerIP2"
Write-Host "  Listener Port: $ListenerPort"
Write-Host "  Primary: $PrimaryReplica (Subnet 1)"
Write-Host "  Secondary: $SecondaryReplica (Subnet 2)"
Write-Host "  Database: $DatabaseName"
Write-Host "  SQL Server Version: 2022"

Write-Host "`nTest connection string (REQUIRED: MultiSubnetFailover=True):" -ForegroundColor Yellow
Write-Host "  Server=$ListenerName,$ListenerPort;Database=$DatabaseName;Integrated Security=True;MultiSubnetFailover=True;" -ForegroundColor Cyan

Write-Host "`nConnection via listener DNS:" -ForegroundColor Yellow
Write-Host "  Server=$ListenerName.contoso.local,$ListenerPort;Database=$DatabaseName;Integrated Security=True;MultiSubnetFailover=True;" -ForegroundColor Cyan

Write-Host "`nIMPORTANT: Always use MultiSubnetFailover=True for multi-subnet AG connections!" -ForegroundColor Red

Write-Host "`nNext: Run validation script (10-Validate-AG.sql)" -ForegroundColor Yellow