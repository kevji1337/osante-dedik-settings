# Backup & Restore Guide

Complete guide for backup operations, restoration procedures, and disaster recovery.

## Overview

This server uses **Restic** for encrypted, deduplicated backups stored in **Cloudflare R2**.

### What Gets Backed Up

| Component | Frequency | Retention | Size (est.) |
|-----------|-----------|-----------|-------------|
| PostgreSQL Database | Daily 2:00 AM | 7d daily, 4w weekly, 12m monthly | Variable |
| Server Configurations | Daily 3:00 AM | 7d daily, 4w weekly, 12m monthly | ~50 MB |
| Application Data | Manual/Custom | As configured | Variable |

### Backup Storage

- **Provider:** Cloudflare R2 (S3-compatible)
- **Encryption:** AES-256 (via Restic)
- **Compression:** Auto (via Restic)
- **Deduplication:** Enabled (via Restic)

## Prerequisites

Before performing backup or restore operations:

1. **Environment Variables Configured:**

```bash
# Check configuration
cat /etc/profile.d/restic-backup.sh

# Load variables
source /etc/profile.d/restic-backup.sh
```

2. **Restic Installed:**

```bash
restic version
```

3. **Repository Initialized:**

```bash
restic snapshots
```

## Backup Operations

### Manual PostgreSQL Backup

```bash
# Full backup with upload to R2
/opt/backup/backup-postgresql.sh

# Local backup only (no upload)
/opt/backup/backup-postgresql.sh --local-only
```

### Manual Configuration Backup

```bash
# Full backup with upload to R2
/opt/backup/backup-configs.sh

# Local backup only
/opt/backup/backup-configs.sh --local-only
```

### Check Backup Status

```bash
# List all snapshots
restic snapshots

# List with details
restic snapshots --long

# Check repository integrity
restic check

# Show backup statistics
restic stats
```

### Backup to Local File (Alternative)

For additional local backups:

```bash
# PostgreSQL dump
pg_dumpall -h localhost -U postgres | gzip > /var/backups/manual/postgresql-$(date +%Y%m%d_%H%M%S).sql.gz

# Verify dump
gunzip -c /var/backups/manual/postgresql-*.sql.gz | head -20
```

## Restore Operations

### Restore PostgreSQL Database

#### Option 1: From Restic Backup

**Step 1: Find the snapshot**

```bash
restic snapshots --group-by=path | grep postgresql
```

**Step 2: Restore the backup file**

```bash
# Restore specific snapshot
restic restore <SNAPSHOT_ID> --target /tmp/restore

# Find the backup file
ls -la /tmp/restore/*/postgresql-*.sql.gz
```

**Step 3: Restore to database**

```bash
# Decompress and restore
gunzip -c /tmp/restore/*/postgresql-*.sql.gz | psql -h localhost -U postgres

# Or for specific database
gunzip -c /tmp/restore/*/postgresql-*.sql.gz | psql -h localhost -U postgres -d your_database
```

#### Option 2: From Local Backup

```bash
# List available backups
ls -la /var/backups/restic/temp/postgresql/

# Restore specific backup
gunzip -c /var/backups/restic/temp/postgresql/postgresql-20260316_020000.sql.gz | psql -h localhost -U postgres
```

#### Option 3: Docker Container Restore

If PostgreSQL runs in Docker:

```bash
# Find container name
docker ps | grep postgres

# Copy backup to container
docker cp /tmp/restore/*/postgresql-*.sql.gz coolify-db:/tmp/

# Restore inside container
docker exec -it coolify-db bash -c "gunzip -c /tmp/postgresql-*.sql.gz | psql -U postgres"
```

### Restore Server Configurations

**Step 1: Find and restore snapshot**

```bash
# Find config snapshots
restic snapshots --group-by=path | grep configs

# Restore
restic restore <SNAPSHOT_ID> --target /tmp/restore-configs
```

**Step 2: Review restored files**

```bash
# Navigate to restored files
cd /tmp/restore-configs

# List structure
tree -L 3
```

**Step 3: Restore specific configurations**

```bash
# SSH configuration
cp -r /tmp/restore-configs/*/etc/ssh /etc/

# UFW rules
cp -r /tmp/restore-configs/*/etc/ufw /etc/

# Fail2ban configuration
cp -r /tmp/restore-configs/*/etc/fail2ban /etc/

# Set correct permissions
chmod 600 /etc/ssh/sshd_config
chmod 644 /etc/ufw/*.rules
```

**Step 4: Restart affected services**

```bash
systemctl restart ssh
systemctl restart ufw
systemctl restart fail2ban
```

### Restore Application Data

```bash
# Find application data snapshots
restic snapshots --tag type=application-data

# Restore
restic restore <SNAPSHOT_ID> --target /tmp/restore-app

# Copy to original location
cp -r /tmp/restore-app/*/opt/osante /opt/

# Set permissions
chown -R www-data:www-data /opt/osante
```

## Disaster Recovery

### Full Server Recovery

In case of complete server failure:

**Step 1: Provision new server**

- Same or greater specs
- Ubuntu 24.04 LTS
- Note new IP address

**Step 2: Install prerequisites**

```bash
apt-get update
apt-get install -y restic postgresql-client
```

**Step 3: Configure Restic**

```bash
# Create environment file
cat > /etc/profile.d/restic-backup.sh << EOF
export RESTIC_REPOSITORY="r2:your-bucket-name"
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_ENDPOINT_URL_S3="https://account-id.r2.cloudflarestorage.com"
export RESTIC_PASSWORD="your-password"
EOF

source /etc/profile.d/restic-backup.sh
```

**Step 4: Access backup repository**

```bash
restic snapshots
```

**Step 5: Restore configurations**

