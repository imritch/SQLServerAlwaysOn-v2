-- SQL01 - Test Availability Group Failover
-- Run in SSMS

USE master;
GO

PRINT '===== Testing AG Failover =====';
PRINT '';

-- Check current primary
PRINT 'Current Primary Replica:';
SELECT 
    ar.replica_server_name AS ReplicaName,
    ars.role_desc AS Role
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ars.role_desc = 'PRIMARY';

PRINT '';
PRINT 'Initiating manual failover to secondary...';
PRINT 'Note: Run this on the SECONDARY replica (SQL02) to failover TO it';
PRINT '';

-- Manual failover (run on the replica you want to failover TO)
-- Uncomment the next line to execute failover
-- ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;

PRINT 'To perform failover:';
PRINT '1. Connect to SQL02 in SSMS';
PRINT '2. Run: ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;';
PRINT '3. Check that SQL02 is now PRIMARY';
PRINT '';

-- After failover, check new primary
PRINT 'After failover, verify:';
SELECT 
    ar.replica_server_name AS ReplicaName,
    ars.role_desc AS Role,
    ars.synchronization_health_desc AS SyncHealth
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ars.role_desc DESC;

PRINT '';
PRINT '===== Automatic Failover Test =====';
PRINT 'To test automatic failover:';
PRINT '1. Stop SQL Server service on current primary';
PRINT '2. Wait 10-15 seconds';
PRINT '3. AG should automatically failover to secondary';
PRINT '4. Connect via listener should still work';
PRINT '';
PRINT 'PowerShell command to stop SQL service:';
PRINT 'Stop-Service MSSQLSERVER -Force';

