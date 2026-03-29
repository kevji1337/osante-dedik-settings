# Setup Guide - Server Hardening & Infrastructure

Detailed step-by-step instructions for setting up a production-ready hardened server.

## Prerequisites

Before starting, ensure you have:

- [ ] Fresh Ubuntu 24.04 LTS server (minimum 2GB RAM, 2 CPU, 25GB disk)
- [ ] Root access via SSH
- [ ] SSH key pair generated (`ssh-keygen -t ed25519`)
- [ ] Domain name pointing to server IP (for Caddy TLS)
- [ ] Cloudflare account (for proxy and R2 storage)
- [ ] At least 1 hour for complete setup

## Phase 1: Initial Server Setup

### 1.1 Connect to Server

```bash
ssh root@your-server-ip
```

### 1.2 Update System

```bash
apt-get update && apt-get upgrade -y
```

### 1.3 Install Required Tools

```bash
apt-get install -y curl wget git vim nano htop tmux jq unzip
```

### 1.4 Copy Hardening Scripts to Server

From your local machine:

```bash
# Option A: Using scp
scp -r . root@your-server-ip:/opt/server-hardening

# Option B: Using git
ssh root@your-server-ip
cd /opt
git clone <your-repo-url> server-hardening
```

### 1.5 Navigate to Scripts Directory

```bash
cd /opt/server-hardening
chmod +x scripts/*.sh configs/backup/*.sh
```

## Phase 2: System Preparation

### 2.1 Run System Preparation Script

```bash
./scripts/01-system-prep.sh \
    --username admin \
    --ssh-key "ssh-ed25519 AAAA... your-public-key" \
    --timezone UTC \
    --hostname your-server-name
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--username` | Yes | Admin username (not 'root') |
| `--ssh-key` | Yes | Your SSH public key |
| `--timezone` | No | Server timezone (default: UTC) |
| `--hostname` | No | Server hostname |

### 2.2 Verify Installation

```bash
# Check installed packages
dpkg -l | grep -E 'ufw|fail2ban|auditd'

# Check admin user
id admin

# Check sudo configuration
visudo -c
```

### 2.3 Test Admin User Access

Open a **new terminal** and test:

```bash
ssh admin@your-server-ip
sudo whoami  # Should return 'root'
```

> ⚠️ **Important:** Do not proceed until you verify admin user can SSH and use sudo!

## Phase 3: SSH Hardening

### 3.1 Backup Current SSH Configuration

```bash
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.initial
```

### 3.2 Review SSH Configuration

```bash
cat configs/sshd_config
```

Key settings:
- `PermitRootLogin no` - No root SSH
- `PasswordAuthentication no` - Keys only
- `MaxAuthTries 3` - Limit attempts
- `ClientAliveInterval 300` - Keep-alive

### 3.3 Apply SSH Hardening

```bash
./scripts/02-ssh-hardening.sh
```

### 3.4 Verify SSH Configuration

```bash
# Test configuration syntax
sshd -t

# Check SSH service status
systemctl status ssh

# View active connections
ss -tlnp | grep ssh
```

### 3.5 Test New SSH Connection

**DO NOT CLOSE YOUR CURRENT SESSION!** Open a new terminal:

```bash
ssh -v admin@your-server-ip
```

If connection succeeds, you can close the old session.

### 3.6 Recovery (If Locked Out)

If you lose SSH access:

