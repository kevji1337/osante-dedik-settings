# 🛡️ SAFE DEPLOYMENT GUIDE

**Безопасное развёртывание infrastructure hardening**

---

## ⚠️ ПРЕДУПРЕЖДЕНИЯ ПЕРЕД НАЧАЛОМ

### Критические Требования

1. **✅ Консольный доступ (VPS web console)**
   - Обязательно для восстановления при блокировке SSH
   - Проверьте что можете войти через консоль

2. **✅ SSH ключ проверен**
   - Сгенерируйте: `ssh-keygen -t ed25519 -a 100`
   - Добавьте на сервер: `ssh-copy-id root@server-ip`
   - **Проверьте в НОВОЙ сессии** что вход работает

3. **✅ Backup/снэпшот сделан**
   - Создайте снэпшот сервера перед изменениями
   - Сохраните важные данные

4. **✅ Время на тестирование**
   - Выделите 1-2 часа на развёртывание
   - Не применяйте в production в рабочее время

---

## 📋 ПОЭТАПНОЕ РАЗВЁРТЫВАНИЕ

### Этап 1: Подготовка (15 минут)

```bash
# Копирование скриптов на сервер
scp -r . root@server-ip:/opt/server-hardening
ssh root@server-ip
cd /opt/server-hardening

# Сделать скрипты исполняемыми
chmod +x scripts/*.sh configs/backup/*.sh
```

#### Шаг 1.1: System Preparation

```bash
# Запуск подготовки системы
./scripts/01-system-prep.sh \
    --username admin \
    --ssh-key "$(cat ~/.ssh/id_ed25519.pub)" \
    --timezone UTC

# Проверка:
id admin
# Должно вывести: uid=1000(admin) gid=1000(admin) groups=...
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 2: SSH Хардинг (10 минут) ⚠️

```bash
# ШАГ 2.1: Применить конфиг БЕЗ перезапуска
./scripts/02-ssh-hardening.sh --no-restart

# ШАГ 2.2: ОТКРЫТЬ НОВУЮ SSH СЕССИЮ
# В новом терминале:
ssh admin@server-ip

# Если вход успешен → ШАГ 2.3:
# Вернуться в первую сессию и перезапустить SSH
systemctl restart ssh

# ШАГ 2.4: Проверить что обе сессии работают
who
# Должны видеть оба подключения
```

**⚠️ ЕСЛИ НОВАЯ СЕССИЯ НЕ РАБОТАЕТ:**
```bash
# Не перезапускать SSH!
# Восстановить backup:
cp /var/backups/hardening/sshd_config.backup.* /etc/ssh/sshd_config
systemctl restart ssh
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 3: Фаервол UFW (10 минут) ⚠️

```bash
# ШАГ 3.1: Dry-run (проверка правил)
./scripts/03-firewall-setup.sh --dry-run

# ШАГ 3.2: Проверить правила
ufw status verbose
# Должно быть:
#   22/tcp (SSH) ALLOW
#   80/tcp (HTTP) ALLOW
#   443/tcp (HTTPS) ALLOW

# ШАГ 3.3: Только после проверки активировать
./scripts/03-firewall-setup.sh

# ШАГ 3.4: Проверить что SSH работает
# Не закрывать текущую сессию!
# Открыть ТРЕТЬЮ сессию и проверить вход
ssh admin@server-ip
```

**⚠️ ЕСЛИ SSH ЗАБЛОКИРОВАН:**
```bash
# Войти через VPS console
ufw disable
# Или через console:
ufw --force reset
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 4: Сеть и Ядро (15 минут)

```bash
# ШАГ 4.1: Fail2ban
./scripts/04-fail2ban-config.sh

# Проверка:
fail2ban-client status
fail2ban-client status sshd

# ШАГ 4.2: Sysctl хардинг (ДО Docker!)
./scripts/05-sysctl-hardening.sh

# Проверка:
sysctl net.ipv4.ip_forward
# Должно быть: net.ipv4.ip_forward = 1

# ШАГ 4.3: Filesystem security
./scripts/06-filesystem-security.sh

# ШАГ 4.4: Logging setup
./scripts/07-logging-setup.sh
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 5: Docker Security (10 минут) ⚠️

```bash
# ⚠️ ВАЖНО: Запускать ДО установки Coolify!

# ШАГ 5.1: Docker security
./scripts/10-docker-security.sh --no-restart

# ШАГ 5.2: Проверить конфиг
cat /etc/docker/daemon.json
# Должно быть:
#   "userland-proxy": true
#   "userns-remap": ""

# ШАГ 5.3: Перезапуск Docker
systemctl restart docker

# ШАГ 5.4: Проверить Docker
docker ps
docker run --rm hello-world
```

**⚠️ ЕСЛИ COOLIFY УЖЕ УСТАНОВЛЕН:**
```bash
# Остановить контейнеры перед применением:
docker stop $(docker ps -q)
./scripts/10-docker-security.sh --no-restart
systemctl restart docker
docker start $(docker ps -aq)

# Пересоздать приложения в Coolify
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 6: Monitoring (20 минут)

```bash
# ШАГ 6.1: Monitoring setup
./scripts/08-monitoring-setup.sh

