-- SQL01 - Validate Availability Group
-- Run in SSMS on SQL01

USE master;
GO

PRINT '===== Availability Group Health Check =====';
PRINT '';

-- Check AG status
PRINT 'Availability Group Replicas Status:';
SELECT 
    ag.name AS AGName,
    ar.replica_server_name AS ReplicaName,
    ar.availability_mode_desc AS AvailabilityMode,
    ar.failover_mode_desc AS FailoverMode,
    ars.role_desc AS Role,
    ars.operational_state_desc AS OperationalState,
    ars.connected_state_desc AS ConnectedState,
    ars.synchronization_health_desc AS SyncHealth
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ar.replica_server_name;

PRINT '';
PRINT 'Database Synchronization Status:';
SELECT 
    db_name(drs.database_id) AS DatabaseName,
    ar.replica_server_name AS ReplicaName,
    drs.synchronization_state_desc AS SyncState,
    drs.synchronization_health_desc AS SyncHealth,
    drs.database_state_desc AS DatabaseState,
    drs.is_suspended AS IsSuspended,
    drs.suspend_reason_desc AS SuspendReason
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
ORDER BY DatabaseName, ReplicaName;

PRINT '';
PRINT 'Availability Group Listener:';
SELECT 
    agl.dns_name AS ListenerName,
    agl.port AS Port,
    agl.ip_configuration_string_from_cluster AS IPConfiguration
FROM sys.availability_group_listeners agl
JOIN sys.availability_groups ag ON agl.group_id = ag.group_id;

PRINT '';
PRINT 'Database Mirroring Endpoints:';
SELECT 
    name AS EndpointName,
    type_desc AS EndpointType,
    state_desc AS State,
    port AS Port
FROM sys.tcp_endpoints 
WHERE type_desc = 'DATABASE_MIRRORING';

PRINT '';
PRINT '===== Expected Results =====';
PRINT 'Replicas: Both should be ONLINE, CONNECTED, HEALTHY';
PRINT 'Database: SYNCHRONIZED on both replicas';
PRINT 'Listener: Should show DNS name and IP';
PRINT 'Endpoints: Should be STARTED on port 5022';
PRINT '';

-- Test connection to listener
PRINT 'Testing Listener Connection:';
PRINT 'Current Server: ' + @@SERVERNAME;
PRINT '';
PRINT 'Try connecting via listener:';
PRINT 'sqlcmd -S SQLAGL01,59999 -Q "SELECT @@SERVERNAME"';

