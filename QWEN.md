# Osante Infrastructure - Project Context

## Project Overview

Production-ready server hardening and infrastructure setup for **Osante** - a commercial web application deployed on Ubuntu 24.04 LTS using Coolify as the deployment platform.

### Architecture Summary

```
Internet → Cloudflare → Ubuntu Server → Caddy Reverse Proxy → Docker Containers
                                                              ├ backend API
                                                              ├ frontend website
                                                              └ PostgreSQL
```

**Tech Stack:**
- **OS:** Ubuntu 24.04 LTS
- **Deployment Platform:** Coolify
- **Container Runtime:** Docker
- **Reverse Proxy:** Caddy (with Cloudflare integration)
- **Database:** PostgreSQL (Docker container)
- **Backup Storage:** Cloudflare R2 (S3-compatible)
- **Monitoring:** System metrics + Docker metrics → Telegram alerts

## Repository Structure

| File | Description |
|------|-------------|
| `PROMPT.md` | Detailed specification for infrastructure setup including SSH hardening, firewall, Fail2ban, sysctl, monitoring, backups |
| `ARCHITECTURE.md` | High-level infrastructure diagram, traffic flow, security requirements, constraints |
| `Caddyfile` | Caddy reverse proxy configuration with Cloudflare verification, security headers, TLS |
| `QWEN.md` | This file - context for AI assistants |

## Key Configuration Details

### Caddy Reverse Proxy (`Caddyfile`)
- Cloudflare-only access enforcement (`CF-Ray` header check)
- Security headers: HSTS, X-Frame-Options, CSP, etc.
- JSON logging with rotation (10MB, 5 files, 30 days)
- Routes: `/api*` → backend:8000, static → osante-web:80
- Health endpoints: `/healthz`, `/readyz`

### Security Requirements
- SSH: keys only, root login disabled, admin user with sudo
- Firewall: UFW with deny incoming, allow outgoing (ports 22, 80, 443)
- PostgreSQL: NOT publicly exposed (Docker internal network only)
- Kernel hardening via sysctl (without breaking Docker networking)
- Fail2ban for SSH protection
- auditd + journald for auditing

### Backup Strategy
- **Tool:** restic (or similar)
- **Storage:** Cloudflare R2 (encrypted)
- **Scope:** PostgreSQL dumps, host configs, Caddy config, application uploads
- **Features:** retention policy, scheduled jobs, restore instructions

### Monitoring Requirements
- Host metrics (CPU, RAM, disk, network, load)
- Docker/container metrics
- Alert rules with Telegram integration

## Development & Operational Conventions

### Script Standards
- Bash with `set -Eeuo pipefail`
- Idempotent operations where possible
- Backups before config modifications
- Clear logging throughout

### Environment Tiers (Coolify)
1. `production` (critical)
2. `staging`
3. `dev`

### Constraints - Hardening Must NOT Break
- Docker networking / bridge
- Coolify deployments
- Caddy reverse proxy
- Cloudflare proxy
- TLS certificate issuance

## Common Operations

### Validation Checks
- SSH configuration (`sshd -t`)
- Firewall status (UFW)
- Fail2ban jails
- Sysctl settings
- Docker status
- Open ports
- World-writable files

### Setup Phases (from PROMPT.md)
1. Server preparation (packages, user, sudo)
2. SSH hardening
3. Firewall (UFW) configuration
4. Fail2ban setup
5. Kernel hardening (sysctl)
6. Filesystem security
7. Logging/auditing (auditd, journald, logrotate)
8. Docker host best practices
9. PostgreSQL container security
10. Monitoring stack installation
11. Backup configuration (restic + R2)
12. Validation script execution

## Files to Generate (per PROMPT.md)

The project expects generation of:
- Bash scripts for each setup phase
- Configuration files (sshd_config, ufw rules, fail2ban jails, sysctl.conf, etc.)
- Monitoring stack with Telegram alerts
- Backup scripts with encryption and retention
- Validation script for security checks
- README documentation

## Security Notes

- All hardening must maintain operational readiness
- PostgreSQL accessible only via Docker internal network
- Cloudflare proxy required for all external traffic
- No business application code in this repository
