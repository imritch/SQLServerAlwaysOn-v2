# Domain Join Process - Quick Reference

## Updated Script: 03-Join-Domain.ps1

This script now handles all the issues discovered during setup:

### Key Fixes Applied

1. **DNS Suffix Configuration**
   - AWS sets DNS suffix to `ec2.internal` by default
   - Script now sets it to `contoso.local` (required for domain join)

2. **Two-Stage Process**
   - **First Run**: Renames computer → Reboots
   - **Second Run**: Joins domain → Reboots

3. **Explicit DC Server**
   - Uses `-Server dc01.contoso.local` parameter
   - More reliable than automatic DC discovery

4. **NetBIOS Enabled**
   - Enables NetBIOS over TCP/IP (required for some AD operations)

5. **Registry-Level Domain Settings**
   - Sets domain in registry for proper AD integration

6. **Hostname Resolution Check**
   - Verifies `dc01.contoso.local` resolves before attempting join
   - Fails fast with helpful error message

### Usage

On SQL01 or SQL02:

```powershell
cd C:\SQLAGScripts
.\03-Join-Domain.ps1

# First run (if not renamed):
Enter computer name (SQL01 or SQL02): SQL01
# -> Renames and reboots

# Second run (after reboot):
Enter computer name (SQL01 or SQL02): SQL01
Enter DC01 Private IP (e.g., 172.31.x.x): 172.31.23.201
Enter CONTOSO\Administrator password: ************
# -> Joins domain and reboots
```

### Troubleshooting

If domain join still fails:

#### 1. Check DC DNS Record (on DC01)
```powershell
Get-DnsServerResourceRecord -ZoneName "contoso.local" -Name "dc01"
# Should show: 172.31.23.201

# If missing:
Add-DnsServerResourceRecordA -ZoneName "contoso.local" -Name "dc01" -IPv4Address "172.31.23.201"
```

#### 2. Delete Stale Computer Account (on DC01)
```powershell
Get-ADComputer -Filter {Name -eq "SQL01"}
Remove-ADComputer -Identity "SQL01" -Confirm:$false
```

#### 3. Check Firewall (on DC01)
```powershell
Get-NetFirewallProfile | Select Name, Enabled
# If enabled:
Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False
```

#### 4. Verify Security Group Rules (AWS)
Ensure these ports are open in the security group:
- DNS: 53 (TCP/UDP)
- Kerberos: 88 (TCP/UDP)
- LDAP: 389 (TCP/UDP)
- SMB: 445 (TCP)
- RPC: 135 (TCP)
- Dynamic RPC: 49152-65535 (TCP)

#### 5. Manual Domain Join (if script fails)
```powershell
# Set DNS and suffix
$DC_IP = "172.31.23.201"
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DC_IP
Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix "contoso.local"

# Clear cache
ipconfig /flushdns
Clear-DnsClientCache

# Test
nslookup dc01.contoso.local

# Join
$cred = Get-Credential CONTOSO\Administrator
Add-Computer -DomainName contoso.local -Server dc01.contoso.local -Credential $cred -Restart
```

### After Domain Join

Once both SQL01 and SQL02 are domain-joined:

1. **Update gMSA Permissions** (on DC01):
   ```powershell
   cd C:\SQLAGScripts
   .\02b-Update-gMSA-Permissions.ps1
   ```

2. **Verify Domain Membership**:
   ```powershell
   # On SQL01/SQL02
   (Get-WmiObject Win32_ComputerSystem).Domain
   # Should show: contoso.local
   ```

3. **Continue with Setup**:
   - Install Failover Clustering (`04-Install-Failover-Clustering.ps1`)
   - Create WSFC (`05-Create-WSFC.ps1`)
   - Install SQL Server

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `The specified domain either does not exist or could not be contacted` | DNS suffix wrong | Script now fixes this automatically |
| `Cannot find an object with identity: 'SQL01$'` | Computer not in domain yet | Normal - run `02b-Update-gMSA-Permissions.ps1` after domain join |
| `ERROR_NO_SUCH_DOMAIN` | DNS suffix issue | Script sets it correctly now |
| `Host (A) records missing` | DC hostname not resolving | Script checks this and provides fix instructions |
| `Computer failed to join` after rename | Reboot needed | Script now handles this in two stages |

### Testing Domain Membership

After successful join and reboot:

```powershell
# Check domain
(Get-WmiObject Win32_ComputerSystem).Domain

# Check DNS suffix
Get-DnsClient | Select InterfaceAlias, ConnectionSpecificSuffix

# Test AD connectivity
nltest /dsgetdc:contoso.local

# Verify group policy
gpupdate /force
gpresult /r
```

All tests should succeed if domain join was successful!

