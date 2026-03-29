# Server Hardening Cheatsheet

Quick reference for common operations and troubleshooting.

## Setup Commands

### Initial Deployment

```bash
# Copy to server
scp -r . root@server-ip:/opt/server-hardening
cd /opt/server-hardening
chmod +x scripts/*.sh configs/backup/*.sh

# Quick deploy (all-in-one)
./scripts/quick-deploy.sh \
  --username admin \
  --ssh-key "ssh-ed25519 AAAA..." \
  --timezone UTC \
  --yes
```

### Individual Scripts

```bash
# System prep
./scripts/01-system-prep.sh --username admin --ssh-key "key"

# SSH hardening
./scripts/02-ssh-hardening.sh

# Firewall
./scripts/03-firewall-setup.sh

# Fail2ban
./scripts/04-fail2ban-config.sh

# Kernel hardening
./scripts/05-sysctl-hardening.sh

# Filesystem
./scripts/06-filesystem-security.sh

# Logging
./scripts/07-logging-setup.sh

# Monitoring
./scripts/08-monitoring-setup.sh

# Backup
./scripts/09-backup-setup.sh

# Docker security
./scripts/10-docker-security.sh
```

## Status Checks

### Quick Health Check

```bash
# All services
systemctl status ssh docker ufw fail2ban auditd prometheus alertmanager node-exporter

# Security validation
./scripts/validate-security.sh

# Generate report
./scripts/security-report.sh
```

### SSH

```bash
# Test config
sshd -t

# Check status
systemctl status ssh

# View logs
journalctl -u ssh -f

# Active connections
ss -tlnp | grep :22
who
```

### Firewall

```bash
# Status
ufw status verbose

# Numbered rules
ufw status numbered

# Allow port
ufw allow 8080/tcp comment 'My service'

# Remove rule
ufw delete allow 8080/tcp

# Logs
tail -f /var/log/ufw.log
```

### Fail2ban

```bash
# Status
fail2ban-client status

# SSH jail
fail2ban-client status sshd

# Unban IP
fail2ban-client set sshd unbanip 192.168.1.100

# Unban all
fail2ban-client reload --unban --all

# Logs
tail -f /var/log/fail2ban.log
```

### Docker

```bash
# Running containers
docker ps

# Docker logs
docker logs container-name

# Socket permissions
stat /var/run/docker.sock

# Network list
docker network ls
```

### Monitoring

```bash
# Check services
systemctl status node-exporter prometheus alertmanager

# Prometheus targets
curl http://localhost:9090/api/v1/targets | jq

# Test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"Test"}}]'

# Grafana access
ssh -L 3000:localhost:3000 admin@server-ip
# Open: http://localhost:3000
```

### Backups

```bash
# List snapshots
restic snapshots

# Manual backup
/opt/backup/backup-configs.sh
/opt/backup/backup-postgresql.sh

# Check integrity
restic check

# Restore
restic restore latest --target /tmp/restore
```

## Troubleshooting

### SSH Lockout

```bash
# From console (VPS provider):
nano /etc/ssh/sshd_config
# Temporarily set: PasswordAuthentication yes
systemctl restart ssh
```

### Docker Network Broken

```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward  # Should be 1

# Enable if needed
sysctl -w net.ipv4.ip_forward=1

# Restart Docker
systemctl restart docker
```

### UFW Blocking Docker

```bash
# Check rules
ufw status verbose

# Edit before.rules
nano /etc/ufw/before.rules
# Ensure Docker bridge rules exist

# Restart UFW
ufw disable && ufw enable
```

### Monitoring Down

```bash
# Restart all
systemctl restart node-exporter prometheus alertmanager

# Check logs
journalctl -u prometheus -f
journalctl -u alertmanager -f

# Check disk space
df -h /opt/monitoring
```

### Backup Failing

