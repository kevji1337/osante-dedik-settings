# Security Hardening Guide

Detailed documentation of all security hardening measures applied to the server.

## Security Overview

This hardening setup follows industry best practices while maintaining practical usability for production workloads.

### Security Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Internet                              │
│                         │                                │
│                    Cloudflare                            │
│                    (WAF + DDoS)                          │
│                         │                                │
├─────────────────────────┼────────────────────────────────┤
│                    Ubuntu Server                         │
│                         │                                │
│  ┌──────────────────────┴──────────────────────┐        │
│  │           UFW Firewall                       │        │
│  │         (Ports 22, 80, 443)                  │        │
│  └──────────────────────┬──────────────────────┘        │
│                         │                                │
│  ┌──────────────────────┴──────────────────────┐        │
│  │           Fail2ban                           │        │
│  │        (Brute-force Protection)              │        │
│  └──────────────────────┬──────────────────────┘        │
│                         │                                │
│  ┌──────────────────────┴──────────────────────┐        │
│  │           SSH Hardening                      │        │
│  │         (Key-only Auth)                      │        │
│  └──────────────────────┬──────────────────────┘        │
│                         │                                │
│  ┌──────────────────────┴──────────────────────┐        │
│  │           Kernel Hardening                   │        │
│  │          (sysctl settings)                   │        │
│  └──────────────────────┬──────────────────────┘        │
│                         │                                │
│  ┌──────────────────────┴──────────────────────┐        │
│  │           Filesystem Security                │        │
│  │         (Permissions, umask)                 │        │
│  └──────────────────────┬──────────────────────┘        │
│                         │                                │
│  ┌──────────────────────┴──────────────────────┐        │
│  │           Docker Security                    │        │
│  │        (Container Isolation)                 │        │
│  └──────────────────────────────────────────────┘        │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## 1. SSH Hardening

### Configuration Applied

| Setting | Value | Purpose |
|---------|-------|---------|
| PermitRootLogin | no | Prevent direct root access |
| PasswordAuthentication | no | Require SSH keys only |
| PubkeyAuthentication | yes | Enable key-based auth |
| MaxAuthTries | 3 | Limit brute-force attempts |
| LoginGraceTime | 60s | Timeout for authentication |
| ClientAliveInterval | 300s | Keep-alive check |
| ClientAliveCountMax | 2 | Max missed keep-alives |
| X11Forwarding | no | Disable X11 (security) |
| AllowTcpForwarding | no | Prevent tunnel abuse |
| PermitTunnel | no | Disable tunneling |
| LogLevel | VERBOSE | Enhanced logging |

### SSH Key Requirements

```bash
# Generate secure key (recommended)
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519

# Or RSA with sufficient length
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

### Recovery Procedure

If locked out:

1. Access server via console (VPS provider's web interface)
2. Edit SSH config: `nano /etc/ssh/sshd_config`
3. Temporarily enable password auth or root login
4. Restart SSH: `systemctl restart ssh`
5. Fix your SSH keys
6. Re-apply hardening

## 2. Firewall (UFW)

### Default Policies

```bash
# Default incoming: DENY
# Default outgoing: ALLOW
# Default forward: DENY
```

### Allowed Ports

| Port | Protocol | Service | Notes |
|------|----------|---------|-------|
| 22 | TCP | SSH | Key-based only |
| 80 | TCP | HTTP | TLS certificates |
| 443 | TCP | HTTPS | Main traffic |

### Docker Compatibility

The `before.rules` file ensures Docker networking works:

```bash
# Allow Docker bridge traffic
-A ufw-before-input -i docker0 -j ACCEPT
-A ufw-before-output -o docker0 -j ACCEPT

# Allow established connections
-A ufw-before-input -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

### Useful Commands

```bash
# Check status
ufw status verbose

# View numbered rules
ufw status numbered

# Add rule
ufw allow 8080/tcp comment 'Custom service'

# Remove rule
ufw delete allow 8080/tcp

# Disable (emergency)
ufw --force disable
```

## 3. Fail2ban Protection

### Active Jails

| Jail | Max Retry | Ban Time | Filter |
|------|-----------|----------|--------|
| sshd | 5 | 1 hour | sshd |
| sshd-recidive | 3 | 24 hours | sshd-recidive |

### Configuration Files

- Main config: `/etc/fail2ban/jail.local`
- Logs: `/var/log/fail2ban.log`
- Socket: `/var/run/fail2ban/fail2ban.sock`

### Useful Commands

```bash
# Check status
fail2ban-client status

# Check SSH jail
fail2ban-client status sshd

# Unban IP
fail2ban-client set sshd unbanip 192.168.1.100

# Unban all
fail2ban-client reload --unban --all

# View logs
tail -f /var/log/fail2ban.log
```

