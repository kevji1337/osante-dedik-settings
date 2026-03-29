Infrastructure architecture:

OS:
Ubuntu 24.04 LTS

Deployment:
Dokploy

Services run in:
Docker containers

Reverse proxy:
Caddy

Traffic flow:

Internet
   │
Cloudflare
   │
Server (Ubuntu)
   │
Caddy reverse proxy
   │
Docker network
 ├ backend API
 ├ frontend website
 └ PostgreSQL container

Database:
PostgreSQL container on the same server

Security requirements:

- SSH access only via keys
- Root SSH login disabled
- Admin user with sudo
- PostgreSQL must NOT be publicly exposed
- Server behind Cloudflare

Backups:
Backup only:
- PostgreSQL database
- host configs
- Caddy config
- application uploads / persistent data

Backup storage:
Cloudflare R2 (S3 compatible)

Monitoring:
Monitoring must be installed on the server.

Requirements:
- host metrics
- docker/container metrics
- alerts in Telegram

Environment setup in Dokploy:

production
staging
dev

Currently only production is critical.

Constraints:

Hardening must NOT break:

- Docker
- Coolify
- container networking
- Caddy
- Cloudflare proxy
- TLS certificate issuance