1. Access server via console (VPS provider's web console)
2. Restore backup: `cp /var/backups/hardening/sshd_config.backup.* /etc/ssh/sshd_config`
3. Restart SSH: `systemctl restart ssh`

## Phase 4: Firewall Configuration

### 4.1 Review Firewall Rules

```bash
cat configs/ufw/user.rules
cat configs/ufw/before.rules
```

### 4.2 Apply Firewall Configuration

```bash
./scripts/03-firewall-setup.sh
```

### 4.3 Verify Firewall Status

```bash
# Check UFW status
ufw status verbose

# Check open ports
ss -tlnp | grep LISTEN
```

Expected open ports:
- 22/tcp (SSH)
- 80/tcp (HTTP - for TLS certificates)
- 443/tcp (HTTPS)

### 4.4 Docker Compatibility Check

```bash
# Verify Docker networking works
docker run --rm hello-world

# Check container can access internet
docker run --rm alpine ping -c 2 8.8.8.8
```

## Phase 5: Fail2ban Configuration

### 5.1 Apply Fail2ban Configuration

```bash
./scripts/04-fail2ban-config.sh
```

### 5.2 Verify Fail2ban Status

```bash
# Service status
systemctl status fail2ban

# Active jails
fail2ban-client status

# SSH jail details
fail2ban-client status sshd
```

### 5.3 Test Fail2ban (Optional)

From a **different IP address**, attempt multiple failed SSH logins:

```bash
# This should get banned after 5 attempts
ssh admin@your-server-ip  # Wrong password 5 times
```

Check if banned:

```bash
fail2ban-client status sshd
```

## Phase 6: Kernel Hardening

### 6.1 Review Sysctl Settings

```bash
cat configs/sysctl.d/99-hardening.conf
```

### 6.2 Apply Kernel Hardening

```bash
./scripts/05-sysctl-hardening.sh
```

### 6.3 Verify Settings

```bash
# Check key parameters
sysctl net.ipv4.ip_forward
sysctl net.ipv4.tcp_syncookies
sysctl kernel.randomize_va_space
```

### 6.4 Docker Network Verification

```bash
# Ensure Docker still works
docker ps
docker network ls
```

## Phase 7: Filesystem Security

### 7.1 Run Filesystem Security Script

```bash
./scripts/06-filesystem-security.sh
```

### 7.2 Review Report

```bash
cat /var/backups/hardening/filesystem-report.*.txt
```

### 7.3 Fix Any Issues

The script will identify:
- World-writable files
- SUID/SGID files
- Incorrect permissions on critical files

Review and fix as needed.

## Phase 8: Logging Configuration

### 8.1 Apply Logging Configuration

```bash
./scripts/07-logging-setup.sh
```

### 8.2 Verify Logging Services

```bash
systemctl status auditd
systemctl status rsyslog
systemctl status systemd-journald
```

### 8.3 Test Logging

```bash
# Generate test log entry
logger "Test log entry from hardening setup"

# Check journal
journalctl -t logger --since "1 minute ago"

# Check audit log
ausearch -m USER_AUTH -ts recent
```

## Phase 9: Monitoring Setup

### 9.1 Install Monitoring Stack

```bash
./scripts/08-monitoring-setup.sh
```

This installs:
- Node Exporter (port 9100)
- Prometheus (port 9090)
- Alertmanager (port 9093)

### 9.2 Configure Telegram Alerts

1. **Create Telegram Bot:**
   - Open @BotFather in Telegram
   - Send `/newbot`
   - Follow prompts to create bot
   - Save the bot token

2. **Get Chat ID:**
   - Add bot to your chat/channel
   - Send any message
   - Visit: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
   - Find `"chat":{"id":123456789}`

3. **Update Alertmanager Configuration:**

```bash
nano /opt/monitoring/alertmanager/alertmanager.yml
```

Replace:
- `YOUR_BOT_TOKEN` with your bot token
- `YOUR_CHAT_ID` with your chat ID

4. **Restart Alertmanager:**

```bash
systemctl restart alertmanager
```

### 9.3 Access Monitoring Dashboards

Via SSH tunnel:

```bash
# Prometheus
ssh -L 9090:localhost:9090 admin@your-server-ip
# Open: http://localhost:9090

# Alertmanager
ssh -L 9093:localhost:9093 admin@your-server-ip
# Open: http://localhost:9093
```

## Phase 10: Backup Setup

### 10.1 Install Backup System

```bash
./scripts/09-backup-setup.sh
```

### 10.2 Configure Cloudflare R2

1. **Create R2 Bucket:**
   - Go to Cloudflare Dashboard → R2 Storage
   - Create new bucket (e.g., `server-backups`)

2. **Create API Token:**
   - R2 API Tokens → Create API Token
   - Permissions: Object Read & Write
   - Save Access Key ID and Secret Access Key

3. **Get Account ID:**
   - Found in Cloudflare Dashboard (bottom right)

4. **Configure Environment Variables:**

```bash
nano /etc/profile.d/restic-backup.sh
```

Fill in:
```bash
export RESTIC_REPOSITORY="r2:server-backups"
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_ENDPOINT_URL_S3="https://your-account-id.r2.cloudflarestorage.com"
export RESTIC_PASSWORD="your-strong-encryption-password"
```

5. **Apply Variables:**

```bash
source /etc/profile.d/restic-backup.sh
```

### 10.3 Initialize Restic Repository

```bash
restic init
```

### 10.4 Test Backup

```bash
# Test configs backup (local only)
/opt/backup/backup-configs.sh --local-only

# Check backup status
restic snapshots
```

## Phase 11: Validation

### 11.1 Run Security Validation

```bash
./scripts/validate-security.sh
```

### 11.2 Review Report

```bash
cat /var/log/server-hardening/security-report.*.txt
```

### 11.3 Address Any Failures

The report will show:
- ✅ PASS - Configuration is correct
- ⚠️ WARN - Warning, review recommended
- ❌ FAIL - Issue needs to be fixed

## Post-Setup Tasks

### 12.1 Configure Coolify

1. Install Coolify (if not already done):
   ```bash
   curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
   ```

2. Access Coolify at `http://your-server-ip:8000`

3. Configure your applications

### 12.2 Configure Caddy

Your Caddyfile should be at `/etc/caddy/Caddyfile`

Verify configuration:
```bash
caddy validate --config /etc/caddy/Caddyfile
```

### 12.3 Set Up Your Applications

1. Deploy applications via Coolify
2. Configure domains in Cloudflare
3. Ensure Cloudflare proxy is enabled (orange cloud)
4. Verify TLS certificates are working

### 12.4 Create Maintenance Schedule

**Daily:**
- Check backup logs: `tail /var/log/backup/*.log`
- Review monitoring alerts

**Weekly:**
- Run security validation: `./scripts/validate-security.sh`
- Check disk usage: `ncdu /`
- Review fail2ban bans: `fail2ban-client status`

**Monthly:**
- Review and rotate logs
- Test backup restoration
- Update system packages
- Review security policies

## Troubleshooting

### Issue: SSH Connection Refused

```bash
# Check SSH service
systemctl status ssh

# Check firewall
ufw status

# Check if port 22 is listening
ss -tlnp | grep :22
```

### Issue: Docker Containers Can't Communicate

```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward

# Check UFW rules for Docker
ufw status verbose

# Restart Docker
systemctl restart docker
```

### Issue: Caddy Can't Get TLS Certificates

```bash
# Check port 80 is open
ufw status | grep 80

# Verify DNS points to server
dig your-domain.com

# Check Caddy logs
journalctl -u caddy -f
```

### Issue: Backups Failing

```bash
# Check environment variables
env | grep -E 'RESTIC_|AWS_'

# Test R2 connection
restic snapshots

# Check restic logs
tail /var/log/backup/*.log
```

## Next Steps

1. [Backup & Restore Procedures](BACKUP-RESTORE.md)
2. [Monitoring Configuration](MONITORING.md)
3. [Security Hardening Details](SECURITY-HARDENING.md)

---

**Setup Complete!** 🎉

Your server is now hardened and production-ready. Remember to:
- Keep the system updated
- Monitor alerts regularly
- Test backups periodically
- Review security configurations quarterly