# ШАГ 6.2: Проверить сервисы
systemctl status node-exporter
systemctl status prometheus
systemctl status alertmanager

# ШАГ 6.3: Проверить порты (должны быть localhost!)
ss -tlnp | grep -E '9090|9093|9100'
# Должно быть:
#   127.0.0.1:9090
#   127.0.0.1:9093
#   127.0.0.1:9100

# ШАГ 6.4: Настроить Telegram (опционально)
# Следовать инструкциям из вывода скрипта
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 7: Backup (15 минут) ⚠️

```bash
# ШАГ 7.1: Backup setup (без cron)
./scripts/09-backup-setup.sh

# ШАГ 7.2: Заполнить переменные
nano /etc/profile.d/restic-backup.sh

# Заполнить:
#   RESTIC_REPOSITORY="r2:your-bucket"
#   AWS_ACCESS_KEY_ID="..."
#   AWS_SECRET_ACCESS_KEY="..."
#   AWS_ENDPOINT_URL_S3="https://..."
#   RESTIC_PASSWORD="..."

# ШАГ 7.3: Применить переменные
source /etc/profile.d/restic-backup.sh

# ШАГ 7.4: Инициализировать restic
restic init

# ШАГ 7.5: Проверить backup
/opt/backup/backup-configs.sh --local-only
restic snapshots
```

**✅ Проверка завершена** → Переходим дальше

---

### Этап 8: Финальная Проверка (10 минут)

```bash
# ШАГ 8.1: Валидация безопасности
./scripts/validate-security.sh

# ШАГ 8.2: Отчёт
./scripts/security-report.sh

# ШАГ 8.3: Проверка всех сервисов
systemctl status ssh docker ufw fail2ban auditd
systemctl status node-exporter prometheus alertmanager

# ШАГ 8.4: Проверка портов
ss -tlnp
```

---

## 📊 ЧЕК-ЛИСТ ЗАВЕРШЕНИЯ

```bash
# □ SSH ключ работает (проверено в новой сессии)
# □ UFW активен, порт 22 открыт
# □ Fail2ban запущен
# □ Sysctl применены, ip_forward = 1
# □ Docker работает, контейнеры запускаются
# □ Monitoring запущен, порты localhost
# □ Backup настроен, restic init выполнен
# □ Все сервисы активны
```

---

## 🚨 ПРОЦЕДУРЫ ВОССТАНОВЛЕНИЯ

### SSH Lockout

```bash
# 1. Войти через VPS web console
# 2. Восстановить SSH:
cp /var/backups/hardening/sshd_config.backup.* /etc/ssh/sshd_config
systemctl restart ssh

# 3. Проверить в новой сессии
```

### UFW Блокировка

```bash
# 1. Войти через VPS console
# 2. Отключить UFW:
ufw disable

# 3. Или сбросить:
ufw --force reset

# 4. Проверить правила:
ufw status verbose
```

### Docker Networking

```bash
# 1. Проверить IP forwarding:
sysctl net.ipv4.ip_forward  # Должен быть 1

# 2. Проверить UFW before.rules:
cat /etc/ufw/before.rules | grep -A 20 "docker"

# 3. Перезапустить Docker:
systemctl restart docker
```

---

## 📞 ПОЛЕЗНЫЕ КОМАНДЫ

```bash
# Проверка SSH
sshd -t
systemctl status ssh

# Проверка UFW
ufw status verbose
ufw status numbered

# Проверка Fail2ban
fail2ban-client status
fail2ban-client status sshd
fail2ban-client set sshd unbanip <IP>

# Проверка Docker
docker ps
docker run --rm hello-world

# Проверка Monitoring
systemctl status node-exporter prometheus alertmanager
curl http://localhost:9090/api/v1/targets | jq

# Проверка Backup
restic snapshots
restic check
```

---

## ✅ POST-DEPLOYMENT

После успешного развёртывания:

1. **Установить Coolify** (если ещё не установлен)
   ```bash
   curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
   ```

2. **Настроить Telegram алерты**
   - Следовать инструкциям из `08-monitoring-setup.sh`

3. **Настроить Cloudflare R2 для backup**
   - Следовать инструкциям из `09-backup-setup.sh`

4. **Проверить через 24 часа**
   - `restic snapshots` — backup выполнен
   - `fail2ban-client status` — есть баны атак
   - `systemctl status` — все сервисы активны

---

## 📖 ДОПОЛНИТЕЛЬНАЯ ДОКУМЕНТАЦИЯ

- [SIMULATION_REPORT.md](SIMULATION_REPORT.md) — Анализ рисков
- [SECURITY_FIXES.md](SECURITY_FIXES.md) — Применённые исправления
- [FIXES_SUMMARY.md](FIXES_SUMMARY.md) — Сводка исправлений
- [docs/SETUP.md](docs/SETUP.md) — Детальная инструкция
- [docs/BACKUP-RESTORE.md](docs/BACKUP-RESTORE.md) — Backup и восстановление

---

**Last Updated:** 2026-03-16  
**Version:** 1.0 (Production Ready)  
**Tested On:** Ubuntu 24.04 LTS