### Custom Filter Example

For Caddy access logs (`/etc/fail2ban/filter.d/caddy.conf`):

```ini
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*(/admin|/wp-|/\.env).*" 404
ignoreregex =
```

## 4. Kernel Hardening (sysctl)

### Network Security

| Parameter | Value | Purpose |
|-----------|-------|---------|
| net.ipv4.ip_forward | 1 | Required for Docker |
| net.ipv4.tcp_syncookies | 1 | SYN flood protection |
| net.ipv4.conf.all.accept_redirects | 0 | Prevent redirect attacks |
| net.ipv4.conf.all.send_redirects | 0 | Don't send redirects |
| net.ipv4.conf.all.rp_filter | 1 | Reverse path filtering |
| net.ipv4.conf.all.log_martians | 1 | Log invalid packets |
| net.ipv4.conf.all.accept_source_route | 0 | No source routing |

### Filesystem Protection

| Parameter | Value | Purpose |
|-----------|-------|---------|
| fs.protected_hardlinks | 2 | Hardlink protection |
| fs.protected_symlinks | 2 | Symlink protection |
| kernel.dmesg_restrict | 1 | Hide kernel messages |
| kernel.kptr_restrict | 2 | Hide kernel pointers |

### Memory Protection

| Parameter | Value | Purpose |
|-----------|-------|---------|
| kernel.randomize_va_space | 2 | Full ASLR |
| kernel.yama.ptrace_scope | 1 | Restrict ptrace |
| fs.suid_dumpable | 0 | No core dumps |

### Apply Settings

```bash
# Apply all
sysctl -p /etc/sysctl.d/99-hardening.conf

# Check specific setting
sysctl net.ipv4.tcp_syncookies

# View all applied
sysctl -a | grep -E '^(net|kernel|fs)\.'
```

## 5. Filesystem Security

### Umask Configuration

```bash
# Default umask: 027
# Files: 640 (rw-r-----)
# Directories: 750 (rwxr-x---)
```

### Critical File Permissions

| File/Directory | Expected | Purpose |
|----------------|----------|---------|
| /etc/passwd | 644 | User database |
| /etc/shadow | 640/600 | Password hashes |
| /etc/group | 644 | Group database |
| /etc/ssh/sshd_config | 600 | SSH config |
| /root | 700 | Root home |

### World-Writable File Check

```bash
# Find world-writable files
find / -type f -perm -0002 -not -path "/proc/*" 2>/dev/null

# Find world-writable directories without sticky bit
find / -type d -perm -0002 -not -path "/proc/*" 2>/dev/null
```

### SUID/SGID Audit

```bash
# Find SUID files
find / -type f -perm -4000 -not -path "/proc/*" 2>/dev/null

# Find SGID files
find / -type f -perm -2000 -not -path "/proc/*" 2>/dev/null
```

## 6. Logging & Auditing

### Configured Services

| Service | Purpose | Log Location |
|---------|---------|--------------|
| auditd | Security auditing | /var/log/audit/ |
| rsyslog | System logging | /var/log/ |
| journald | Journal logging | journalctl |
| logrotate | Log rotation | /etc/logrotate.d/ |

### Audit Rules

Key monitored events:

- Time changes
- Identity files (/etc/passwd, /etc/shadow)
- Sudo usage
- SSH configuration changes
- Docker socket access
- Network configuration changes

### Useful Commands

```bash
# View audit logs
ausearch -m USER_AUTH -ts today

# Search by key
ausearch -k sshd -ts today

# Generate report
aureport --summary

# View journal
journalctl -f

# View auth logs
tail -f /var/log/auth.log
```

### Log Retention

| Log Type | Rotation | Retention |
|----------|----------|-----------|
| Audit logs | Daily | 90 days |
| Auth logs | Weekly | 12 weeks |
| Application logs | Daily | 30 days |
| Backup logs | Daily | 30 days |

## 7. Docker Security

### Daemon Configuration

```json
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "userns-remap": "default",
    "live-restore": true
}
```

### Security Features

| Feature | Status | Description |
|---------|--------|-------------|
| User namespace | Enabled | Container root ≠ Host root |
| Log rotation | Enabled | 10MB × 3 files |
| Live restore | Enabled | Containers survive daemon restart |
| Socket permissions | 660 | root:docker only |

### Best Practices

1. **Don't run as root inside containers**
   ```dockerfile
   USER appuser
   ```

2. **Use read-only filesystem where possible**
   ```yaml
   read_only: true
   tmpfs:
     - /tmp
   ```

3. **Limit capabilities**
   ```yaml
   cap_drop:
     - ALL
   cap_add:
     - NET_BIND_SERVICE
   ```

