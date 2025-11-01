# Active Directory Web Services (ADWS) Issue

## The Problem

When running `06-Install-SQLServer-Prep.ps1` on SQL nodes, you get this error:

```
Error installing gMSAs: Unable to contact the server. This may be because this server 
does not exist, it is currently down, or it does not have the Active Directory Web 
Services running.
```

## Root Cause

**Port 9389 (ADWS) is missing from the AWS Security Group**, and/or the ADWS service is not running on DC01.

Active Directory PowerShell cmdlets (like `Install-ADServiceAccount`, `Test-ADServiceAccount`) use **ADWS** (Active Directory Web Services) on TCP port **9389** to communicate with the domain controller. Without this:

- ✗ Cannot install gMSA accounts remotely
- ✗ Cannot test gMSA accounts
- ✗ Cannot run most AD PowerShell cmdlets from SQL nodes

## Quick Fix (3 Steps)

### Step 1: Add Port 9389 to AWS Security Group (From your local machine)

```bash
cd /path/to/SQLServerAlwaysOn/AWS/Scripts
./add-security-group-rules.sh sql-ag-demo us-east-1
```

This now includes port 9389 for ADWS.

### Step 2: Ensure ADWS is Running on DC01

On **DC01**:

```powershell
cd C:\SQLAGScripts
.\Fix-ADWS.ps1
```

This will:
- Start the ADWS service
- Set it to automatic startup
- Enable firewall rules

### Step 3: Verify and Retry

On **SQL01**:

```powershell
# Test ADWS connectivity
.\Test-ADWS-Connectivity.ps1

# If all tests pass, try again
.\06-Install-SQLServer-Prep.ps1
```

## Detailed Explanation

### What is ADWS?

**ADWS (Active Directory Web Services)** is a Windows service that provides a web service interface to Active Directory. It's required for:

- PowerShell Active Directory module cmdlets
- Remote administration of Active Directory
- Modern AD management tools

### How it Works

```
SQL01 (running AD cmdlets)
    ↓
TCP Port 9389
    ↓
DC01 (ADWS service listening)
    ↓
Active Directory Database
```

### Why This Matters

The script `06-Install-SQLServer-Prep.ps1` needs to:
1. **Install gMSA** on SQL nodes (`Install-ADServiceAccount`)
2. **Test gMSA** functionality (`Test-ADServiceAccount`)

Both cmdlets require ADWS connectivity to DC01.

## Diagnostic Steps

### Test ADWS Connectivity

On **SQL01**:

```powershell
# Comprehensive test
.\Test-ADWS-Connectivity.ps1

# Manual port test
Test-NetConnection -ComputerName DC01.contoso.local -Port 9389

# Try a simple AD query
Get-ADDomain
```

### Check ADWS Service on DC01

On **DC01**:

```powershell
# Check service status
Get-Service ADWS

# Expected output:
# Status   Name               DisplayName
# ------   ----               -----------
# Running  ADWS               Active Directory Web Services
```

If not running:
```powershell
Start-Service ADWS
Set-Service ADWS -StartupType Automatic
```

### Verify Security Group

From your local machine:

```bash
# Check if port 9389 is in the security group
aws ec2 describe-security-groups \
  --group-ids <sg-id> \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`9389`]' \
  --output table
```

## Alternative: Run Directly on DC01

If you can't get ADWS working immediately, you can run the gMSA installation directly on DC01:

On **DC01**, for each SQL node:

```powershell
# Enable SQL01 to use gMSAs
Add-ADComputerServiceAccount -Identity SQL01 -ServiceAccount sqlsvc
Add-ADComputerServiceAccount -Identity SQL01 -ServiceAccount sqlagent

# Enable SQL02 to use gMSAs
Add-ADComputerServiceAccount -Identity SQL02 -ServiceAccount sqlsvc
Add-ADComputerServiceAccount -Identity SQL02 -ServiceAccount sqlagent
```

Then on **SQL01** and **SQL02**:

```powershell
# Install the gMSAs locally (ADWS not needed for this)
Install-ADServiceAccount -Identity sqlsvc
Install-ADServiceAccount -Identity sqlagent

# Test
Test-ADServiceAccount -Identity sqlsvc
Test-ADServiceAccount -Identity sqlagent
```

This works because the local machine can communicate with AD directly without ADWS.

## Prevention for Future

To avoid this in future CloudFormation deployments, add this to the security group:

```yaml
# In SQL-AG-CloudFormation.yaml, add to SecurityGroupIngress:

# Active Directory Web Services (ADWS)
- IpProtocol: tcp
  FromPort: 9389
  ToPort: 9389
  CidrIp: !Ref VpcCIDR
  Description: Active Directory Web Services (ADWS)
```

