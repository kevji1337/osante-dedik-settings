# =============================================================================
# Osante Infrastructure - Makefile
# Описание: Автоматизация常见 операций
# =============================================================================

.PHONY: help validate deploy backup restore check clean docs test

# =============================================================================
# Help
# =============================================================================

help:
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║   Osante Infrastructure - Available Commands                 ║"
	@echo "╠══════════════════════════════════════════════════════════════╣"
	@echo "║  make validate     - Run security validation                 ║"
	@echo "║  make check        - Check Docker compatibility              ║"
	@echo "║  make deploy       - Full deployment                         ║"
	@echo "║  make backup       - Run backup                              ║"
	@echo "║  make restore      - Restore from backup                     ║"
	@echo "║  make docs         - Generate documentation                  ║"
	@echo "║  make clean        - Clean temporary files                   ║"
	@echo "║  make test         - Run all tests                           ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"

# =============================================================================
# Validation
# =============================================================================

validate:
	@echo "🔍 Running security validation..."
	@chmod +x scripts/validate-security.sh
	@./scripts/validate-security.sh

check:
	@echo "🐳 Checking Docker compatibility..."
	@chmod +x scripts/check-ufw-docker.sh
	@./scripts/check-ufw-docker.sh

# =============================================================================
# Deployment
# =============================================================================

deploy: deploy-01 deploy-02 deploy-03 deploy-04 deploy-05 deploy-06 deploy-07 deploy-08 deploy-09 deploy-10
	@echo "✅ Deployment complete!"

deploy-01:
	@echo "📦 Step 1/10: System Preparation..."
	@chmod +x scripts/01-system-prep.sh
	@./scripts/01-system-prep.sh --username admin --ssh-key "$$(cat ~/.ssh/id_ed25519.pub)" --timezone UTC

deploy-02:
	@echo "🔐 Step 2/10: SSH Hardening..."
	@chmod +x scripts/02-ssh-hardening.sh
	@./scripts/02-ssh-hardening.sh --no-restart
	@echo "⚠️  Test SSH in new session before restart!"

deploy-03:
	@echo "🔥 Step 3/10: Firewall Setup..."
	@chmod +x scripts/03-firewall-setup.sh
	@./scripts/03-firewall-setup.sh --with-cloudflare

deploy-04:
	@echo "🚔 Step 4/10: Fail2ban Setup..."
	@chmod +x scripts/04-fail2ban-config.sh
	@./scripts/04-fail2ban-config.sh

deploy-05:
	@echo "⚙️  Step 5/10: Sysctl Hardening..."
	@chmod +x scripts/05-sysctl-hardening.sh
	@./scripts/05-sysctl-hardening.sh

deploy-06:
	@echo "📁 Step 6/10: Filesystem Security..."
	@chmod +x scripts/06-filesystem-security.sh
	@./scripts/06-filesystem-security.sh

deploy-07:
	@echo "📝 Step 7/10: Logging Setup..."
	@chmod +x scripts/07-logging-setup.sh
	@./scripts/07-logging-setup.sh

deploy-08:
	@echo "📊 Step 8/10: Monitoring Setup..."
	@chmod +x scripts/08-monitoring-setup.sh
	@./scripts/08-monitoring-setup.sh

deploy-09:
	@echo "💾 Step 9/10: Backup Setup..."
	@chmod +x scripts/09-backup-setup.sh
	@./scripts/09-backup-setup.sh

deploy-10:
	@echo "🐳 Step 10/10: Docker Security..."
	@chmod +x scripts/10-docker-security.sh
	@./scripts/10-docker-security.sh --no-restart

# =============================================================================
# Backup & Restore
# =============================================================================

backup:
	@echo "💾 Running backup..."
	@chmod +x scripts/09-backup-setup.sh
	@./scripts/09-backup-setup.sh

restore:
	@echo "🔄 Restore instructions:"
	@echo "   See docs/BACKUP-RESTORE.md for detailed restore procedures"
	@echo ""
	@echo "   Quick restore:"
	@echo "   ./configs/backup/restore-postgresql.sh --list"
	@echo "   ./configs/backup/restore-postgresql.sh [snapshot_id]"

# =============================================================================
# Documentation
# =============================================================================

docs:
	@echo "📖 Generating documentation..."
	@echo ""
	@echo "Available documentation:"
	@echo "  - README.md                    : Main documentation"
	@echo "  - FINAL_DEPLOYMENT_CHECK.md    : Deployment guide"
	@echo "  - CRITICAL_FIXES_APPLIED.md    : Security fixes"
	@echo "  - ARCHITECTURE.md              : Architecture overview"
	@echo "  - docs/CLOUDFLARE_TUNNEL.md    : Tunnel setup"
	@echo "  - docs/MONITORING.md           : Monitoring setup"
	@echo "  - docs/BACKUP-RESTORE.md       : Backup & restore"

# =============================================================================
# Cleanup
# =============================================================================

clean:
	@echo "🧹 Cleaning temporary files..."
	@rm -rf /var/backups/restic/temp/*
	@rm -rf /var/log/backup/*.log
	@rm -rf /var/log/server-hardening/*.log
	@echo "✅ Cleanup complete"

# =============================================================================
# Testing
# =============================================================================

test: validate check
	@echo "✅ All tests passed!"

# =============================================================================
# Demo
# =============================================================================

demo:
	@chmod +x scripts/demo.sh
	@./scripts/demo.sh
