# SQL Server Availability Group on AWS - Complete Setup Package

This package contains everything you need to set up a 2-node SQL Server Always On Availability Group in AWS.

---

## 🎯 What's New in Version 2.0

This version includes major enhancements for production-ready deployments:

- ✅ **Multi-Subnet Architecture:** Nodes deployed across 2 availability zones
- ✅ **SQL Server 2022:** Updated from SQL 2019 to SQL 2022 Developer Edition
- ✅ **Enhanced gMSA Management:** AD security groups for easier permission management
- ✅ **Dual IP Configuration:** CNO and AG Listener with 2 IPs (one per subnet)
- ✅ **Improved Failover:** Optimized cross-subnet failover settings
- ✅ **CloudFormation VPC:** Creates dedicated VPC with 2 subnets in different AZs

**Migration from v1.0:** If upgrading from the previous single-subnet setup, you'll need to redeploy using the new CloudFormation template. The multi-subnet architecture requires different IP addressing and cluster configuration.

---

## 📁 Package Contents

### Documentation

1. **Quick-Start-Guide.md** ⭐ **START HERE**
   - Step-by-step instructions for the entire setup
   - Condensed format for quick execution
   - Best for: Following along during setup

2. **SQL-AG-Setup-Guide.md**
   - Comprehensive guide with detailed explanations
   - Architecture diagrams and background info
   - Troubleshooting guide
   - Best for: Understanding the details

3. **Setup-Checklist.md**
   - Interactive checklist to track progress
   - Space for documenting your IPs and credentials
   - Issue tracking section
   - Best for: Staying organized during setup

### Infrastructure as Code

4. **SQL-AG-CloudFormation.yaml**
   - Automated EC2 instance deployment
   - Security group configuration
   - 3 instances (1 DC + 2 SQL nodes)
   - Estimated deployment: 5 minutes

### Scripts Folder

