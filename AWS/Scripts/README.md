# SQL Server Availability Group Setup Scripts

This folder contains all PowerShell and SQL scripts needed to set up a 2-node SQL Server Availability Group in AWS.

## Script Execution Order

### Phase 1: Domain Controller Setup (DC01)

1. **01-Setup-DomainController.ps1** (DC01)
   - Run as local Administrator
   - Installs AD DS and promotes to DC
   - Server will restart automatically

2. **02-Configure-AD.ps1** (DC01)
   - Run as CONTOSO\Administrator after restart
   - Creates OUs, gMSA accounts, and SQL admin user

### Phase 2: Join SQL Servers to Domain

3. **03-Join-Domain.ps1** (SQL01 and SQL02)
   - Run as local Administrator on both nodes
   - Configures DNS and joins to domain
   - Server will restart

### Phase 3: Install Failover Clustering

4. **04-Install-Failover-Clustering.ps1** (SQL01 and SQL02)
   - Run as CONTOSO\Administrator on both nodes
   - Installs Failover Clustering feature and enables firewall rules

**4b. 04b-Assign-Secondary-IPs.sh** (Run from your local machine)
   - **⚠️ CRITICAL for AWS Multi-Subnet AG**
   - Run AFTER step 4
   - Assigns secondary private IPs to SQL nodes at AWS ENI level
   - Bash script (macOS/Linux)
   - Usage: `./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1`

**4c. 04c-Configure-Secondary-IPs-Windows.ps1** (SQL01 and SQL02)
   - **⚠️ REQUIRED - Run AFTER 04b**
   - Run as Administrator on BOTH nodes
   - Configures Windows to recognize the secondary IPs
   - Converts network adapter from DHCP to static IP
   - Auto-detects node and adds appropriate secondary IPs

5. **05-Create-WSFC.ps1** (SQL01 only)
   - Run as CONTOSO\Administrator
   - Creates Windows Failover Cluster with multi-subnet support
   - Run only AFTER 04c is complete on both nodes

### Phase 4: Install SQL Server

6. **06-Install-SQLServer-Prep.ps1** (SQL01 and SQL02)
   - Run as CONTOSO\Administrator on both nodes
   - Prepares gMSA and directories
   - Then run SQL Server setup manually

7. **07-Enable-AlwaysOn.ps1** (SQL01 and SQL02)
   - Run as Administrator on both nodes after SQL installation
   - Enables AlwaysOn feature

### Phase 5: Create Availability Group

8. **08-Create-TestDatabase.sql** (SQL01)
   - Run in SSMS on SQL01
   - Creates sample database and takes backups

9. **09-Create-AvailabilityGroup.ps1** (SQL01)
   - Run as CONTOSO\Administrator
   - Creates endpoints, AG, and listener

### Phase 6: Validation and Testing

10. **10-Validate-AG.sql** (SQL01)
    - Run in SSMS
    - Validates AG health and synchronization

11. **11-Test-Failover.sql** (SQL01)
    - Run in SSMS
    - Tests manual and automatic failover

## Important Notes

### IP Addresses (AWS-Specific Requirement)

**⚠️ CRITICAL AWS DIFFERENCE:** Unlike on-premises clustering, AWS requires all virtual IPs (cluster IPs and listener IPs) to be pre-assigned as secondary private IPs to the ENIs (Elastic Network Interfaces) BEFORE using them in Windows clustering.

**Why?** AWS manages IP addresses at the ENI level. The cluster cannot dynamically claim IPs without them being pre-assigned to the ENI. This is due to how AWS handles ARP and routing at the VPC level.

**IP Allocation Strategy (from script 04b):**
- **SQL01 (10.0.1.x subnet):**
  - Primary IP: Auto-assigned (e.g., 10.0.1.107)
  - Secondary IP 1: 10.0.1.50 → Used for WSFC Cluster IP
  - Secondary IP 2: 10.0.1.51 → Used for AG Listener IP

