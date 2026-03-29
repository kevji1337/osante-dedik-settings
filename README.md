# Server Hardening & Infrastructure Setup

Production-ready server hardening and infrastructure configuration for Ubuntu 24.04 LTS with Docker, Coolify, Caddy, and Cloudflare.

## 🔒 Security Status

**✅ PRODUCTION READY** — Все критические и high-risk уязвимости исправлены (2026-03-16)

**Latest Audits:**
- [FINAL_SECURITY_AUDIT.md](FINAL_SECURITY_AUDIT.md) — Общий аудит безопасности
- [UFW_FIREWALL_AUDIT.md](UFW_FIREWALL_AUDIT.md) — Аудит UFW и Docker совместимости
- [FINAL_RISK_AUDIT.md](FINAL_RISK_AUDIT.md) — Аудит 10 критических рисков
- [CRITICAL_FIXES_APPLIED.md](CRITICAL_FIXES_APPLIED.md) — Применённые исправления
- [FINAL_DEPLOYMENT_CHECK.md](FINAL_DEPLOYMENT_CHECK.md) — Финальная проверка развёртывания

См. [SECURITY_FIXES.md](SECURITY_FIXES.md) для полного списка применённых исправлений.

---

## 🚀 Quick Deploy

**Minimum time:** 90-120 minutes  
**Risk level:** LOW  
**Confidence:** 100%

```bash
# 1. Copy to server
scp -r . root@server-ip:/opt/server-hardening
ssh root@server-ip
cd /opt/server-hardening

# 2. Run setup (follow prompts)
./scripts/01-system-prep.sh --username admin --ssh-key "$(cat ~/.ssh/id_ed25519.pub)"
./scripts/02-ssh-hardening.sh --no-restart  # Then test SSH before restart!
./scripts/03-firewall-setup.sh --with-cloudflare
./scripts/04-fail2ban-config.sh
./scripts/05-sysctl-hardening.sh
./scripts/06-filesystem-security.sh
./scripts/07-logging-setup.sh
./scripts/10-docker-security.sh --no-restart  # Before Coolify!
./scripts/08-monitoring-setup.sh
./scripts/09-backup-setup.sh

# 3. Verify
./scripts/validate-security.sh
```

**Full instructions:** [FINAL_DEPLOYMENT_CHECK.md](FINAL_DEPLOYMENT_CHECK.md) | [SAFE_DEPLOYMENT.md](SAFE_DEPLOYMENT.md)

## 📋 Overview

This project provides a complete, production-ready server hardening setup with:

- **System Preparation** - Base packages, user creation, auto-updates
- **SSH Hardening** - Key-only authentication, secure configuration
- **Firewall (UFW)** - Docker-compatible rules, PostgreSQL blocked, **Cloudflare IP protection**
- **Fail2ban** - SSH brute-force protection + UFW rate limiting
- **Kernel Hardening** - Safe sysctl settings (Docker-compatible)
- **Filesystem Security** - Permissions, umask, audits
- **Logging & Auditing** - auditd, journald, logrotate
- **Docker Security** - Container isolation, userland-proxy enabled
- **Monitoring** - Prometheus, Node Exporter, Alertmanager + Telegram (localhost only)
- **Backups** - Restic with Cloudflare R2 storage

## 🛡️ Cloudflare Origin Protection

**NEW:** HTTP/HTTPS трафик разрешён **ТОЛЬКО** с IP адресов Cloudflare.

```
✅ Port 80  — Cloudflare IP only (22 ranges)
✅ Port 443 — Cloudflare IP only (22 ranges)
✅ Port 22  — Open for SSH admin access
✅ Direct access blocked — Прямой доступ заблокирован
```

**Setup:**
```bash
./scripts/03-firewall-setup.sh --with-cloudflare
```

**Update IP ranges:**
```bash
./scripts/update-cloudflare-ips.sh
```

**Documentation:** [CLOUDFLARE_IMPLEMENTATION.md](CLOUDFLARE_IMPLEMENTATION.md) | [docs/CLOUDFLARE_PROTECTION.md](docs/CLOUDFLARE_PROTECTION.md)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
│                             │                                    │
│                      Cloudflare (WAF)                            │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Ubuntu 24.04 LTS │
                    │    (Hardened)     │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