5. **Scripts/** (11 PowerShell/SQL scripts)
   - Automated configuration scripts
   - Numbered in execution order
   - See Scripts/README.md for details

---

## 🚀 Quick Start

### Three Simple Steps:

1. **Deploy Infrastructure (5 min)**
   ```bash
   # Get your public IP (macOS/Linux)
   MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32
   
   # Deploy stack (replace YOUR_KEY with your actual EC2 key pair name)
   aws cloudformation create-stack \
     --stack-name sql-ag-demo \
     --template-body file://SQL-AG-CloudFormation.yaml \
     --parameters \
       ParameterKey=KeyPairName,ParameterValue=YOUR_KEY \
       ParameterKey=YourIPAddress,ParameterValue=$MY_IP
   
   # Track progress
   watch -n 5 'aws cloudformation describe-stacks --stack-name sql-ag-demo --query "Stacks[0].StackStatus" --output text'
   ```

2. **Follow Quick-Start-Guide.md** (2-3 hours)
   - Copy scripts to each server
   - Execute scripts in numbered order
   - Follow validation steps

3. **Demo and Learn!**
   - Test failover scenarios
   - Practice AG operations
   - Understand HA architecture

---

## 📊 What You'll Build

```
┌──────────────────────────────────────────────────────────────────┐
│                    AWS VPC (10.0.0.0/16)                         │
│                                                                  │
│  ┌─── Subnet 1 (10.0.1.0/24) - AZ1 ────────────────────────┐   │
│  │                                                           │   │
│  │  ┌──────────────┐    ┌──────────────┐                   │   │
│  │  │    DC01      │    │    SQL01     │                   │   │
│  │  │  t3.medium   │    │  t3.xlarge   │                   │   │
│  │  │  Win2019     │◄───┤  Win2019     │                   │   │
│  │  │  AD DS       │    │  SQL 2022    │                   │   │
│  │  └──────────────┘    │  Primary     │                   │   │
│  │                      └──────────────┘                   │   │
│  │                                                           │   │
│  │  Cluster IP: 10.0.1.50                                  │   │
│  │  Listener IP: 10.0.1.51                                 │   │
│  └───────────────────────────────────────────────────────────┘   │
│                             │                                    │
│                      ┌──────┴───────┐                            │
│                      │   SQLAGL01   │                            │
│                      │Multi-Subnet  │                            │
│                      │   Listener   │                            │
│                      │  Port 59999  │                            │
│                      │  2 IPs (OR)  │                            │
│                      └──────┬───────┘                            │
│                             │                                    │
│  ┌─── Subnet 2 (10.0.2.0/24) - AZ2 ────────────────────────┐   │
│  │                                                           │   │
│  │                      ┌──────▼───────┐                   │   │
│  │                      │    SQL02     │                   │   │
│  │                      │  t3.xlarge   │                   │   │
│  │                      │  Win2019     │                   │   │
│  │                      │  SQL 2022    │                   │   │
│  │                      │  Secondary   │                   │   │
│  │                      └──────────────┘                   │   │
│  │                                                           │   │
│  │  Cluster IP: 10.0.2.50                                  │   │
│  │  Listener IP: 10.0.2.51                                 │   │
│  └───────────────────────────────────────────────────────────┘   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**Features:**
- ✅ Active Directory with gMSA service accounts
- ✅ Windows Server Failover Cluster (WSFC) with multi-subnet support
- ✅ SQL Server 2022 Developer Edition
- ✅ Multi-subnet AG deployment across 2 availability zones
- ✅ Synchronous replication with automatic failover
- ✅ Availability Group Listener for seamless failover
- ✅ Test database with sample data

---

## 📋 Prerequisites

### AWS Requirements
- AWS account with EC2 permissions
- EC2 key pair in target region
- Default VPC (or create one)
- Budget: ~$0.38/hour

### Local Requirements
- RDP client (Microsoft Remote Desktop for macOS, or built-in for Windows)
- Text editor
- AWS CLI (for CLI deployment)
- **macOS users:** If `curl ifconfig.me` fails, use `curl https://checkip.amazonaws.com` instead

### Knowledge Requirements
- Basic Windows Server administration
- SQL Server fundamentals
- RDP and remote administration
- PowerShell basics (helpful)

---

## ⏱️ Time Estimates

| Phase | Duration | Description |
|-------|----------|-------------|
| Infrastructure | 5-10 min | Deploy CloudFormation stack |
| Domain Controller | 20-30 min | Install AD, create gMSA |
| Domain Join | 10-15 min | Join SQL nodes to domain |
| Failover Cluster | 15-20 min | Install clustering, create WSFC |
| SQL Installation | 30-40 min | Install SQL on both nodes |
| Availability Group | 15-20 min | Create AG and listener |
| Validation | 10-15 min | Test AG health and failover |
| **TOTAL** | **2-3 hours** | Complete end-to-end setup |

---

## 💰 Cost Breakdown

**Running Costs (us-east-1):**
- DC01 (t3.medium): ~$0.0416/hour
- SQL01 (t3.xlarge): ~$0.1664/hour
- SQL02 (t3.xlarge): ~$0.1664/hour
- **Total: ~$0.38/hour** or **~$275/month**

**Storage:**
- DC01: 50 GB = ~$5/month
- SQL01: 150 GB = ~$15/month
- SQL02: 150 GB = ~$15/month
- **Total: ~$35/month**

**Grand Total if left running:** ~$310/month

**💡 Cost Saving Tips:**
- Stop instances when not in use (saves compute, not storage)
- Use this for demos/learning, then terminate
- For prolonged testing, schedule start/stop with AWS Systems Manager

---

## 🎯 Learning Objectives

By completing this setup, you'll learn:

1. **Active Directory for SQL**
   - AD DS installation and configuration
   - Group Managed Service Accounts (gMSA)
   - Domain-joined SQL Server best practices

2. **Windows Server Failover Clustering**
   - WSFC installation and configuration
   - Quorum models
   - Multi-node cluster management

3. **SQL Server AlwaysOn**
   - Availability Group architecture
   - Synchronous vs. asynchronous replication
   - Automatic and manual failover
   - AG Listeners and connection strings

4. **AWS Infrastructure**
   - EC2 instance management
   - Security groups for HA workloads
   - Networking for multi-node clusters

5. **High Availability Concepts**
   - RPO and RTO considerations
   - Failure scenarios and recovery
   - Monitoring and alerting

---

## 📖 Documentation Guide

### For Quick Setup (Minimal Reading)
1. Read: **Quick-Start-Guide.md**
2. Use: **Setup-Checklist.md** (track progress)
3. Run scripts in numbered order

### For Deep Understanding (Maximum Learning)
1. Read: **SQL-AG-Setup-Guide.md** (comprehensive)
2. Read: **Scripts/README.md** (understand each script)
3. Execute with: **Setup-Checklist.md**
4. Review: Troubleshooting sections as needed

### For Presentation/Demo
1. Pre-deploy infrastructure with CloudFormation
2. Use Quick-Start-Guide as demo script
3. Show key validation queries from 10-Validate-AG.sql
4. Demonstrate failover with 11-Test-Failover.sql

---

## 🔧 Common Customizations

### Change Domain Name

Update in these scripts:
- `01-Setup-DomainController.ps1` (line 7-8)
- `02-Configure-AD.ps1` (line 5-6)
- `03-Join-Domain.ps1` (line 6)
- `09-Create-AvailabilityGroup.ps1` (line 86, 94)

### Change AG/Listener Names

Update in:
- `09-Create-AvailabilityGroup.ps1` (line 9-10)
- All validation scripts

### Use Different SQL Version

Current setup uses SQL Server 2022 (MSSQL16.MSSQLSERVER).

To use a different version:
1. Download desired SQL version
2. Update paths in `06-Install-SQLServer-Prep.ps1`
3. Adjust instance paths (MSSQL16.MSSQLSERVER → version-specific)
   - SQL 2019: MSSQL15.MSSQLSERVER
   - SQL 2022: MSSQL16.MSSQLSERVER

### Add More Databases

After setup, on SQL01:
```sql
-- Create and backup new database
CREATE DATABASE [NewDB];
ALTER DATABASE [NewDB] SET RECOVERY FULL;
BACKUP DATABASE [NewDB] TO DISK = 'path\NewDB.bak';

-- Add to AG
ALTER AVAILABILITY GROUP [SQLAOAG01] ADD DATABASE [NewDB];
```

---

## 🐛 Troubleshooting Quick Reference

### macOS: Can't Get Public IP
If `curl ifconfig.me` fails on macOS, use alternatives:
```bash
# Option 1 (recommended for AWS)
MY_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')/32

# Option 2
MY_IP=$(curl -s https://api.ipify.org)/32

# Option 3
MY_IP=$(curl -s https://icanhazip.com | tr -d '\n')/32
```

### Can't Connect to Instances
- Check security group has your current IP
- Verify instances are running
- Get correct password from EC2

### Domain Join Fails
- Verify DC01 is running and promoted
- Check DNS on SQL node: `ipconfig /all`
- Should show DC01 IP as DNS server
- Test: `ping contoso.local`

### gMSA Installation Fails
```powershell
# On DC01, verify KDS key
Get-KdsRootKey

# Re-add computer accounts
Set-ADServiceAccount -Identity sqlsvc `
  -PrincipalsAllowedToRetrieveManagedPassword SQL01$, SQL02$
```

### Cluster Creation Fails
- Ignore storage-related warnings
- Ensure both nodes can ping each other
- Verify both nodes in same domain
- Check firewall allows cluster traffic

### AG Synchronization Issues
```sql
-- Check state
SELECT * FROM sys.dm_hadr_database_replica_states;

-- Resume if suspended
ALTER DATABASE [AGTestDB] SET HADR RESUME;
```

**For more troubleshooting:** See SQL-AG-Setup-Guide.md, Phase 8

---

## 🧹 Cleanup

### Stop for Later Resume
```bash
# Stop all instances (keeps configuration)
aws ec2 stop-instances --instance-ids i-xxx i-yyy i-zzz
```

### Complete Teardown
```bash
# Delete everything
aws cloudformation delete-stack --stack-name sql-ag-demo
```

---

## 📚 Additional Resources

### Microsoft Documentation
- [AlwaysOn Availability Groups](https://docs.microsoft.com/sql/database-engine/availability-groups/)
- [Group Managed Service Accounts](https://docs.microsoft.com/windows-server/security/group-managed-service-accounts/)
- [Windows Server Failover Clustering](https://docs.microsoft.com/windows-server/failover-clustering/)

### AWS Documentation
- [SQL Server on AWS Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/sql-server-ec2-best-practices/)
- [High Availability for SQL Server on EC2](https://aws.amazon.com/quickstart/architecture/sql/)

### Brent Ozar Resources
- Already in your Scripts folder: SQL-Server-First-Responder-Kit-dev

---

## 🤝 Support & Feedback

**Issues During Setup?**
1. Check Setup-Checklist.md for missed steps
2. Review Troubleshooting section in SQL-AG-Setup-Guide.md
3. Verify all prerequisites are met
4. Check CloudWatch logs for error details

**Want to Extend This?**
- Add read-only routing
- Configure automatic backups
- Set up monitoring with CloudWatch
- Add third node for geo-redundancy
- Implement S3 cloud witness

---

## ✅ Success Criteria

You'll know setup is successful when:

- [x] All instances running and domain-joined
- [x] WSFC operational with both nodes
- [x] SQL Server using gMSA service accounts
- [x] AG created with SYNCHRONIZED status
- [x] Listener accepts connections
- [x] Manual failover completes in < 5 seconds
- [x] Automatic failover completes in < 30 seconds
- [x] No data loss during failover
- [x] Both replicas show HEALTHY status

---

## 🎓 Next Steps After Setup

1. **Practice Operations**
   - Add/remove databases from AG
   - Perform various failover types
   - Test disaster recovery scenarios

2. **Implement Monitoring**
   - Set up Extended Events
   - Configure SQL Agent alerts
   - Add CloudWatch metrics

3. **Configure Backups**
   - Create backup jobs
   - Test restore procedures
   - Configure backup to S3

4. **Test Advanced Scenarios**
   - Network partition simulation
   - Latency testing
   - Load testing with listener

5. **Document Your Environment**
   - Create operational runbooks
   - Document connection strings
   - Maintain change log

---

**Version:** 2.0  
**Last Updated:** October 2025  
**Tested On:** Windows Server 2019, SQL Server 2022 Developer, AWS EC2, Multi-Subnet Deployment

**Author's Note:** This setup is designed for learning and demos. For production use, consider additional security hardening, monitoring, backup strategies, and review AWS best practices for SQL Server workloads.