```bash
# Restore configs first
restic restore latest --include /etc --target /
```

**Step 6: Restore database**

```bash
# Find and restore PostgreSQL backup
restic restore latest --include /var/backups --target /tmp/
gunzip -c /tmp/*/postgresql-*.sql.gz | psql -h localhost -U postgres
```

**Step 7: Reinstall services**

- Docker
- Coolify
- Caddy
- Your applications

### Recovery Verification

After any restore operation:

**Database:**

```bash
# Check database connectivity
psql -h localhost -U postgres -c "\l"

# Verify table counts
psql -h localhost -U postgres -d your_db -c "SELECT COUNT(*) FROM your_table;"
```

**Configurations:**

```bash
# SSH
sshd -t

# UFW
ufw status

# Fail2ban
fail2ban-client status
```

**Applications:**

```bash
# Check Docker containers
docker ps

# Check Caddy
curl -I https://your-domain.com
```

## Scheduled Backups

### Cron Schedule

Backups are scheduled via `/etc/cron.d/restic-backup`:

```cron
# PostgreSQL backup - daily at 2:00 AM
0 2 * * * root /opt/backup/backup-postgresql.sh >> /var/log/backup/cron-postgresql.log 2>&1

# Configs backup - daily at 3:00 AM
0 3 * * * root /opt/backup/backup-configs.sh >> /var/log/backup/cron-configs.log 2>&1

# Cleanup - weekly on Sunday at 4:00 AM
0 4 * * 0 root find /var/backups/restic/temp -type f -mtime +7 -delete 2>/dev/null
```

### Systemd Timers

Alternative scheduling via systemd:

```bash
# Check timer status
systemctl list-timers | grep backup

# View timer details
systemctl cat backup-postgresql.timer
```

## Retention Policy

Current retention settings:

```bash
# View current policy
grep RESTIC_FORGET_POLICY /opt/backup/restic-profile.sh
```

Default policy:
- Keep last 7 snapshots
- Keep 7 daily snapshots
- Keep 4 weekly snapshots
- Keep 12 monthly snapshots
- Keep 5 yearly snapshots

### Modify Retention

Edit `/opt/backup/restic-profile.sh`:

```bash
RESTIC_FORGET_POLICY="--keep-last 14 --keep-daily 14 --keep-weekly 8 --keep-monthly 24"
```

Apply immediately:

```bash
restic forget --prune
```

## Monitoring Backups

### Check Backup Logs

```bash
# Recent backup logs
tail -50 /var/log/backup/*.log

# Search for errors
grep -i error /var/log/backup/*.log

# Check last successful backup
grep "SUCCESS" /var/log/backup/*.log | tail -5
```

### Backup Health Check Script

```bash
#!/bin/bash
# /opt/backup/check-backup-health.sh

source /etc/profile.d/restic-backup.sh

echo "=== Restic Repository Status ==="
restic stats

echo ""
echo "=== Latest Snapshots ==="
restic snapshots --last 5

echo ""
echo "=== Repository Integrity ==="
restic check --read-data-subset=1%

echo ""
echo "=== Last Backup Age ==="
LAST_BACKUP=$(restic snapshots --last 1 --json | jq -r '.[0].time')
echo "Last backup: ${LAST_BACKUP}"
```

### Alert on Backup Failure

Add to monitoring alerts (`configs/monitoring/alert_rules.yml`):

```yaml
- alert: BackupMissing
  expr: time() - restic_last_backup_timestamp > 86400
  for: 1h
  labels:
    severity: critical
  annotations:
    summary: "Backup missing for more than 24 hours"
    telegram_message: "🔴 Backup не выполнялся более 24 часов"
```

## Troubleshooting

### Issue: Restic Repository Not Accessible

```bash
# Check environment variables
env | grep -E 'RESTIC_|AWS_'

# Test connection
restic snapshots

# Check R2 bucket
curl -s -I "https://ACCOUNT_ID.r2.cloudflarestorage.com/BUCKET_NAME" \
  -H "Authorization: AWS4-HMAC-SHA256 ..."
```

### Issue: Backup Fails Due to Space

```bash
# Check local temp space
df -h /var/backups

# Clean temp files
find /var/backups/restic/temp -mtime +7 -delete

# Prune old snapshots
restic forget --prune
```

### Issue: Restore Permission Denied

```bash
# Check file ownership
ls -la /tmp/restore/

# Fix permissions
chown -R $(whoami):$(whoami) /tmp/restore/
```

### Issue: PostgreSQL Restore Fails

```bash
# Check PostgreSQL is running
systemctl status postgresql

# Check connection
psql -h localhost -U postgres -c "\l"

# Check disk space
df -h /var/lib/postgresql

# Try single transaction
gunzip -c backup.sql.gz | psql -h localhost -U postgres --single-transaction
```

## Best Practices

1. **Test Restores Regularly**
   - Monthly restore test to separate environment
   - Verify data integrity after restore

2. **Monitor Backup Health**
   - Check backup logs daily
   - Set up alerts for failed backups

3. **Secure Credentials**
   - Never commit passwords to version control
   - Rotate R2 credentials periodically

4. **Document Recovery Procedures**
   - Keep runbooks updated
   - Train team on recovery process

5. **Multiple Backup Copies**
   - Consider additional backup location
   - Keep critical configs in version control

## Quick Reference

```bash
# List snapshots
restic snapshots

# Create manual backup
restic backup /path/to/backup

# Restore snapshot
restic restore SNAPSHOT_ID --target /tmp/restore

# Check integrity
restic check

# Remove old snapshots
restic forget --prune

# View statistics
restic stats
```

---

**Important:** Always test restore procedures in a non-production environment before relying on them for disaster recovery.