## Complete Port List for AD

For reference, here are all AD-related ports:

| Port | Protocol | Service | Purpose |
|------|----------|---------|---------|
| 53 | TCP/UDP | DNS | Name resolution |
| 88 | TCP/UDP | Kerberos | Authentication |
| 135 | TCP | RPC | Remote procedure calls |
| 137-139 | TCP/UDP | NetBIOS | Legacy name resolution |
| 389 | TCP/UDP | LDAP | Directory queries |
| 445 | TCP | SMB | File sharing |
| 464 | TCP/UDP | Kerberos | Password changes |
| 636 | TCP | LDAPS | Secure LDAP |
| 3268-3269 | TCP | Global Catalog | Forest-wide queries |
| **9389** | **TCP** | **ADWS** | **PowerShell remoting** ← Missing! |

## Common Scenarios

### Scenario 1: Fresh Deployment

**Solution:** Run `add-security-group-rules.sh` before joining SQL nodes to domain. This now includes ADWS port.

### Scenario 2: Existing Deployment (Your Case)

**Solution:**
1. Add port to security group: `./add-security-group-rules.sh`
2. Fix ADWS on DC01: `.\Fix-ADWS.ps1`
3. Retry: `.\06-Install-SQLServer-Prep.ps1`

### Scenario 3: ADWS Still Not Working

**Workaround:** Run gMSA commands directly on DC01 (see "Alternative" section above)

## Verification Checklist

Before running `06-Install-SQLServer-Prep.ps1`:

- [ ] Port 9389 added to AWS Security Group
- [ ] ADWS service running on DC01
- [ ] ADWS firewall rule enabled on DC01
- [ ] Can connect to DC01:9389 from SQL01
- [ ] AD PowerShell module installed on SQL nodes
- [ ] DNS resolution working (DC01.contoso.local)

Run this to verify all:
```powershell
.\Test-ADWS-Connectivity.ps1
```

## Scripts Summary

| Script | Purpose | Run On |
|--------|---------|---------|
| `add-security-group-rules.sh` | Add port 9389 to security group | Local machine |
| `Fix-ADWS.ps1` | Start/configure ADWS service | DC01 |
| `Test-ADWS-Connectivity.ps1` | Diagnose ADWS connectivity | SQL01/SQL02 |
| `06-Install-SQLServer-Prep.ps1` | Install gMSAs and prep for SQL | SQL01/SQL02 |

## Error Messages

### "Unable to contact the server"

**Meaning:** ADWS port 9389 is blocked or service not running

**Fix:** 
1. Add port to security group
2. Start ADWS on DC01

### "Active Directory Web Services running"

**Meaning:** Same as above - cannot reach ADWS

**Fix:** Same as above

### "This server does not exist"

**Meaning:** DNS resolution issue or server actually down

**Fix:** 
1. Check DC01 is running
2. Verify DNS: `nslookup DC01.contoso.local`

## Technical Details

### ADWS Service Details

```powershell
# Service name: ADWS
# Display name: Active Directory Web Services
# Binary path: %systemroot%\ADWS\Microsoft.ActiveDirectory.WebServices.exe
# Startup type: Automatic (Delayed Start)
# Port: TCP 9389
# Dependencies: None critical
```

### ADWS vs LDAP

| Feature | LDAP (389) | ADWS (9389) |
|---------|-----------|-------------|
| Protocol | LDAP | SOAP/XML over HTTP |
| Used by | Legacy tools, ldapsearch | PowerShell, modern tools |
| Performance | Fast, binary | Slower, XML-based |
| Features | Basic queries | Rich object model |
| Required for | Basic AD operations | PowerShell cmdlets |

Both are needed for full AD functionality.

## References

- [Microsoft: AD Web Services Overview](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/dd391908(v=ws.10))
- [ADWS Port Requirements](https://docs.microsoft.com/en-us/troubleshoot/windows-server/identity/config-firewall-for-ad-domains-and-trusts)
- [Active Directory PowerShell Module](https://docs.microsoft.com/en-us/powershell/module/activedirectory/)

## Quick Command Reference

```powershell
# On DC01 - Check ADWS
Get-Service ADWS
Start-Service ADWS
Set-Service ADWS -StartupType Automatic

# On SQL nodes - Test connectivity
Test-NetConnection -ComputerName DC01 -Port 9389
Import-Module ActiveDirectory
Get-ADDomain

# Install gMSA (requires ADWS)
Install-ADServiceAccount -Identity sqlsvc
Test-ADServiceAccount -Identity sqlsvc
```

---

**Bottom Line:** ADWS (port 9389) is required for AD PowerShell cmdlets. Add it to your security group and ensure the service is running on DC01.

