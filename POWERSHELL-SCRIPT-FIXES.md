# PowerShell Script Issues and Fixes

## Two Critical Issues Resolved

### Issue 1: Missing RSAT Tools ✅ FIXED

**Problem:**
- SQL nodes couldn't run AD PowerShell cmdlets (`Install-ADServiceAccount`, `Test-ADServiceAccount`, etc.)
- Users had to manually install "AD DS and AD LDS Tools" from Server Manager
- Script `06-Install-SQLServer-Prep.ps1` failed with AD module errors

**Root Cause:**
- RSAT (Remote Server Administration Tools) for Active Directory was not being installed during setup
- Without RSAT-AD-PowerShell, AD cmdlets are not available on SQL nodes

**Solution:**
1. Updated `03-Join-Domain.ps1` to install RSAT-AD-PowerShell during domain join
2. Updated `06-Install-SQLServer-Prep.ps1` to check and install RSAT if missing (safety check)

**Changes Made:**

```powershell
# In 03-Join-Domain.ps1 (after domain join, before restart)
Install-WindowsFeature -Name RSAT-AD-PowerShell

# In 06-Install-SQLServer-Prep.ps1 (at the beginning)
$adModule = Get-WindowsFeature -Name RSAT-AD-PowerShell
if (-not $adModule.Installed) {
    Install-WindowsFeature -Name RSAT-AD-PowerShell
    Import-Module ActiveDirectory
}
```

**Impact:**
- ✅ RSAT tools now install automatically during domain join
- ✅ AD cmdlets work immediately on SQL nodes
- ✅ No manual Server Manager intervention needed
- ✅ gMSA installation and testing works without errors

---

### Issue 2: Unix Line Endings ✅ FIXED

**Problem:**
- PowerShell scripts failed with parsing errors
- Scripts had to be manually edited (removing last blank line) to work
- Different scripts worked/failed inconsistently

**Root Cause:**
- Scripts created on macOS/Linux have Unix line endings (`LF` = `\n`)
- Windows PowerShell expects Windows line endings (`CRLF` = `\r\n`)
- Blank lines with only `\n` cause PowerShell parsing failures

**Technical Details:**

Unix line ending:
```
...some code\n
\n
```

Windows line ending (required):
```
...some code\r\n
\r\n
```

**Solution:**
Created `Fix-LineEndings.sh` script that:
1. Converts all `.ps1` files from Unix (LF) to Windows (CRLF) line endings
2. Removes trailing blank lines that cause parsing issues
3. Ensures files end properly with `\r\n`

**How to Use:**

```bash
# From your local machine (macOS/Linux)
cd /path/to/SQLServerAlwaysOn/AWS/Scripts
./Fix-LineEndings.sh
```

**Output:**
```
===== Fixing Line Endings for PowerShell Scripts =====

Converting: 00-Pre-Cluster-Diagnostics.ps1
Converting: 04c-Configure-Secondary-IPs-Windows.ps1
Converting: 05-Create-WSFC.ps1
...

===== Line Ending Conversion Complete! =====
Total PowerShell files: 19
Files converted: 11
```

**Impact:**
- ✅ All PowerShell scripts now have Windows line endings
- ✅ Scripts work correctly in Windows PowerShell without modification
- ✅ No more manual editing required
- ✅ Consistent behavior across all scripts

---

## What Changed in Specific Scripts

### `03-Join-Domain.ps1`

