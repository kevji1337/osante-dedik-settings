# 🚀 Quick Start — Production Deployment

**Статус:** ✅ PRODUCTION READY  
**Последний аудит:** 2026-03-16  
**Вердикт:** ГОТОВО ДЛЯ PRODUCTION

---

## ⚠️ ПЕРЕД НАЧАЛОМ

### Обязательные требования

1. **✅ Консольный доступ (VPS web console)**
   - Обязательно для восстановления при блокировке SSH
   - Проверьте что можете войти через консоль

2. **✅ SSH ключ проверен**
   - Сгенерируйте: `ssh-keygen -t ed25519 -a 100`
   - Добавьте на сервер: `ssh-copy-id root@server-ip`
   - **Проверьте в НОВОЙ сессии** что вход работает

3. **✅ Backup/снэпшот сделан**
   - Создайте снэпшот сервера перед изменениями

---

## 📋 КОМАНДЫ БЫСТРОГО РАЗВЁРТЫВАНИЯ

```bash
# =============================================================================
# 0. Подготовка
# =============================================================================

# Скопировать на сервер
scp -r . root@server-ip:/opt/server-hardening
ssh root@server-ip
cd /opt/server-hardening

# Сделать скрипты исполняемыми
chmod +x scripts/*.sh configs/backup/*.sh

# =============================================================================
# 1. System Preparation (15 минут)
# =============================================================================

./scripts/01-system-prep.sh \
    --username admin \
    --ssh-key "$(cat ~/.ssh/id_ed25519.pub)" \
    --timezone UTC

# =============================================================================
# 2. SSH Hardening (10 минут) ⚠️
# =============================================================================

# БЕЗ перезапуска!
./scripts/02-ssh-hardening.sh --no-restart

# ОТКРЫТЬ НОВУЮ SSH СЕССИЮ и проверить вход
# ssh admin@server-ip

# Если работает — перезапустить SSH
systemctl restart ssh

# =============================================================================
# 3. Firewall with Cloudflare Protection (10 минут) ⚠️
# =============================================================================

# Dry-run для проверки
./scripts/03-firewall-setup.sh --dry-run --with-cloudflare

# Проверить правила
ufw status verbose

# Активировать
./scripts/03-firewall-setup.sh --with-cloudflare

# =============================================================================
# 4. Network Security (15 минут)
# =============================================================================

./scripts/04-fail2ban-config.sh
./scripts/05-sysctl-hardening.sh
./scripts/06-filesystem-security.sh
./scripts/07-logging-setup.sh

# =============================================================================
# 5. Docker Security (10 минут) ⚠️
# =============================================================================

# ЗАПУСКАТЬ ДО УСТАНОВКИ COOLIFY!
./scripts/10-docker-security.sh --no-restart
systemctl restart docker

# =============================================================================
# 6. Monitoring (20 минут)
# =============================================================================

./scripts/08-monitoring-setup.sh

# =============================================================================
# 7. Backup (15 минут) ⚠️
# =============================================================================

./scripts/09-backup-setup.sh

# Заполнить переменные R2
nano /etc/profile.d/restic-backup.sh

# Применить и инициализировать
source /etc/profile.d/restic-backup.sh
restic init

# =============================================================================
# 8. Финальная проверка (10 минут)
# =============================================================================

./scripts/validate-security.sh
./scripts/security-report.sh

# =============================================================================
# 9. Установка Coolify (если ещё не установлен)
# =============================================================================

curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

---

## ✅ ЧЕК-ЛИСТ ЗАВЕРШЕНИЯ

```bash
# Проверить SSH
ssh admin@server-ip

# Проверить UFW
ufw status verbose
# Должно быть: 22 ALLOW, 80/443 Cloudflare only, 5432 DROP

# Проверить Docker
docker ps
docker run --rm hello-world

# Проверить мониторинг
systemctl status node-exporter prometheus alertmanager

# Проверить порты мониторинга (должны быть localhost)
ss -tlnp | grep -E '9090|9093|9100'
# Должно быть: 127.0.0.1:9090, 127.0.0.1:9093, 127.0.0.1:9100

# Проверить backup
restic snapshots
```

---

## 🚨 ВОССТАНОВЛЕНИЕ

### SSH Lockout

```bash
# 1. Войти через VPS console
# 2. Восстановить:
cp /var/backups/hardening/sshd_config.backup.* /etc/ssh/sshd_config
systemctl restart ssh
```

### UFW Блокировка

```bash
# 1. Войти через VPS console
# 2. Отключить:
ufw disable
```

### Docker Networking

```bash
# 1. Проверить IP forwarding:
sysctl net.ipv4.ip_forward

# 2. Перезапустить Docker:
systemctl restart docker
```

---

## 📖 ДОКУМЕНТАЦИЯ

| Документ | Описание |
|----------|----------|
| [FINAL_SECURITY_AUDIT.md](FINAL_SECURITY_AUDIT.md) | Полный аудит безопасности |
| [SAFE_DEPLOYMENT.md](SAFE_DEPLOYMENT.md) | Пошаговая инструкция |
| [SIMULATION_REPORT.md](SIMULATION_REPORT.md) | Анализ рисков |
| [docs/CLOUDFLARE_PROTECTION.md](docs/CLOUDFLARE_PROTECTION.md) | Cloudflare защита |
| [docs/BACKUP-RESTORE.md](docs/BACKUP-RESTORE.md) | Backup и восстановление |

---

## 🔒 SECURITY SUMMARY

```
┌────────────────────────────────────────────────────────────────┐
│  CRITICAL: 0  │  HIGH: 0  │  MEDIUM: 3  │  LOW: 4  │  ВСЕГО: 7 │
└────────────────────────────────────────────────────────────────┘

✅ SSH: PasswordAuthentication=no, PermitRootLogin=no
✅ UFW: Cloudflare IP protection, Docker-compatible
✅ PostgreSQL: Port 5432 blocked
✅ Monitoring: Localhost only (9090, 9093, 3000)
✅ Backup: Restic + R2 encrypted
✅ Docker: Coolify-compatible
```

---

**Last Updated:** 2026-03-16  
**Version:** 1.0  
**Status:** ✅ PRODUCTION READY
