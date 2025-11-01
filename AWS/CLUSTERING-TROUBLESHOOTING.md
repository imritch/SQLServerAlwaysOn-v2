# Windows Failover Clustering Troubleshooting Guide

## Problem: "Computer SQL02 could not be reached"

### Root Cause

The cluster creation fails because **Windows Failover Clustering requires additional network ports** that are not in the default CloudFormation security group.

### Symptoms

1. Cluster creation times out with error: "This operation returned because the timeout period expired"
2. Failover Cluster Manager can reach SQL01 but not SQL02
3. Test-Cluster fails or times out

### The Issue

Your CloudFormation template includes many necessary ports, but is **missing critical Windows Clustering and NetBIOS ports**:

**Missing Ports:**
- TCP/UDP 137 - NetBIOS Name Service
- TCP/UDP 138 - NetBIOS Datagram Service  
- TCP 139 - NetBIOS Session Service
- TCP/UDP 464 - Kerberos Password Change
- TCP 5985-5986 - WinRM (for remote management)

**Also:**
- Windows Firewall on the nodes may be blocking Failover Clustering rules

## Solution: Three-Step Fix

### Step 1: Add Missing Security Group Rules (Run from your local machine)

```bash
cd /path/to/SQLServerAlwaysOn/AWS/Scripts

# Make script executable
chmod +x add-security-group-rules.sh

# Add missing ports to security group
./add-security-group-rules.sh sql-ag-demo us-east-1
```

**What this does:**
- Adds NetBIOS ports (137, 138, 139)
- Adds Kerberos password change port (464)
- Adds WinRM ports (5985, 5986)
- All ports are scoped to VPC CIDR (10.0.0.0/16) for security

### Step 2: Enable Windows Firewall Rules (Run on BOTH SQL nodes)

On **SQL01**:
```powershell
cd C:\SQLAGScripts
.\Fix-ClusteringFirewall.ps1
```

On **SQL02**:
```powershell
cd C:\SQLAGScripts
.\Fix-ClusteringFirewall.ps1
```

**What this does:**
- Enables "Failover Cluster Manager" firewall rule group
- Enables "Failover Clusters" firewall rule group
- Enables "File and Printer Sharing" (for SMB)
- Enables "Remote Event Log Management"
- Enables "Remote Service Management"

### Step 3: Verify Connectivity (Run on SQL01)

```powershell
cd C:\SQLAGScripts
.\Troubleshoot-Clustering.ps1 -TargetNode SQL02
```

**What this tests:**
1. ✓ Basic network connectivity (ping)
2. ✓ DNS resolution (forward and reverse)
3. ✓ Windows Firewall status
4. ✓ Failover Clustering firewall rules
5. ✓ SMB connectivity (port 445)
6. ✓ RPC connectivity (port 135)
7. ✓ Cluster service port (3343)
8. ✓ WinRM connectivity
9. ✓ Active Directory computer object
10. ✓ Overall readiness

### Step 4: Try Cluster Creation Again

After all tests pass:

```powershell
cd C:\SQLAGScripts
.\05-Create-WSFC.ps1
```

## Detailed Port Requirements for Windows Clustering

| Port | Protocol | Purpose |
|------|----------|---------|
| 53 | TCP/UDP | DNS |
| 88 | TCP/UDP | Kerberos Authentication |
| 135 | TCP | RPC Endpoint Mapper |
| 137 | UDP | NetBIOS Name Service |
| 138 | UDP | NetBIOS Datagram |
| 139 | TCP | NetBIOS Session |
| 389 | TCP/UDP | LDAP |
| 445 | TCP | SMB/CIFS |
| 464 | TCP/UDP | Kerberos Password Change |
| 636 | TCP | LDAPS |
| 3268-3269 | TCP | Global Catalog |
| 3343 | TCP/UDP | Windows Cluster Service |
| 5985-5986 | TCP | WinRM |
| 49152-65535 | TCP | Dynamic RPC |

## Common Error Messages and Causes

### Error 1: "Computer SQL02 could not be reached"
**Cause:** Firewall rules blocking communication
**Fix:** Run Step 1 and Step 2 above

### Error 2: "An error occurred creating cluster - timeout"
**Cause:** Network connectivity issues
**Fix:** 
1. Check security group has all required ports
2. Verify Windows Firewall rules are enabled
3. Ensure DNS is working (ipconfig /all should show DC01 as DNS server)

### Error 3: "The cluster name resource failed to come online"
**Cause:** Secondary IPs not assigned at ENI level
**Fix:**
```bash
# From your local machine
./04b-Assign-Secondary-IPs.sh sql-ag-demo us-east-1
```

