# Outstanding Items

1. When executing 04d-Verify-Secondary-IPs.ps1, I first got an error as displayed below. 

I had to manually edit the script, had to add a line and then remove that line at the end of the script. 
When executed again, it worked. Some issue with the line terminator. 
Secondly, after the script executed successfully, it said that AWS CLI is not available in Windows. 
Do I need that logic in the script there? If not then remove that logic. 



```powershell
PS C:\SQLAGScripts\Scripts> .\04d-Verify-Secondary-IPs.ps1
At C:\SQLAGScripts\Scripts\04d-Verify-Secondary-IPs.ps1:151 char:26
+ Write-Host "  $cmdExample" -ForegroundColor Cyan
+                          ~~~~~~~~~~~~~~~~~~~~~~~
The string is missing the terminator: ".
At C:\SQLAGScripts\Scripts\04d-Verify-Secondary-IPs.ps1:125 char:64
+ if (-not $hasClusterInWindows -and -not $hasListenerInWindows) {
+                                                                ~
Missing closing '}' in statement block or type definition.
    + CategoryInfo          : ParserError: (:) [], ParseException
    + FullyQualifiedErrorId : TerminatorExpectedAtEndOfString

PS C:\SQLAGScripts\Scripts> .\04d-Verify-Secondary-IPs.ps1
===== Verifying Secondary IP Assignment =====

⚠ AWS CLI not available in Windows - skipping ENI verification
Continuing with local network validation only...

[1/3] Detecting current node...
Computer Name: SQL01
Primary IP: 10.0.1.9

Detected as: SQL01

[3/3] Verifying Windows IP configuration...
IPs configured in Windows:
  10.0.1.9

✓ Secondary IPs are NOT in Windows (correct for AWS)

===== Validation Summary =====

Node: SQL01
Primary IP (in Windows): 10.0.1.9
Cluster IP (at ENI only): 10.0.1.50
Listener IP (at ENI only): 10.0.1.51

Peer Node: SQL02
Peer Cluster IP: 10.0.2.50
Peer Listener IP: 10.0.2.51

All validations passed!
Ready to create Windows Failover Cluster

Next Step: Run 05-Create-WSFC.ps1 with these IPs:
  .\05-Create-WSFC.ps1 -ClusterIP1 10.0.1.50 -ClusterIP2 10.0.2.50

```


2. When executing 05-Create-WSFC.ps1, I got a similar line terminator error. Had to manually edit the script, had to add a line and then remove that line at the end of the script. 
Thereafter the script worked. 


3. Cluster creation was successful. I can verify the cluster and its resources in the Windows Server Failover Cluster Manager. However, the SQL Server prep script failed. 
Need to fix this. 

## Error Message

```powershell
PS C:\SQLAGScripts\Scripts> .\06-Install-SQLServer-Prep.ps1
===== SQL Server Installation Preparation on SQL01 =====

[0/3] Checking RSAT AD PowerShell module...
RSAT AD PowerShell module already installed
WARNING: Error initializing default drive: 'Unable to contact the server. This may be because this server does not
exist, it is currently down, or it does not have the Active Directory Web Services running.'.

[1/3] Installing gMSA accounts...
Error installing gMSAs: Unable to contact the server. This may be because this server does not exist, it is currently down, or it does not have the Active Directory Web Services running.
Make sure AD module is available and KDS key has replicated.

[2/3] Testing gMSA...
Test-ADServiceAccount : Unable to contact the server. This may be because this server does not exist, it is currently
down, or it does not have the Active Directory Web Services running.
At C:\SQLAGScripts\Scripts\06-Install-SQLServer-Prep.ps1:47 char:15
+ $testSqlSvc = Test-ADServiceAccount -Identity "sqlsvc"
+               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : ResourceUnavailable: (:) [Test-ADServiceAccount], ADServerDownException
    + FullyQualifiedErrorId : ActiveDirectoryServer:0,Microsoft.ActiveDirectory.Management.Commands.TestADServiceAccount
```
## Solution
Okay, this issue was caused because of required ports not being opened. 
 
Solution to this issue was execute the following scripts - 
1. .\Fix-ADWS.ps1 on DC01
2. .\add-security-group-rules.sh on your local machine

Following is the output of the original script after the required ports were opened on the Security Group.

```powershell

PS C:\SQLAGScripts\Scripts> .\06-Install-SQLServer-Prep.ps1
===== SQL Server Installation Preparation on SQL01 =====

[0/3] Checking RSAT AD PowerShell module...
RSAT AD PowerShell module already installed

[1/3] Installing gMSA accounts...
gMSAs installed successfully

[2/3] Testing gMSA...
gMSA test successful!

[3/3] Creating SQL Server 2022 directories...


    Directory: D:\MSSQL


Mode                LastWriteTime         Length Name
----                -------------         ------ ----
d-----       10/25/2025   8:09 PM                DATA
d-----       10/25/2025   8:09 PM                LOG
d-----       10/25/2025   8:09 PM                BACKUP

===== Preparation Complete =====

Now download and run SQL Server 2022 Developer Edition Setup:
Download from: https://www.microsoft.com/sql-server/sql-server-downloads

Setup configuration:
1. Features: Database Engine, Replication, Full-Text
2. Instance: MSSQLSERVER (default)
3. SQL Service Account: CONTOSO\sqlsvc$ (no password)
4. Agent Service Account: CONTOSO\sqlagent$ (no password)
5. SQL Admins: Add CONTOSO\sqladmin and BUILTIN\Administrators

After SQL Server 2022 installation, run: 07-Enable-AlwaysOn.ps1

```
4. SSMS
There is no step to install SSMS. 
Need to add a step in the guide to install SSMS. 

