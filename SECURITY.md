```markdown
# 🔒 Security Policy

## Supported Versions

We take security seriously. Security updates and vulnerability patches are provided for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

### Private Reporting Process

Instead, please report them via email to:

📧 **security@termux-vault.dev**

Include the following in your report:

1. **Description of the vulnerability**
   - Type of issue (e.g., buffer overflow, privilege escalation, data exposure)
   - Impact and potential exploit scenarios

2. **Steps to reproduce**
   - Minimal code or commands to trigger the vulnerability
   - Environment details (Termux version, Android version, device)

3. **Proof of concept**
   - Screenshots, logs, or code snippets
   - Any relevant error messages

4. **Suggested fix** (optional)
   - Proposed patch or mitigation strategy

### Response Timeline

| Phase | Timeframe |
|-------|-----------|
| Initial acknowledgment | Within 24 hours |
| Confirmation of vulnerability | Within 72 hours |
| Security patch release | Within 7 days (critical), 14 days (high), 30 days (medium) |
| Public disclosure | After patch is released and users have had time to update |

---

## Security Best Practices for Users

### 🔐 File Permissions

The system automatically manages permissions, but verify:

```bash
# Check that sensitive files are not world-readable
ls -la ~/termux-backup/vault/backups/
ls -la ~/termux-backup/config/backup.conf

# Recommended permissions
chmod 700 ~/termux-backup/vault/backups
chmod 600 ~/termux-backup/config/backup.conf
chmod 600 ~/termux-backup/vault/backup.log
```

🔑 SSH Key Protection

Backups include SSH keys. After restore, immediately verify:

```bash
# Ensure proper SSH permissions
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub
chmod 600 ~/.ssh/authorized_keys
```

📦 Checksum Verification

Always verify backup integrity before restore:

```bash
# Verify backup integrity
./termux-backup verify <backup-name>

# Manual checksum verification
sha256sum -c vault/meta/<backup-name>/checksum.sha256
```

🔄 Regular Updates

Keep the system updated:

```bash
# Update Termux Vault
git pull origin main
bash install.sh

# Verify installation
./termux-backup --help
```

---

Security Features

✅ Cryptographic Integrity

· SHA256 checksums generated for every backup
· Pre-restore verification prevents corrupted data restoration
· Manifest validation ensures metadata integrity

✅ Atomic Operations

· No partial backups - Operations complete fully or not at all
· Safety snapshots created before any destructive operation
· Transaction-like behavior prevents system inconsistency

✅ Data Protection

· Self-contained storage - No data leaves the device
· No external dependencies - Reduced attack surface
· No network access required - Air-gapped operation possible
· Compression with verification - zstd with integrity checks

✅ Access Control

· No root required - Runs with standard user permissions
· File permission preservation - Maintains original security context
· Exclusion patterns - Configurable sensitive data filtering

---

Vulnerability Disclosure Policy

Our Commitment

1. Prompt Response: We will acknowledge receipt of your report within 24 hours
2. Transparency: We will keep you informed of our progress
3. Credit: We will publicly acknowledge your contribution (unless you prefer anonymity)
4. Safe Harbor: We will not pursue legal action against security researchers who act in good faith

Disclosure Timeline

```
Day 0:    Vulnerability reported
Day 1:    Initial acknowledgment
Day 3:    Confirmation and severity assessment
Day 7:    Critical patch development begins
Day 14:   Patch released for critical vulnerabilities
Day 30:   Public disclosure (CVE requested if applicable)
```

Severity Classification

Severity Examples Response Time
Critical Data loss, privilege escalation, remote code execution 7 days
High Information disclosure, integrity violation 14 days
Medium Denial of service, configuration weakness 30 days
Low Cosmetic issues, documentation errors Next release

---

Secure Development Practices

Code Standards

· Strict error handling: set -Eeuo pipefail in all scripts
· Input validation: All user inputs are sanitized
· Path traversal prevention: No dynamic path construction from user input
· Shell injection prevention: Parameterized commands, no eval

Testing Requirements

```bash
# Run security tests before deployment
cd ~/termux-backup

# 1. Check for hardcoded paths
grep -r "/data/data/com.termux" --include="*.sh" | grep -v "^#"

# 2. Check for world-writable files
find . -type f -perm -o+w

# 3. Check for SUID/SGID files
find . -type f -perm /6000