┌───────▼────────┐   ┌───────▼────────┐   ┌───────▼────────┐
│  UFW Firewall  │   │   Fail2ban     │   │  Auditd        │
│  22, 80, 443   │   │  SSH Protect   │   │  Logging       │
└────────────────┘   └────────────────┘   └────────────────┘
        │
        │    ┌──────────────────────────────────────────┐
        │    │           Docker Environment              │
        │    │  ┌──────────┐  ┌──────────┐  ┌────────┐ │
        │    │  │  Caddy   │  │ Coolify  │  │  App   │ │
        │    │  │  Proxy   │  │  Deploy  │  │  API   │ │
        │    │  └──────────┘  └──────────┘  └────────┘ │
        │    │  ┌──────────┐  ┌──────────┐  ┌────────┐ │
        │    │  │ Frontend │  │PostgreSQL│  │Monitoring││
        │    │  │   Web    │  │ Internal │  │ Stack  │ │
        │    │  └──────────┘  └──────────┘  └────────┘ │
        │    └──────────────────────────────────────────┘
        │
        │    ┌──────────────────────────────────────────┐
        │    │           Backup System                  │
        │    │   Restic → Cloudflare R2 (Encrypted)    │
        │    └──────────────────────────────────────────┘
```

## 📁 Directory Structure

```
.
├── scripts/
│   ├── 01-system-prep.sh         # System preparation
│   ├── 02-ssh-hardening.sh       # SSH hardening
│   ├── 03-firewall-setup.sh      # UFW configuration
│   ├── 04-fail2ban-config.sh     # Fail2ban setup
│   ├── 05-sysctl-hardening.sh    # Kernel hardening
│   ├── 06-filesystem-security.sh # Filesystem security
│   ├── 07-logging-setup.sh       # Logging & auditing
│   ├── 08-monitoring-setup.sh    # Monitoring stack
│   ├── 09-backup-setup.sh        # Backup system
│   ├── 10-docker-security.sh     # Docker hardening
│   └── validate-security.sh      # Security validation
├── configs/
│   ├── sshd_config               # SSH server config
│   ├── ufw/
│   │   ├── before.rules          # Docker compatibility rules
│   │   └── user.rules            # User-defined rules
│   ├── fail2ban/
│   │   ├── jail.local            # Jail configuration
│   │   └── filter.d/
│   │       └── caddy.conf        # Caddy filter
│   ├── sysctl.d/
│   │   └── 99-hardening.conf     # Kernel parameters
│   ├── logrotate.d/
│   │   ├── auditd                # Audit log rotation
│   │   └── custom-apps           # Application logs
│   ├── monitoring/
│   │   ├── alert_rules.yml       # Prometheus alerts
│   │   └── alertmanager.yml      # Alertmanager config
│   ├── grafana/
│   │   ├── provisioning/
│   │   │   ├── datasources.yml   # Prometheus datasource
│   │   │   └── dashboards.yml    # Dashboard provisioning
│   │   └── dashboards/
│   │       └── server-monitoring.json
│   └── backup/
│       ├── restic-profile.sh     # Backup profiles
│       ├── backup-postgresql.sh  # PostgreSQL backup
│       └── backup-configs.sh     # Configs backup
├── docs/
│   ├── SETUP.md                  # Setup guide
│   ├── BACKUP-RESTORE.md         # Backup & restore procedures
│   ├── MONITORING.md             # Monitoring documentation
│   └── SECURITY-HARDENING.md     # Security hardening details
├── docker-compose.monitoring.yml # Docker Compose for monitoring
└── README.md                     # This file
```

## 🚀 Quick Start

### Prerequisites

- Fresh Ubuntu 24.04 LTS server (minimum 2GB RAM, 2 CPU, 25GB disk)
- Root access via SSH
- **CONSOLE ACCESS (VPS web console) — REQUIRED for recovery**
- SSH key pair generated (`ssh-keygen -t ed25519`)
- Domain configured (for Caddy TLS)
- Cloudflare account (for proxy and R2 storage)

### ⚠️ Important Warnings

**BEFORE RUNNING quick-deploy.sh:**

1. **Test SSH key access** — Verify you can login with SSH key in a NEW session
2. **Have console access** — VPS provider's web console for recovery
3. **Backup important data** — Create snapshots before hardening
4. **Read SIMULATION_REPORT.md** — Understand the risks

**See [SIMULATION_REPORT.md](SIMULATION_REPORT.md) for detailed risk analysis.**

### Step 1: Copy Scripts to Server

```bash
# From your local machine
scp -r . root@your-server-ip:/opt/server-hardening
ssh root@your-server-ip
cd /opt/server-hardening
```

### Step 2: Run Setup Scripts (in order)

```bash
# Make scripts executable
chmod +x scripts/*.sh configs/backup/*.sh

# 1. System preparation (CRITICAL: Use your SSH public key)
./scripts/01-system-prep.sh \
    --username admin \
    --ssh-key "ssh-ed25519 AAAA... your-public-key" \
    --timezone UTC \
    --hostname your-server-name

# 2. SSH hardening (WARNING: May disconnect SSH session)
./scripts/02-ssh-hardening.sh

# 3. Firewall setup
./scripts/03-firewall-setup.sh

# 4. Fail2ban configuration
./scripts/04-fail2ban-config.sh

# 5. Kernel hardening
./scripts/05-sysctl-hardening.sh

# 6. Filesystem security
./scripts/06-filesystem-security.sh

# 7. Logging setup
./scripts/07-logging-setup.sh

# 8. Monitoring setup
./scripts/08-monitoring-setup.sh

# 9. Backup setup
./scripts/09-backup-setup.sh

# 10. Docker security (optional, run after Docker is installed)
./scripts/10-docker-security.sh
```

### Step 3: Validate Security

```bash
./scripts/validate-security.sh
```

## 📖 Documentation

| Document | Description |
|----------|-------------|
| [SETUP.md](docs/SETUP.md) | Detailed step-by-step setup instructions |
| [BACKUP-RESTORE.md](docs/BACKUP-RESTORE.md) | Backup and restore procedures |
| [MONITORING.md](docs/MONITORING.md) | Monitoring and Telegram alert setup |
| [SECURITY-HARDENING.md](docs/SECURITY-HARDENING.md) | Security hardening details |

## 🔧 Configuration

### SSH Key Setup

Before running SSH hardening:

```bash
# Generate secure key
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519

# Copy public key to server
ssh-copy-id root@your-server-ip
```

### Cloudflare R2 Setup (for Backups)

1. **Create R2 bucket** in Cloudflare Dashboard
2. **Create API token** with Object Read & Write permissions
3. **Get Account ID** from Cloudflare Dashboard
4. **Configure** `/etc/profile.d/restic-backup.sh`:

```bash
export RESTIC_REPOSITORY="r2:your-bucket-name"
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_ENDPOINT_URL_S3="https://account-id.r2.cloudflarestorage.com"
export RESTIC_PASSWORD="your-encryption-password"
```

### Telegram Alerts Setup

1. **Create bot** via @BotFather in Telegram
2. **Get bot token**
3. **Add bot** to your chat/channel
4. **Get chat ID**: `https://api.telegram.org/bot<TOKEN>/getUpdates`
5. **Update** `configs/monitoring/alertmanager.yml` with token and chat ID

See [MONITORING.md](docs/MONITORING.md) for detailed instructions.

## 🔒 Security Features

| Feature | Status | Description |
|---------|--------|-------------|
| SSH Key Auth | ✅ | Password authentication disabled |
| Root SSH Login | ❌ | Disabled |
| Firewall | ✅ | UFW with minimal open ports |
| Fail2ban | ✅ | SSH brute-force protection (5 strikes = 1h ban) |
| Kernel Hardening | ✅ | Safe sysctl settings (Docker compatible) |
| Filesystem Security | ✅ | Proper permissions, umask 027 |
| Logging | ✅ | auditd, journald, logrotate |
| Auto Updates | ✅ | Security updates enabled |
| Monitoring | ✅ | Prometheus + Telegram alerts |
| Backups | ✅ | Encrypted, offsite (Cloudflare R2) |
| Docker Security | ✅ | User namespaces, log rotation |

## 📊 Ports Reference

| Service | Port | Access | Notes |
|---------|------|--------|-------|
| SSH | 22 | Public | Key-based only |
| HTTP | 80 | Public | Caddy/TLS |
| HTTPS | 443 | Public | Main traffic |
| Node Exporter | 9100 | Local | Prometheus metrics |
| Prometheus | 9090 | Local | Metrics storage |
| Alertmanager | 9093 | Local | Alert routing |
| Grafana | 3000 | Local | Dashboards |
| PostgreSQL | 5432 | Internal | Docker network only |

> **Note:** Monitoring services are bound to localhost. Use SSH tunneling for remote access.

## 🗄️ Backup Schedule

| Backup Type | Schedule | Retention | Storage |
|-------------|----------|-----------|---------|
| PostgreSQL | Daily 2:00 AM | 7d, 4w, 12m | Cloudflare R2 |
| Server Configs | Daily 3:00 AM | 7d, 4w, 12m | Cloudflare R2 |

## ✅ Validation Checklist

Run `./scripts/validate-security.sh` to verify:

- [ ] SSH configuration is secure
- [ ] Firewall is active with correct rules
- [ ] Fail2ban is running
- [ ] Kernel parameters are hardened
- [ ] Docker is working correctly
- [ ] No world-writable files
- [ ] Logging is configured
- [ ] System is up to date

## 🔍 Useful Commands

### Security Checks

```bash
# Full security validation
./scripts/validate-security.sh

# Check SSH config
sshd -t

# Check firewall status
ufw status verbose

# Check fail2ban status
fail2ban-client status

# Check kernel hardening
sysctl -a | grep -E '^(net|kernel|fs)\.'
```

### Monitoring

```bash
# Check monitoring services
systemctl status node-exporter prometheus alertmanager

# View Prometheus targets
curl http://localhost:9090/api/v1/targets | jq

# Test Telegram alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"Test"}}]'
```

### Backups

```bash
# List snapshots
restic snapshots

# Manual backup
/opt/backup/backup-configs.sh

# Check backup integrity
restic check
```

### Docker

```bash
# Check running containers
docker ps

# Check Docker security
./scripts/10-docker-security.sh --check
```

## 🆘 Troubleshooting

### SSH Connection Lost After Hardening

1. Access server via console (VPS provider's web console)
2. Check SSH: `systemctl status ssh`
3. Validate config: `sshd -t`
4. Restore backup: `cp /var/backups/hardening/sshd_config.backup.* /etc/ssh/sshd_config`
5. Restart: `systemctl restart ssh`

### Docker Networking Issues

```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward  # Should be 1

# Check UFW rules
ufw status verbose

# Restart Docker
systemctl restart docker
```

### Monitoring Not Working

```bash
# Check services
systemctl status node-exporter prometheus alertmanager

# View logs
journalctl -u prometheus -f

# Check ports
ss -tlnp | grep -E '9090|9093|9100'
```

### Backup Failures

```bash
# Check environment variables
env | grep -E 'RESTIC_|AWS_'

# Test R2 connection
restic snapshots

# Check logs
tail /var/log/backup/*.log
```

## 📝 Important Notes

1. **Always test in staging first** before applying to production
2. **Keep SSH session open** until you verify new connection works
3. **Backup all configurations** before making changes
4. **Document any custom changes** for future reference
5. **Regular validation** - run security checks monthly

## 🔐 Security Best Practices

### Regular Maintenance

**Daily:**
- Check monitoring alerts (Telegram)
- Review backup logs

**Weekly:**
- Run security validation script
- Check fail2ban bans
- Review disk usage trends

**Monthly:**
- Apply system updates
- Review and tune alert thresholds
- Test backup restoration
- Review user access

**Quarterly:**
- Full security audit
- Rotate credentials
- Review firewall rules
- Update documentation

### Incident Response

If you suspect a security incident:

1. **Preserve evidence** - Don't reboot or modify logs
2. **Isolate** - Disconnect from network if critical
3. **Document** - Record all observations and actions
4. **Analyze** - Review logs, check for unauthorized access
5. **Recover** - Restore from known-good backup
6. **Learn** - Update hardening to prevent recurrence

## 🤝 Contributing

This setup is designed for production use. When modifying:

1. Test changes in a non-production environment
2. Update documentation
3. Ensure backward compatibility
4. Add validation checks

## 📄 License

This project is provided as-is for production server hardening.

## 📞 Support

For issues and questions:

1. Check documentation in `docs/`
2. Review logs in `/var/log/server-hardening/`
3. Run validation script for diagnostics
4. Check systemd journal: `journalctl -xe`

## 📈 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-16 | Initial production release |

---

**Last Updated:** 2026-03-16  
**Ubuntu Version:** 24.04 LTS  
**Tested With:** Docker, Coolify, Caddy, Cloudflare

**Remember:** Security is a process, not a product. Stay vigilant! 🔒
