You are a senior DevSecOps / SRE engineer.

Your task is to design and generate a production-ready server hardening and infrastructure setup for a newly purchased server.

OS:
Ubuntu 24.04 LTS

The server will host a commercial production product.

Architecture:

Deployment:
Coolify

Containers:
Docker

Reverse proxy:
Caddy

Traffic flow:

Internet
 → Cloudflare
 → Server
 → Caddy
 → Docker containers

Services that will run:

- backend API
- frontend website
- PostgreSQL container

PostgreSQL runs inside Docker on the same server.

SSH access:
- only via SSH keys
- root SSH login disabled
- one admin user with sudo

The system must be hardened but remain practical for production usage.

IMPORTANT:

Hardening must NOT break:

- Docker networking
- Docker bridge
- Coolify deployments
- Caddy reverse proxy
- Cloudflare proxy
- TLS certificate generation

The solution must focus on host security and operational readiness.

Do not configure business application code.

---

Your task is to generate a production-ready infrastructure setup.

The output must include:

1. Architecture explanation
2. Folder structure
3. Bash scripts
4. Configuration files
5. README documentation
6. Validation scripts

All scripts must be safe and understandable.

Requirements for scripts:

- Bash scripts
- set -Eeuo pipefail
- create backups before modifying configs
- clear logging
- idempotent where possible

---

Server preparation script must include:

- system update
- installation of base packages
- timezone setup
- admin user creation
- sudo configuration

Packages to install:

curl
wget
git
vim or nano
htop
tmux
jq
unzip
ufw
fail2ban
auditd
rsyslog
logrotate
needrestart
unattended-upgrades
apt-listchanges
debsums
ncdu
tree
bash-completion

---

SSH hardening:

- PermitRootLogin no
- PasswordAuthentication no
- PubkeyAuthentication yes
- MaxAuthTries
- LoginGraceTime
- ClientAliveInterval
- ClientAliveCountMax
- disable X11Forwarding

Always validate configuration with:

sshd -t

before restarting ssh.

---

Firewall configuration:

Use UFW.

Rules:

default deny incoming
default allow outgoing

Open ports:

SSH
80
443

PostgreSQL port 5432 must NOT be exposed publicly.

Ensure firewall does not break Docker networking.

---

Fail2ban configuration:

Configure jail for SSH.

Use reasonable limits.

---

Kernel hardening:

Configure safe sysctl settings:

- spoofing protection
- disable ICMP redirects
- disable source routing
- SYN cookies
- martian logging
- filesystem protections

Do NOT include settings that break Docker networking.

---

Filesystem security:

- proper permissions
- secure umask
- check world writable files
- audit friendly configuration

---

Logging and auditing:

Configure:

auditd
journald retention
logrotate
auth logs
sudo logs

---

Docker host best practices:

Provide recommendations for:

- docker socket protection
- docker group access
- container isolation
- volume permissions
- restart policies
- logging drivers

Do NOT break Coolify.

---

PostgreSQL container security recommendations:

- do not expose port externally
- use docker internal network
- provide backup strategy

---

Monitoring:

Install a practical monitoring stack suitable for one production server.

Requirements:

- monitor CPU
- RAM
- disk usage
- network
- docker containers
- system load

Monitoring must support alerts.

Alerts must be sent to Telegram.

Include:

- instructions to configure Telegram bot
- alert rules examples

Choose a monitoring stack and briefly explain the choice.

---

Backups:

Backup strategy must include:

1. PostgreSQL backups
2. server configs
3. Caddy config
4. application uploads / persistent data

Backup storage:

Cloudflare R2 (S3 compatible)

Recommended tool:

restic or similar.

Backups must include:

- encryption
- retention policy
- scheduled jobs

Also include restore instructions.

---

Validation script:

Generate a script that checks:

- SSH configuration
- firewall status
- fail2ban
- sysctl settings
- docker status
- open ports
- sudo configuration
- world writable files

Output a security summary.

---

Output format:

1. Architecture overview
2. File structure
3. Full scripts
4. README
5. Setup steps
6. Validation steps
7. Backup restore instructions
8. Security notes

The result must be production-ready, secure-by-default and maintainable.