### Error 4: DNS resolution failures
**Cause:** DNS not configured properly or not pointing to DC01
**Fix on affected node:**
```powershell
# Check current DNS servers
ipconfig /all

# If DNS doesn't show DC01 IP, reconfigure:
$Adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $Adapter.InterfaceIndex -ServerAddresses "172.31.10.100"

# Flush and re-register DNS
ipconfig /flushdns
ipconfig /registerdns
```

## Manual Verification Commands

### Test basic connectivity:
```powershell
Test-Connection -ComputerName SQL02 -Count 4
```

### Test DNS resolution:
```powershell
Resolve-DnsName SQL02
Resolve-DnsName SQL02.contoso.local
```

### Test SMB connectivity:
```powershell
Test-NetConnection -ComputerName SQL02 -Port 445
```

### Test RPC connectivity:
```powershell
Test-NetConnection -ComputerName SQL02 -Port 135
```

### Test cluster port:
```powershell
Test-NetConnection -ComputerName SQL02 -Port 3343
```

### Test cluster validation:
```powershell
Test-Cluster -Node SQL01.contoso.local, SQL02.contoso.local
```

### Check firewall rules:
```powershell
# See all cluster-related firewall rules
Get-NetFirewallRule | Where-Object {$_.DisplayGroup -like "*Cluster*"} | 
  Format-Table DisplayName, Enabled, Direction, Action

# See which are enabled
Get-NetFirewallRule | Where-Object {
  $_.DisplayGroup -like "*Cluster*" -and $_.Enabled -eq $true
} | Measure-Object
```

### Check domain membership:
```powershell
Test-ComputerSecureChannel -Verbose
Get-ADComputer -Identity SQL01
Get-ADComputer -Identity SQL02
```

## Automated Solution Script

I've created a master troubleshooting script that runs all checks:

```powershell
# On SQL01
.\Troubleshoot-Clustering.ps1 -TargetNode SQL02
```

This will:
- Test all connectivity
- Identify specific issues
- Provide specific remediation steps

## Prevention for Future Deployments

To avoid this issue in future CloudFormation deployments, update the security group in your CloudFormation template:

```yaml
# Add these rules to SQLAGSecurityGroup in SQL-AG-CloudFormation.yaml

# NetBIOS Name Service
- IpProtocol: udp
  FromPort: 137
  ToPort: 137
  CidrIp: !Ref VpcCIDR
  Description: NetBIOS Name Service

# NetBIOS Datagram
- IpProtocol: udp
  FromPort: 138
  ToPort: 138
  CidrIp: !Ref VpcCIDR
  Description: NetBIOS Datagram

# NetBIOS Session
- IpProtocol: tcp
  FromPort: 139
  ToPort: 139
  CidrIp: !Ref VpcCIDR
  Description: NetBIOS Session

# Kerberos Password Change
- IpProtocol: tcp
  FromPort: 464
  ToPort: 464
  CidrIp: !Ref VpcCIDR
  Description: Kerberos Password Change
- IpProtocol: udp
  FromPort: 464
  ToPort: 464
  CidrIp: !Ref VpcCIDR
  Description: Kerberos Password Change UDP

# WinRM
- IpProtocol: tcp
  FromPort: 5985
  ToPort: 5986
  CidrIp: !Ref VpcCIDR
  Description: WinRM
```

## References

- [Microsoft: Failover Cluster Network Requirements](https://docs.microsoft.com/en-us/windows-server/failover-clustering/clustering-requirements)
- [AWS: SQL Server Clustering Requirements](https://docs.aws.amazon.com/sql-server-ec2/latest/userguide/aws-sql-ec2-clustering.html)
- [Firewall Rules for Failover Clustering](https://docs.microsoft.com/en-us/troubleshoot/windows-server/high-availability/service-overview-and-network-port-requirements)

## Quick Checklist

Before creating a Windows Failover Cluster in AWS:

- [ ] Security group includes all required ports (run add-security-group-rules.sh)
- [ ] Secondary IPs assigned at ENI level (run 04b-Assign-Secondary-IPs.sh)
- [ ] Secondary IPs NOT in Windows (only at ENI level)
- [ ] Failover Clustering feature installed on both nodes (04-Install-Failover-Clustering.ps1)
- [ ] Windows Firewall cluster rules enabled on both nodes (Fix-ClusteringFirewall.ps1)
- [ ] DNS resolves both nodes correctly (points to DC01)
- [ ] Both nodes are domain-joined (CONTOSO\Administrator)
- [ ] Can ping both nodes from each other
- [ ] SMB (port 445) accessible between nodes
- [ ] Test-Cluster passes (or at least completes without timeout)

Use the troubleshooting script to verify all of these automatically:
```powershell
.\Troubleshoot-Clustering.ps1 -TargetNode SQL02
```