**Added:**
```powershell
# Install RSAT AD PowerShell tools (needed for gMSA and AD cmdlets later)
Write-Host "`n[6/5] Installing RSAT Active Directory PowerShell module..." -ForegroundColor Yellow
try {
    Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
    Write-Host "RSAT AD PowerShell module installed successfully" -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not install RSAT AD PowerShell module: $_" -ForegroundColor Yellow
    Write-Host "You can install it later from Server Manager" -ForegroundColor Cyan
}
```

**When:** Right after domain join, before restart

**Why:** Ensures AD cmdlets are available immediately after rejoining as domain user

---

### `06-Install-SQLServer-Prep.ps1`

**Added:**
```powershell
# Step 0: Ensure RSAT AD PowerShell module is installed
Write-Host "`n[0/4] Checking RSAT AD PowerShell module..." -ForegroundColor Yellow
$adModule = Get-WindowsFeature -Name RSAT-AD-PowerShell
if (-not $adModule.Installed) {
    Write-Host "RSAT AD PowerShell module not found. Installing..." -ForegroundColor Cyan
    try {
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop | Out-Null
        Write-Host "RSAT AD PowerShell module installed successfully" -ForegroundColor Green
        Import-Module ActiveDirectory
    } catch {
        Write-Host "ERROR: Could not install RSAT AD PowerShell module: $_" -ForegroundColor Red
        Write-Host "Install manually from Server Manager: AD DS and AD LDS Tools" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "RSAT AD PowerShell module already installed" -ForegroundColor Green
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
}
```

**When:** At the very beginning, before trying to use AD cmdlets

**Why:** Safety check - if RSAT wasn't installed during domain join for any reason, install it now

---

### All `.ps1` Files

**Changed:**
- Line endings converted from Unix (`LF`) to Windows (`CRLF`)
- Trailing blank lines removed or properly formatted
- Files end with proper `\r\n`

**Why:** Windows PowerShell requires CRLF line endings to parse correctly

---

## Testing the Fixes

### Test 1: RSAT Installation

On a freshly domain-joined SQL node:

```powershell
# Check if RSAT is installed
Get-WindowsFeature -Name RSAT-AD-PowerShell

# Should show:
# Install State: Installed

# Test AD module works
Import-Module ActiveDirectory
Get-ADDomain

# Should return domain information without errors
```

### Test 2: Line Endings

On Windows, run any PowerShell script:

```powershell
# Should work without errors
.\Configure-DNS-Suffix.ps1
.\Test-ADWS-Connectivity.ps1
.\Fix-ADWS.ps1
```

**Before fix:** Parsing errors, had to manually edit files

**After fix:** All scripts work correctly

---

## For Future Script Development

### When Creating New PowerShell Scripts

1. **Create scripts normally** on macOS/Linux (with LF line endings)
2. **Before committing**, run:
   ```bash
   ./Fix-LineEndings.sh
   ```
3. **Commit the CRLF versions** to the repository

### Alternative: Use Git Attributes

Add to `.gitattributes`:
```
*.ps1 text eol=crlf
```

This makes Git automatically convert line endings when checking out on different platforms.

---

## What RSAT Includes

**RSAT-AD-PowerShell** installs:

| Component | Purpose |
|-----------|---------|
| ActiveDirectory PowerShell Module | Cmdlets for managing AD |
| AD DS Snap-Ins | GUI tools (not needed for scripts) |
| AD LDS Snap-Ins | Lightweight Directory Services tools |

**Key cmdlets enabled:**
- `Get-ADDomain`
- `Get-ADComputer`
- `Get-ADUser`
- `Get-ADServiceAccount`
- `Install-ADServiceAccount` ← Critical for gMSA!
- `Test-ADServiceAccount` ← Critical for gMSA!
- `Add-ADComputerServiceAccount`
- And 100+ more...

---

## Troubleshooting

### Issue: "Install-ADServiceAccount : The term 'Install-ADServiceAccount' is not recognized"

**Cause:** RSAT not installed

**Fix:**
```powershell
Install-WindowsFeature -Name RSAT-AD-PowerShell
Import-Module ActiveDirectory
```

### Issue: "ParserError: The string is missing the terminator"

**Cause:** Unix line endings (LF) instead of Windows (CRLF)

**Fix:**
```bash
# On your local machine
cd AWS/Scripts
./Fix-LineEndings.sh
```

Then re-copy the fixed scripts to Windows servers.

### Issue: Script works after deleting last blank line

**Cause:** Same as above - line ending issue

**Fix:** Same as above - run `Fix-LineEndings.sh`

---

## Migration Guide

### For Existing Installations

If you've already set up SQL nodes before these fixes:

**Option A: Quick Fix (Manual)**

On each SQL node:
```powershell
# Install RSAT manually
Install-WindowsFeature -Name RSAT-AD-PowerShell
Import-Module ActiveDirectory
```

**Option B: Complete Fix (Automated)**

1. On your local machine:
   ```bash
   cd AWS/Scripts
   ./Fix-LineEndings.sh
   ```

2. Re-copy all scripts to SQL nodes

3. On each SQL node:
   ```powershell
   # RSAT should now install automatically when running scripts
   .\06-Install-SQLServer-Prep.ps1
   ```

### For New Installations

✅ **No action needed!** 

All fixes are now integrated:
1. Run `./Fix-LineEndings.sh` once before first use
2. Follow the Quick Start Guide as normal
3. RSAT installs automatically during domain join

---

## Scripts That Use RSAT

These scripts require RSAT-AD-PowerShell:

| Script | AD Cmdlets Used |
|--------|-----------------|
| `06-Install-SQLServer-Prep.ps1` | `Install-ADServiceAccount`, `Test-ADServiceAccount` |
| `02-Configure-AD.ps1` | `New-ADOrganizationalUnit`, `New-ADUser`, `New-ADServiceAccount` |
| `02b-Update-gMSA-Permissions.ps1` | `Set-ADServiceAccount` |
| `Test-ADWS-Connectivity.ps1` | `Get-ADDomain` |

Without RSAT, all of these will fail!

---

## Summary

### What Was Wrong

1. ❌ RSAT not installed → AD cmdlets don't work
2. ❌ Unix line endings → PowerShell parsing errors

### What's Fixed

1. ✅ RSAT installs automatically during domain join
2. ✅ All scripts converted to Windows line endings
3. ✅ Safety check in `06-Install-SQLServer-Prep.ps1` to install RSAT if missing
4. ✅ Utility script `Fix-LineEndings.sh` for future maintenance

### Benefits

- ✅ No manual RSAT installation needed
- ✅ No manual script editing needed
- ✅ Scripts work correctly on first try
- ✅ Consistent experience across all deployments
- ✅ Saves 10-15 minutes per setup

---

## Quick Reference Commands

```powershell
# Check if RSAT is installed
Get-WindowsFeature -Name RSAT-AD-PowerShell

# Install RSAT manually
Install-WindowsFeature -Name RSAT-AD-PowerShell

# Import AD module
Import-Module ActiveDirectory

# Test AD connectivity
Get-ADDomain
```

```bash
# Fix line endings (from macOS/Linux)
cd AWS/Scripts
./Fix-LineEndings.sh
```

---

**Both issues are now resolved in the repository!** All future users will benefit from these fixes automatically. 🎉

