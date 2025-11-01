-- SQL01 - Create Test Database for AG
-- Run in SSMS on SQL01

-- Create sample database for AG
CREATE DATABASE AGTestDB;
GO

-- Set Recovery Model to FULL (required for AG)
ALTER DATABASE AGTestDB SET RECOVERY FULL;
GO

-- Create sample table
USE AGTestDB;
GO

CREATE TABLE dbo.TestData (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    DataValue NVARCHAR(100),
    CreatedDate DATETIME DEFAULT GETDATE()
);
GO

INSERT INTO dbo.TestData (DataValue)
VALUES ('Sample Data 1'), ('Sample Data 2'), ('Sample Data 3');
GO

-- Take full backup (required before adding to AG)
-- SQL Server 2022 uses MSSQL16
BACKUP DATABASE AGTestDB 
TO DISK = 'D:\MSSQL\BACKUP\AGTestDB_Full.bak'
WITH FORMAT, INIT, COMPRESSION;
GO

-- Take log backup
BACKUP LOG AGTestDB 
TO DISK = 'D:\MSSQL\BACKUP\AGTestDB_Log.trn'
WITH FORMAT, INIT, COMPRESSION;
GO

PRINT 'Database AGTestDB created and backed up successfully!';
PRINT 'Next: Copy backup files to SQL02 and run AG creation script';