5. Enable AlwaysOn powershell script is failing. 
Error given below. 
Likely I am importing module without installing it first. 
Need to check and fix this. 

```powershell
PS C:\SQLAGScripts\Scripts> .\07-Enable-AlwaysOn.ps1
===== Enabling AlwaysOn High Availability =====
Error enabling AlwaysOn: The term 'Enable-SqlAlwaysOn' is not recognized as the name of a cmdlet, function, script file, or operable program. Check the spelling of the name, or if a path was included, verify that the path is correct and try again.

Manual steps:
1. Open SQL Server Configuration Manager
2. Right-click SQL Server (MSSQLSERVER) -> Properties
3. Go to AlwaysOn High Availability tab
4. Check 'Enable AlwaysOn Availability Groups'
5. Click OK and restart SQL Server service

===== AlwaysOn Configuration Complete =====
Run this script on both SQL01 and SQL02
Next: Create sample database and Availability Group from SQL01
```

## Solution
Updated the script to look for the sql server module and if not found, install it before importing the module. Works successfully now. 

6. The Create Availability Group powershell script is failing. 
There were two separate failures identified. 
First the script being run on SQL01 was not able to see SQL02. 
Tried Test-NetConnection -ComputerName SQL02 -Port 1433 to see if the port was open. 
It kept failing on TCP. 
Checked the protocols for SQL Server in the SQL Server Configuration Manager. 
Strangely, TCP was disabled on both SQL01 and SQL02. 
Enabled TCP manually on both SQL01 and SQL02. 
Thereafter Test-NetConnection -ComputerName SQL02 -Port 1433 passed. 

Secondly the script now is failing while on step 5/7 when it is joining the database to the AG on the secondary node. 
Error details below. 
Need to investigate and fix this. 


## Error

```powershell

PS C:\SQLAGScripts\Scripts> .\09-Create-AvailabilityGroup.ps1
===== Creating Availability Group (Multi-Subnet) =====

IMPORTANT: Multi-subnet AG Listener requires 2 IP addresses (one per subnet)
These IPs must be pre-assigned at the AWS ENI level

Subnet Information:
  Subnet 1 (SQL01): 10.0.1.0/24
  Subnet 2 (SQL02): 10.0.2.0/24

Pre-assigned Secondary IPs for Listener:
  Listener IP 1: 10.0.1.51
  Listener IP 2: 10.0.2.51

(These were assigned in step 04b)

===== Multi-Subnet AG Configuration =====
AG Name: SQLAOAG01
Listener Name: SQLAGL01
Listener IP 1 (Subnet 1): 10.0.1.51
Listener IP 2 (Subnet 2): 10.0.2.51
Listener Port: 1433

[0/7] Pre-flight validation...
✓ Listener IPs verified to be at ENI level only (not in Windows)


[0/7] Creating SQL Server service account logins...
Login verified/created on SQL01
Login verified/created on SQL02

[1/7] Creating database mirroring endpoints...
Endpoint created on SQL01
Endpoint created on SQL02

[2/7] Setting up backup share...
Backup share created: \\SQL01\SQLBackup

[3/7] Creating Availability Group on primary replica...
Availability Group 'SQLAOAG01' created on SQL01

[4/7] Joining secondary replica to AG...
SQL02 joined to AG

[5/7] Restoring database on secondary replica...
Restoring full backup...
Restoring log backup...
Joining database to AG on secondary...
Invoke-Sqlcmd : The connection to the primary replica is not active.  The command cannot be processed.
 Msg 35250, Level 16, State 7, Procedure , Line 1.
At C:\SQLAGScripts\Scripts\09-Create-AvailabilityGroup.ps1:180 char:1
+ Invoke-Sqlcmd -ServerInstance $SecondaryReplica -Query $joinDBScript  ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidOperation: (:) [Invoke-Sqlcmd], SqlPowerShellSqlExecutionException
    + FullyQualifiedErrorId : SqlError,Microsoft.SqlServer.Management.PowerShell.GetScriptCommand

```

7. Line Endings 

05-Create-WSFC.ps1
I still had to go and manually correct the line ending in the script in Windows environment. Created a new line and removed it and script worked after that. 
Need to find a solution for this so that it is not required to be done manually. 

Same issue observed with Fix-ADWS.ps1
Same issue observed with 09-Create-AvailabilityGroup.ps1

8. TCP/IP disabled on SQL Server instances.
Turned it on manually. 

9. 09-Create-AvailabilityGroup.ps1 failed. 
Tried Test-NetConnection SQL02 -port 1433 which failed. 
Disabled firewall on both SQL01 and SQL02.
Script worked and AG was created successfully. 
Need to fix this with scripts so that it doesn't have to be done manually. 




