# DNS Suffix Configuration for Windows Clustering in AWS

## The Problem

When creating a Windows Failover Cluster, you may encounter this error:

```
The clustered role was not successfully created.
The computer "SQL02" could not be reached.
This operation returned because the timeout period expired.
```

This happens even though:
- ✓ Ping works
- ✓ RDP works
- ✓ Both nodes are domain-joined
- ✓ `nslookup SQL02.contoso.local` works
- ✗ `nslookup SQL02` **fails** ← This is the issue!

## Root Cause

Windows Failover Clustering uses **short hostnames** (e.g., "SQL02") internally, not fully qualified domain names (FQDNs). 

By default in AWS EC2, Windows sets the DNS suffix to `ec2.internal`, so when you try to resolve "SQL02", Windows tries:
1. SQL02.ec2.internal ← **FAILS** (doesn't exist)
2. Gives up before trying contoso.local

The fix is to configure Windows to **"Append primary and connection specific DNS suffixes"**, which makes Windows try:
1. SQL02.contoso.local ← **SUCCESS!**

## The Solution (3 Options)

### Option 1: Automated (Run After Domain Join) ✅ **Recommended**

The domain join script now automatically configures this! If you used the updated `03-Join-Domain.ps1`, you're already good.

```powershell
# Already included in updated scripts:
# - 03-Join-Domain.ps1
# - 04c-Configure-Secondary-IPs-Windows.ps1
```

### Option 2: Standalone Script (If You Already Joined Domain)

If you already joined the domain before this fix, run this on **BOTH** SQL01 and SQL02:

```powershell
cd C:\SQLAGScripts
.\Configure-DNS-Suffix.ps1
```

This script:
- Sets connection-specific DNS suffix to "contoso.local"
- Configures DNS suffix search list
- Enables "Append primary and connection specific DNS suffixes"
- Flushes DNS cache
- Tests short name resolution

### Option 3: Manual Configuration (GUI)

If you prefer to do it manually:

1. Open **Control Panel** → **Network and Sharing Center**
2. Click **Change adapter settings**
3. Right-click on your network adapter → **Properties**
4. Select **Internet Protocol Version 4 (TCP/IPv4)** → **Properties**
5. Click **Advanced**
6. Go to the **DNS** tab
7. Select **"Append primary and connection specific DNS suffixes"**
8. Click **OK** → **OK** → **Close**
9. Reboot (or flush DNS: `ipconfig /flushdns`)
10. **Repeat on other node**

## Technical Details

### Registry Settings

The configuration sets these registry keys:

```powershell
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\"

# DNS suffix search list
Set-ItemProperty $regPath -Name "SearchList" -Value "contoso.local" -Type String

# Enable "Append primary and connection specific DNS suffixes"
# 1 = Append suffixes (default behavior)
# 0 = Use explicit search list only
Set-ItemProperty $regPath -Name "UseDomainNameDevolution" -Value 1 -Type DWord
```

### Connection-Specific Suffix

```powershell
# Set at adapter level
Set-DnsClient -InterfaceIndex X -ConnectionSpecificSuffix "contoso.local"
```

### How DNS Resolution Works After Fix

When you try to resolve "SQL02":

**Before fix:**
1. SQL02 (literal) - FAIL
2. SQL02.ec2.internal - FAIL
3. Give up ❌

**After fix:**
1. SQL02 (literal) - FAIL  
2. SQL02.contoso.local - **SUCCESS** ✅

## Verification

### Test 1: Short Name Resolution

```powershell
nslookup SQL01
nslookup SQL02
```

**Expected:** Both should resolve to private IPs

### Test 2: Diagnostic Script

```powershell
.\00-Pre-Cluster-Diagnostics.ps1
```

Look for these checks:
- [1b/11] Testing DNS Resolution (Short Names) ← Should pass ✓
- [1c/11] Checking DNS Suffix Configuration ← Should pass ✓

### Test 3: Registry Verification

```powershell
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\"

# Check search list
Get-ItemProperty $regPath -Name "SearchList"

# Check devolution setting
Get-ItemProperty $regPath -Name "UseDomainNameDevolution"
```

**Expected output:**
```
SearchList             : contoso.local
UseDomainNameDevolution: 1
```

### Test 4: Try Cluster Creation

```powershell
.\05-Create-WSFC.ps1
```

Should now complete without timeout!

## Why This Matters for AWS

### AWS-Specific Issue

In on-premises environments, DHCP typically sets the correct DNS suffix automatically. In AWS:

1. **EC2 Default:** DNS suffix is `ec2.internal` (AWS internal DNS)
2. **After Domain Join:** Windows adds `contoso.local` as primary suffix
3. **But:** Search order might still prioritize ec2.internal
4. **Result:** Short name resolution fails for domain computers

### Windows Clustering Behavior

Windows Failover Clustering (`Test-Cluster`, `New-Cluster`) uses **WMI and DCOM** for node communication, which internally use short hostnames. If short name resolution fails, cluster creation times out.

## Updated Scripts

The following scripts now automatically configure DNS suffix:

1. **`03-Join-Domain.ps1`** (lines 67-72)
   - Configures during domain join
   - Sets SearchList registry key
   - Enables UseDomainNameDevolution

2. **`04c-Configure-Secondary-IPs-Windows.ps1`** (lines 84-90)
   - Re-applies settings after network configuration
   - Ensures persistence

3. **`Configure-DNS-Suffix.ps1`** (new)
   - Standalone script for existing installations
   - Comprehensive verification
   - Tests short name resolution

4. **`00-Pre-Cluster-Diagnostics.ps1`** (tests 1b and 1c)
   - Detects missing DNS suffix configuration
   - Provides remediation steps

## Migration Path

### If You Already Have Nodes Set Up

**Run this on BOTH SQL01 and SQL02:**

```powershell
cd C:\SQLAGScripts
.\Configure-DNS-Suffix.ps1

# Verify
nslookup SQL01
nslookup SQL02

# Try cluster creation
.\05-Create-WSFC.ps1
```

### For New Deployments

Just use the updated scripts - it's automatic! ✅

```powershell
# Domain join (includes DNS suffix config)
.\03-Join-Domain.ps1

# Later, cluster creation will work
.\05-Create-WSFC.ps1
```

## Common Questions

### Q: Do I need to reboot after changing DNS settings?

**A:** Not required, but recommended. At minimum, flush DNS cache:
```powershell
ipconfig /flushdns
Clear-DnsClientCache
```

### Q: Will this affect normal DNS resolution?

**A:** No! It only adds "contoso.local" to the search list. All other DNS resolution continues to work normally.

### Q: Why didn't the domain join set this automatically?

**A:** Domain join does set the primary DNS suffix, but AWS EC2's default connection-specific suffix (`ec2.internal`) can take precedence. Our script explicitly configures the search order.

### Q: What if I have multiple domains?

**A:** Modify the SearchList to include all domains:
```powershell
Set-ItemProperty $regPath -Name "SearchList" -Value "contoso.local,otherdomain.com" -Type String
```

### Q: Can I verify this without trying cluster creation?

**A:** Yes! Run:
```powershell
.\Troubleshoot-Clustering.ps1 -TargetNode SQL02
```

Test 1b will specifically check short name resolution.

## Related Issues

This DNS suffix issue can also affect:

- **SQL Server AG Listener creation** (uses short names)
- **PowerShell remoting** (depends on WinRM and DNS)
- **Windows Admin Center** (requires short name resolution)
- **Any WMI-based management tools**

All are resolved by the same DNS suffix configuration.

## References

- [Microsoft: DNS Suffix Search List](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2008-R2-and-2008/cc959611(v=ws.10))
- [Windows Clustering Requirements](https://docs.microsoft.com/en-us/windows-server/failover-clustering/clustering-requirements)
- [AWS EC2 DNS Resolution](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/ec2-windows-dns.html)

## Quick Reference

| Symptom | Cause | Fix |
|---------|-------|-----|
| `nslookup SQL02` fails | DNS suffix not configured | Run `Configure-DNS-Suffix.ps1` |
| Cluster creation times out | Can't resolve short names | Same as above |
| `Test-Cluster` hangs | WMI can't reach nodes | Same as above |
| FQDN works but short name doesn't | Search list doesn't include domain | Same as above |

---

**Bottom Line:** For Windows Clustering in AWS to work, you **must** configure "Append primary and connection specific DNS suffixes" to include your domain. The updated scripts do this automatically! ✅