- **SQL02 (10.0.2.x subnet):**
  - Primary IP: Auto-assigned (e.g., 10.0.2.239)
  - Secondary IP 1: 10.0.2.50 → Used for WSFC Cluster IP
  - Secondary IP 2: 10.0.2.51 → Used for AG Listener IP

**Other IPs needed:**
- DC01 private IP (for DNS configuration in step 03)

**Reference:** [AWS Documentation - Configure Secondary Private IPv4 Addresses](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/config-windows-multiple-ip.html) and [Migrating Windows Failover Clusters](https://docs.aws.amazon.com/prescriptive-guidance/latest/migration-microsoft-workloads-aws/migrating-failover-workloads.html)

### Credentials

Default credentials created by scripts:
- Domain: contoso.local
- Domain Admin: CONTOSO\Administrator (your chosen password)
- SQL Admin: CONTOSO\sqladmin (P@ssw0rd123!)
- gMSA: CONTOSO\sqlsvc$ (SQL Service)
- gMSA: CONTOSO\sqlagent$ (SQL Agent)

**IMPORTANT:** Change these passwords for production use!

### Prerequisites

Before running scripts:
1. All EC2 instances created and running
2. Security group configured with required ports (run add-security-group-rules.sh with correct VPC CIDR)
3. RDP access working to all instances
4. Source/Dest check disabled on SQL instances
5. **Secondary IPs assigned in AWS AND configured in Windows** (steps 04b and 04c)

### Troubleshooting

If a script fails:
1. Check the error message
2. Verify network connectivity between nodes
3. Ensure all prerequisites are met
4. Consult the main setup guide: SQL-AG-Setup-Guide.md

### Script Modifications

Some scripts require you to enter values interactively:
- DC01 IP address
- Cluster IP
- Listener IP
- Domain admin password

You can modify the scripts to hardcode these values if preferred.

## File Descriptions

| Script | Purpose | Run On | Prerequisites |
|--------|---------|--------|---------------|
| 01-Setup-DomainController.ps1 | Install AD DS | DC01 | None |
| 02-Configure-AD.ps1 | Configure AD for SQL AG | DC01 | Script 01 complete |
| 03-Join-Domain.ps1 | Join to domain | SQL01, SQL02 | Script 02 complete |
| 04-Install-Failover-Clustering.ps1 | Install clustering | SQL01, SQL02 | Script 03 complete |
| 04b-Assign-Secondary-IPs.sh | Assign AWS ENI IPs | Local machine | Script 04 complete |
| 04c-Configure-Secondary-IPs-Windows.ps1 | Configure IPs in Windows | SQL01, SQL02 | Script 04b complete |
| 05-Create-WSFC.ps1 | Create WSFC | SQL01 | Script 04c complete on both nodes |
| 06-Install-SQLServer-Prep.ps1 | Prepare for SQL install | SQL01, SQL02 | Script 05 complete |
| 07-Enable-AlwaysOn.ps1 | Enable AlwaysOn | SQL01, SQL02 | SQL Server installed |
| 08-Create-TestDatabase.sql | Create test DB | SQL01 | Script 07 complete |
| 09-Create-AvailabilityGroup.ps1 | Create AG | SQL01 | Script 08 complete |
| 10-Validate-AG.sql | Validate AG | SQL01 | Script 09 complete |
| 11-Test-Failover.sql | Test failover | SQL01, SQL02 | Script 10 complete |

## Estimated Time

- Phase 1 (DC Setup): 20-30 minutes
- Phase 2 (Domain Join): 10 minutes
- Phase 3 (Clustering): 15 minutes
- Phase 4 (SQL Install): 30-40 minutes
- Phase 5 (AG Creation): 15-20 minutes
- Phase 6 (Testing): 10 minutes

**Total:** 2-3 hours

## Support

Refer to the main guide (SQL-AG-Setup-Guide.md) for:
- Detailed explanations
- AWS infrastructure setup
- Troubleshooting guide
- Architecture diagrams
- Cleanup instructions