# 4. Verify checksums of all scripts
sha256sum termux-backup termux-restore lib/*.sh config/*.conf
```

---

Third-Party Dependencies

Termux Vault has zero external dependencies by design:

Component Built-in Notes
bash ✅ Termux default shell
tar ✅ Pre-installed in Termux
zstd ❌ Required: pkg install zstd
sha256sum ✅ Part of coreutils
dpkg ✅ Termux package manager
apt ✅ Termux package manager

Install missing dependency:

```bash
pkg install zstd
```

---

Secure Configuration Template

config/backup.conf - Security Hardened

```bash
# ============================================================
# SECURITY SETTINGS
# ============================================================

# Always verify integrity (DO NOT DISABLE)
SHA256_VALIDATE=true

# Create safety snapshot before restore (DO NOT DISABLE)
PRE_RESTORE_SNAPSHOT=true

# Minimum free space (prevents system crash)
MIN_FREE_SPACE_MB=512

# ============================================================
# SENSITIVE DATA PROTECTION
# ============================================================

# Exclude sensitive files from backup
EXCLUDE_PATTERNS=(
    ".cache"
    "tmp"
    ".bash_history"        # Command history
    ".python_history"      # Python history
    ".node_repl_history"   # Node.js history
    ".lesshst"             # Less history
)

# ============================================================
# RETENTION (limits exposure window)
# ============================================================
MAX_BACKUPS=7              # Keep only recent backups
MAX_SNAPSHOT_AGE_DAYS=14   # Remove old snapshots faster
```

---

Incident Response

If You Suspect a Breach

1. Isolate the system
   ```bash
   # Disable network (if applicable)
   termux-wifi-enable false
   ```
2. Create forensic backup
   ```bash
   # Backup current state for analysis
   tar -czf forensic-$(date +%Y%m%d-%H%M%S).tar.gz ~/termux-backup/vault/
   ```
3. Verify last known good backup
   ```bash
   # Check which backups pass integrity verification
   ./termux-backup list
   ./termux-backup verify <latest-backup>
   ```
4. Restore from clean backup
   ```bash
   # Restore from verified backup
   ./termux-restore restore <last-known-good-backup>
   ```
5. Contact us
   ```bash
   # Send forensic data (encrypted)
   gpg --encrypt --recipient security@termux-vault.dev forensic-*.tar.gz
   ```

---

Security Audits

Self-Audit Checklist

Run these checks monthly:

```bash
#!/bin/bash
# security-audit.sh - Monthly security audit

echo "=== Termux Vault Security Audit ==="
echo "Date: $(date)"
echo ""

# 1. Check file permissions
echo "[1/6] Checking file permissions..."
find ~/termux-backup -type f -name "*.sh" -exec ls -la {} \;

# 2. Verify no world-readable sensitive files
echo "[2/6] Checking for world-readable sensitive files..."
find ~/termux-backup/vault -type f -perm -004

# 3. Check for modified scripts
echo "[3/6] Verifying script integrity..."
md5sum ~/termux-backup/termux-backup ~/termux-backup/termux-restore

# 4. Check backup integrity
echo "[4/6] Verifying backup integrity..."
for backup in ~/termux-backup/vault/backups/*.tar.zst; do
    [[ "$backup" == *"-prefix.tar.zst" ]] && continue
    name=$(basename "$backup" .tar.zst)
    ~/termux-backup/termux-backup verify "$name" 2>&1 | grep -E "(✓|✗|FAILED)"
done

# 5. Check for suspicious processes
echo "[5/6] Checking for suspicious processes..."
ps aux | grep -E "(nc|netcat|reverse|bind)" | grep -v grep

# 6. Review recent logs
echo "[6/6] Reviewing recent log entries..."
grep -E "(ERROR|WARN|FAILED)" ~/termux-backup/vault/backup.log | tail -20

echo ""
echo "=== Audit Complete ==="
```

---

Compliance

Data Protection

· GDPR: All data remains on-device, no external transmission
· HIPAA: No PHI collection or transmission (suitable for development environments)
· PCI-DSS: No payment data processing

Encryption Standards

Feature Algorithm Key Size
Integrity SHA-256 256-bit
Compression Zstandard N/A (lossless)
Archive GNU tar N/A

---

Contact

· Security Issues: security@termux-vault.dev
· General Questions: Open a GitHub Issue
· Responsible Disclosure: See Reporting Process

---

Acknowledgments

We thank the following for their security contributions:

· The Termux development team
· The Bash security community
· All security researchers who responsibly disclose vulnerabilities

---

Changelog

Date Version Changes
2026-01-28 1.0.0 Initial security policy
- - -

---

<div align="center">

🔒 Security is not an afterthought. It's built into every line of code.

Report responsibly. Protect diligently. Backup religiously.

</div>
```

---

📋 How to Use This File

1. Save as SECURITY.md in your repository root
2. GitHub automatically detects and displays it in the Security tab
3. Update contact email to your actual security contact
4. Add to .github/SECURITY.md for organization-level policy (optional)

Quick Setup

```bash
# In your repository
cat > SECURITY.md << 'EOF'
[paste the content above]
EOF

# Commit and push
git add SECURITY.md
git commit -m "Add security policy"
git push origin main
```

This will appear at: https://github.com/erfan1994/termux-backup/security/policy
