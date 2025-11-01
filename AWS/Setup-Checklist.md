# SQL Server AG Setup Checklist

Use this checklist to track your progress through the setup.

---

## Pre-Deployment

- [ ] AWS account with appropriate permissions
- [ ] EC2 key pair created
- [ ] Current public IP noted for security group
- [ ] CloudFormation template downloaded
- [ ] All scripts downloaded to local machine

---

## Phase 1: Infrastructure (30 min)

- [ ] CloudFormation stack deployed
- [ ] Stack creation completed successfully
- [ ] Instance IPs noted from outputs:
  - DC01 Private IP: ________________
  - DC01 Public IP: ________________
  - SQL01 Private IP: ________________
  - SQL01 Public IP: ________________
  - SQL02 Private IP: ________________
  - SQL02 Public IP: ________________
- [ ] Windows passwords retrieved for all instances
- [ ] RDP access verified to DC01
- [ ] RDP access verified to SQL01
- [ ] RDP access verified to SQL02

---

## Phase 2: Domain Controller Setup (20 min)

**On DC01:**

- [ ] Scripts copied to `C:\SQLAGScripts\`
- [ ] Script `01-Setup-DomainController.ps1` executed
- [ ] DC01 restarted automatically
- [ ] RDP back as `CONTOSO\Administrator`
- [ ] Script `02-Configure-AD.ps1` executed
- [ ] Active Directory configured successfully
- [ ] gMSA accounts created (sqlsvc$, sqlagent$)
- [ ] SQL admin user created (sqladmin)
- [ ] Verified in Active Directory Users and Computers

---

## Phase 3: Join SQL Nodes to Domain (15 min)

**On SQL01:**

- [ ] Scripts copied to `C:\SQLAGScripts\`
- [ ] Script `03-Join-Domain.ps1` executed
- [ ] Domain IP entered: ________________
- [ ] Computer renamed to SQL01
- [ ] Joined to domain successfully
- [ ] SQL01 restarted
- [ ] RDP back as `CONTOSO\Administrator`
- [ ] Verified domain membership: `(Get-WmiObject Win32_ComputerSystem).Domain`

**On SQL02:**

- [ ] Scripts copied to `C:\SQLAGScripts\`
- [ ] Script `03-Join-Domain.ps1` executed
- [ ] Domain IP entered: ________________
- [ ] Computer renamed to SQL02
- [ ] Joined to domain successfully
- [ ] SQL02 restarted
- [ ] RDP back as `CONTOSO\Administrator`
- [ ] Verified domain membership: `(Get-WmiObject Win32_ComputerSystem).Domain`

---

## Phase 4: Windows Failover Cluster (20 min)

**On SQL01:**

- [ ] Script `04-Install-Failover-Clustering.ps1` executed
- [ ] Failover Clustering feature installed

**On SQL02:**

- [ ] Script `04-Install-Failover-Clustering.ps1` executed
- [ ] Failover Clustering feature installed

**On Local Machine (AWS Secondary IP Assignment):**

- [ ] Script `04b-Assign-Secondary-IPs.sh` executed from macOS/Linux terminal
- [ ] Secondary IPs assigned to SQL01 at AWS level: 10.0.1.50, 10.0.1.51
- [ ] Secondary IPs assigned to SQL02 at AWS level: 10.0.2.50, 10.0.2.51
- [ ] Verified IPs in AWS EC2 console (Network Interfaces)
- [ ] **⚠️ IMPORTANT:** Do NOT manually configure these IPs in Windows - Failover Cluster will handle it

**On SQL01 (create cluster):**

- [ ] Script `05-Create-WSFC.ps1` executed
- [ ] Cluster IP 1 entered: 10.0.1.50 (Subnet 1)
- [ ] Cluster IP 2 entered: 10.0.2.50 (Subnet 2)
- [ ] Cluster validation run (warnings OK)
- [ ] Multi-subnet cluster created: SQLCLUSTER
- [ ] Both nodes visible in cluster: `Get-ClusterNode`
- [ ] Cluster quorum configured
- [ ] Verified cluster status: `Get-Cluster`
- [ ] Verified multi-subnet parameters configured

---

## Phase 5: SQL Server Installation (40 min)

**On SQL01:**

- [ ] SQL Server 2022 Developer Edition downloaded
- [ ] Media extracted to `C:\SQLInstall`
- [ ] Script `06-Install-SQLServer-Prep.ps1` executed
- [ ] gMSA accounts installed on SQL01
- [ ] gMSA test passed
- [ ] SQL Server setup.exe launched
- [ ] Features selected: Database Engine, Replication, Full-Text
- [ ] Instance: MSSQLSERVER (default)
- [ ] Service account: `CONTOSO\sqlsvc$`
- [ ] Agent account: `CONTOSO\sqlagent$`
- [ ] SQL Admins: CONTOSO\sqladmin, BUILTIN\Administrators
- [ ] SQL Server installed successfully
- [ ] Script `07-Enable-AlwaysOn.ps1` executed
- [ ] AlwaysOn enabled
- [ ] SQL Service restarted
- [ ] Verified in SQL Configuration Manager

**On SQL02:**

- [ ] SQL Server 2022 Developer Edition downloaded
- [ ] Media extracted to `C:\SQLInstall`
- [ ] Script `06-Install-SQLServer-Prep.ps1` executed
- [ ] gMSA accounts installed on SQL02
- [ ] gMSA test passed
- [ ] SQL Server setup.exe launched
- [ ] Features selected: Database Engine, Replication, Full-Text
- [ ] Instance: MSSQLSERVER (default)
- [ ] Service account: `CONTOSO\sqlsvc$`
- [ ] Agent account: `CONTOSO\sqlagent$`
- [ ] SQL Admins: CONTOSO\sqladmin, BUILTIN\Administrators
- [ ] SQL Server installed successfully
- [ ] Script `07-Enable-AlwaysOn.ps1` executed
- [ ] AlwaysOn enabled
- [ ] SQL Service restarted
- [ ] Verified in SQL Configuration Manager

---

## Phase 6: Availability Group Creation (20 min)

**On SQL01:**

- [ ] SSMS opened and connected to SQL01
- [ ] Script `08-Create-TestDatabase.sql` executed
- [ ] Database AGTestDB created
- [ ] Recovery model set to FULL
- [ ] Test data inserted
- [ ] Full backup completed
- [ ] Log backup completed
- [ ] Backup files exist in `C:\...\BACKUP\`
- [ ] Backup folder shared: `\\SQL01\SQLBackup`
- [ ] Script `09-Create-AvailabilityGroup.ps1` executed
- [ ] Listener IP 1 entered: 10.0.1.51 (Subnet 1)
- [ ] Listener IP 2 entered: 10.0.2.51 (Subnet 2)
- [ ] Endpoints created on both nodes
- [ ] Availability Group SQLAOAG01 created
- [ ] SQL02 joined to AG
- [ ] Database restored on SQL02
- [ ] Database joined to AG on SQL02
- [ ] Multi-subnet listener SQLAGL01 created with 2 IPs
- [ ] No errors in script output

---

## Phase 7: Validation (15 min)

**Health Checks:**

- [ ] Script `10-Validate-AG.sql` executed in SSMS
- [ ] Both replicas show ONLINE status
- [ ] Both replicas show CONNECTED state
- [ ] Both replicas show HEALTHY sync health
- [ ] Database shows SYNCHRONIZED state
- [ ] Listener shows correct DNS name and IP
- [ ] Endpoints are STARTED on port 5022

**Connectivity Tests:**

- [ ] DNS resolution works: `nslookup SQLAGL01.contoso.local`
- [ ] Listener connection works: `sqlcmd -S SQLAGL01,59999`
- [ ] Query via listener returns data
- [ ] Verified current primary: `SELECT @@SERVERNAME`

**Failover Tests:**

- [ ] Manual failover executed: `ALTER AVAILABILITY GROUP SQLAOAG01 FAILOVER;`
- [ ] Failover completed successfully
- [ ] SQL02 now shows as PRIMARY
- [ ] SQL01 now shows as SECONDARY
- [ ] Database still SYNCHRONIZED
- [ ] Listener still resolves and connects
- [ ] Failover back to SQL01 successful

**Automatic Failover Test:**

- [ ] Stopped SQL service on current primary
- [ ] Waited 10-15 seconds
- [ ] AG automatically failed over to secondary
- [ ] Listener still accessible
- [ ] No data loss
- [ ] Started SQL service on previous primary
- [ ] Previous primary rejoined as secondary

---

## Phase 8: Post-Setup (Optional)

**Documentation:**

- [ ] Took screenshots of AG dashboard in SSMS
- [ ] Documented IP addresses and configuration
- [ ] Saved connection strings
- [ ] Created runbook for common operations

**Monitoring Setup:**

- [ ] Extended Events configured for AG monitoring
- [ ] SQL Server Agent alerts configured
- [ ] CloudWatch agent installed (optional)
- [ ] Performance counters configured

**Backup Configuration:**

- [ ] Backup jobs created
- [ ] Backup preference set to secondary
- [ ] S3 integration configured (optional)
- [ ] Test restore performed

**Additional Testing:**

- [ ] Added second database to AG
- [ ] Tested AG with different workload
- [ ] Verified read-only routing (if configured)
- [ ] Tested with multi-subnet failover connection string

---

## Cleanup Checklist

**When Demo is Complete:**

- [ ] Documented any lessons learned
- [ ] Exported any necessary scripts or configs
- [ ] Stopped EC2 instances (if keeping for later)
  
  OR
  
- [ ] Deleted CloudFormation stack
- [ ] Verified all resources deleted
- [ ] Released Elastic IPs (if allocated)
- [ ] Verified no unexpected charges

---

## Common Issues Resolved

**Track any issues you encountered and how you resolved them:**

Issue: _______________________________________________  
Resolution: ___________________________________________

Issue: _______________________________________________  
Resolution: ___________________________________________

Issue: _______________________________________________  
Resolution: ___________________________________________

---

## Notes

**Important IPs:**
- DC01 Private IP: ________________
- SQL01 Primary IP: ________________
- SQL02 Primary IP: ________________
- Cluster IP 1 (Subnet 1): 10.0.1.50
- Cluster IP 2 (Subnet 2): 10.0.2.50
- Listener IP 1 (Subnet 1): 10.0.1.51
- Listener IP 2 (Subnet 2): 10.0.2.51

**Credentials:**
- Domain Admin: CONTOSO\Administrator / ______________
- SQL Admin: CONTOSO\sqladmin / P@ssw0rd123!

**Timeline:**
- Start Time: ______________
- DC Setup Completed: ______________
- Domain Join Completed: ______________
- Cluster Created: ______________
- SQL Installed: ______________
- AG Created: ______________
- End Time: ______________
- Total Duration: ______________

**Resources:**
- CloudFormation Stack Name: ______________
- DC01 Instance ID: ______________
- SQL01 Instance ID: ______________
- SQL02 Instance ID: ______________

---

## Success Criteria

You've successfully completed the setup when:

✅ All three instances are running and domain-joined  
✅ Windows Failover Cluster is operational with 2 nodes  
✅ SQL Server installed on both nodes with gMSA service accounts  
✅ Availability Group created with one database  
✅ AG Listener resolves and accepts connections  
✅ Manual failover works without errors  
✅ Automatic failover works within 30 seconds  
✅ No data loss during failover  
✅ Both replicas show SYNCHRONIZED state  

---

**Setup Date:** ________________  
**Completed By:** ________________  
**Status:** [ ] In Progress  [ ] Completed  [ ] Issues Encountered  

**Notes/Comments:**
_______________________________________________________________
_______________________________________________________________
_______________________________________________________________