```bash
# Check env vars
env | grep -E 'RESTIC_|AWS_'

# Test connection
restic snapshots

# Check R2 credentials
curl -s -I "https://ACCOUNT_ID.r2.cloudflarestorage.com/BUCKET" \
  -H "Authorization: AWS4-HMAC-SHA256 ..."
```

## Security Commands

### Find World-Writable Files

```bash
find / -type f -perm -0002 -not -path "/proc/*" 2>/dev/null
find / -type d -perm -0002 -not -path "/proc/*" 2>/dev/null
```

### Find SUID Files

```bash
find / -type f -perm -4000 -not -path "/proc/*" 2>/dev/null
```

### Check Open Ports

```bash
ss -tlnp
netstat -tlnp  # Alternative
```

### Check Listening Services

```bash
ss -tlnp | grep LISTEN
```

### View Auth Logs

```bash
tail -f /var/log/auth.log
journalctl -t sshd -f
```

### Audit Log Search

```bash
# Recent auth events
ausearch -m USER_AUTH -ts recent

# By key
ausearch -k sshd -ts today

# Generate report
aureport --summary
```

## Maintenance

### Update System

```bash
# Check updates
apt-get update
apt-get upgrade --dry-run

# Install
apt-get upgrade

# Reboot if kernel updated
systemctl reboot
```

### Clean Logs

```bash
# Check log sizes
du -sh /var/log/*

# Rotate logs
logrotate -f /etc/logrotate.conf

# Clear journal
journalctl --vacuum-time=7d
```

### Clean Docker

```bash
# Remove unused
docker system prune -a

# Remove old images
docker image prune -a --filter "until=168h"

# Check disk usage
docker system df
```

### Backup Rotation

```bash
# Remove old snapshots
restic forget --keep-last 7 --keep-daily 7 --prune

# Check repo
restic check
```

## Configuration Files

| File | Purpose |
|------|---------|
| `/etc/ssh/sshd_config` | SSH server config |
| `/etc/ufw/` | UFW firewall rules |
| `/etc/fail2ban/jail.local` | Fail2ban jails |
| `/etc/sysctl.d/99-hardening.conf` | Kernel hardening |
| `/etc/docker/daemon.json` | Docker config |
| `/opt/monitoring/prometheus/prometheus.yml` | Prometheus config |
| `/opt/monitoring/alertmanager/alertmanager.yml` | Alertmanager config |
| `/etc/profile.d/restic-backup.sh` | Backup env vars |

## Log Locations

| Log | Location |
|-----|----------|
| SSH | `/var/log/auth.log` |
| UFW | `/var/log/ufw.log` |
| Fail2ban | `/var/log/fail2ban.log` |
| Audit | `/var/log/audit/audit.log` |
| System | `/var/log/syslog` |
| Docker | `journalctl -u docker` |
| Backup | `/var/log/backup/` |
| Hardening | `/var/log/server-hardening/` |

## Emergency Contacts

```
Server Provider Console: https://provider.com/console
Cloudflare Dashboard: https://dash.cloudflare.com
Backup Storage: Cloudflare R2
Monitoring Alerts: Telegram Bot
```

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────┐
│  SSH:     ssh admin@server-ip                           │
│  Status:  ./scripts/validate-security.sh                │
│  Report:  ./scripts/security-report.sh                  │
│  Deploy:  ./scripts/quick-deploy.sh --yes               │
├─────────────────────────────────────────────────────────┤
│  Grafana:    http://localhost:9090 (SSH tunnel)         │
│  Prometheus: http://localhost:9090 (SSH tunnel)         │
│  Alertmgr:   http://localhost:9093 (SSH tunnel)         │
├─────────────────────────────────────────────────────────┤
│  Backup:   /opt/backup/                                 │
│  Logs:     /var/log/server-hardening/                   │
│  Configs:  /opt/server-hardening/configs/               │
└─────────────────────────────────────────────────────────┘
```

---

**Remember:** Always test changes in a non-production environment first!