4. **Use secrets for sensitive data**
   ```yaml
   secrets:
     - db_password
   ```

## 8. PostgreSQL Security

### Container Security

```yaml
services:
  postgres:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD_FILE=/run/secrets/db_password
    secrets:
      - db_password
    networks:
      - internal-network  # Not exposed publicly
    volumes:
      - pg_data:/var/lib/postgresql/data
```

### Network Security

- Port 5432 NOT exposed to host
- Only accessible via Docker internal network
- Applications connect via Docker network

### Backup Security

- Encrypted with Restic (AES-256)
- Stored offsite (Cloudflare R2)
- Retention: 7 daily, 4 weekly, 12 monthly

## 9. Security Validation

### Automated Checks

Run the validation script:

```bash
./scripts/validate-security.sh
```

### Manual Checklist

**SSH:**
- [ ] Root login disabled
- [ ] Password auth disabled
- [ ] Key-based auth working
- [ ] SSH config valid (sshd -t)

**Firewall:**
- [ ] UFW active
- [ ] Only required ports open
- [ ] Default deny incoming

**Fail2ban:**
- [ ] Service running
- [ ] SSH jail active
- [ ] No false positives

**Kernel:**
- [ ] IP forwarding enabled (for Docker)
- [ ] SYN cookies enabled
- [ ] ICMP redirects disabled
- [ ] ASLR enabled

**Filesystem:**
- [ ] No unexpected world-writable files
- [ ] Critical files have correct permissions
- [ ] Docker socket protected

**Logging:**
- [ ] Auditd running
- [ ] Logs being rotated
- [ ] Sudo logging enabled

## 10. Security Updates

### Automatic Updates

Configured via `unattended-upgrades`:

- Security updates: Automatic
- Other updates: Manual review
- Reboot: Manual (scheduled maintenance)

### Manual Update Process

```bash
# Check available updates
apt-get update
apt-get upgrade --dry-run

# Install updates
apt-get upgrade

# Review changelogs
apt-listchanges changes

# Reboot if kernel updated
systemctl reboot
```

### Monitoring for Vulnerabilities

```bash
# Check for known vulnerabilities
debsums -s

# Review installed packages
dpkg -l | grep -v '^ii'
```

## 11. Incident Response

### SSH Brute Force Detected

```bash
# Check fail2ban bans
fail2ban-client status sshd

# View banned IPs
fail2ban-client get sshd banned

# Check auth logs
grep "Failed password" /var/log/auth.log | tail -20

# If needed, change SSH port temporarily
# Edit /etc/ssh/sshd_config, add: Port 2222
```

### Suspicious Activity

```bash
# Check current connections
ss -tlnp

# Check logged in users
who
last

# Check recent commands (if auditd enabled)
ausearch -ts today

# Check for unusual processes
ps auxf | head -50
```

### Recovery Mode

1. Access via console (VPS provider)
2. Review logs: `/var/log/auth.log`, `/var/log/audit/`
3. Check for unauthorized users: `cat /etc/passwd`
4. Check for unauthorized SSH keys: `cat /root/.ssh/authorized_keys`
5. Review cron jobs: `crontab -l`, `ls /etc/cron.*`

## 12. Compliance Notes

This hardening setup addresses requirements from:

- **CIS Ubuntu Benchmark** - Partial alignment
- **NIST 800-53** - Access Control, Audit & Accountability
- **PCI DSS** - Basic host security requirements

### Key Controls Implemented

| Control | Implementation |
|---------|----------------|
| AC-2 Account Management | Admin user with sudo |
| AC-3 Access Enforcement | File permissions, UFW |
| AC-6 Least Privilege | Sudo, no root SSH |
| AU-2 Auditable Events | Auditd rules |
| AU-3 Content of Audit | Timestamps, users, actions |
| IA-2 Identification | SSH key authentication |
| IA-5 Authenticators | Key-only, no passwords |
| SC-7 Boundary Protection | UFW firewall |
| SI-4 Information Monitoring | Fail2ban, auditd |

## Quick Reference

```bash
# Security validation
./scripts/validate-security.sh

# Check SSH config
sshd -t

# Check firewall
ufw status verbose

# Check fail2ban
fail2ban-client status

# Check kernel params
sysctl -a | grep -E '^(net|kernel|fs)\.'

# Check world-writable
find / -type f -perm -0002 2>/dev/null | wc -l

# Check audit status
systemctl status auditd

# View security logs
tail -f /var/log/auth.log
```

---

**Security is a process, not a product!**

Regular activities:
- Run validation script weekly
- Review logs daily (automated alerts)
- Update system monthly
- Review and tune thresholds quarterly
- Full security audit annually
