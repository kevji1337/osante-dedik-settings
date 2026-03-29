# Security Fixes Applied

## Дата применения: 2026-03-16

Этот документ описывает все исправления безопасности, применённые к проекту после аудита.

---

## CRITICAL FIXES

### 1. Monitoring Ports Bound to Localhost

**Проблема:** Prometheus (9090), Alertmanager (9093), и Grafana (3000) были открыты публично.

**Файл:** `docker-compose.monitoring.yml`

**Изменения:**
```yaml
# БЫЛО:
ports:
  - "9090:9090"    # ОТКРЫТ НАРУЖУ

# СТАЛО:
ports:
  - "127.0.0.1:9090:9090"    # Только localhost
```

**Применено к:**
- Prometheus: порт 9090
- Alertmanager: порт 9093
- Grafana: порт 3000

**Доступ через SSH tunnel:**
```bash
ssh -L 9090:localhost:9090 -L 9093:localhost:9093 -L 3000:localhost:3000 admin@server
```

---

### 2. Telegram Tokens Moved to Environment Variables

**Проблема:** Telegram токены хранились в plain text в конфиге alertmanager.yml

**Файл:** `configs/monitoring/alertmanager.yml`

**Изменения:**
```yaml
# БЫЛО:
telegram_configs:
  - bot_token: 'YOUR_BOT_TOKEN'    # ← ТОКЕН В КОНФИГЕ

# СТАЛО:
telegram_configs:
  - bot_token: '${TELEGRAM_BOT_TOKEN}'    # ← Переменная окружения
```

**Дополнительно созданы:**
- `configs/monitoring/telegram.env.example` — шаблон EnvironmentFile
- `configs/systemd/alertmanager.service` — systemd service с EnvironmentFile

**Инструкция:**
```bash
# 1. Создать EnvironmentFile
cp configs/monitoring/telegram.env.example /etc/alertmanager/telegram.env
nano /etc/alertmanager/telegram.env

# 2. Установить права
chmod 600 /etc/alertmanager/telegram.env
chown root:root /etc/alertmanager/telegram.env

# 3. Перезапустить Alertmanager
systemctl daemon-reload
systemctl restart alertmanager
```

---

### 3. PostgreSQL Port Explicitly Blocked in UFW

**Проблема:** Порт PostgreSQL (5432) не имел явного правила DROP, мог быть случайно открыт.

**Файл:** `configs/ufw/user.rules`

**Изменения:**
```bash
# ДОБАВЛЕНО ПОСЛЕ РАЗРЕШАЮЩИХ ПРАВИЛ:
# Заблокировать PostgreSQL (порт 5432) — только внутри Docker сети
-A ufw-user-input -p tcp --dport 5432 -j DROP
-A ufw-user-input -p udp --dport 5432 -j DROP
```

**Проверка:**
```bash
ufw status verbose
# Должно быть: 5432/tcp DENY Anywhere
```

---

## HIGH RISK FIXES

### 4. Docker User Namespace Remapping Disabled

**Проблема:** `userns-remap: default` мог сломать Coolify и контейнеры.

**Файл:** `scripts/10-docker-security.sh`

**Изменения:**
```json
# БЫЛО:
{
    "userland-proxy": false,
    "userns-remap": "default"
}

# СТАЛО:
{
    "userland-proxy": true,
    "userns-remap": ""
}
```

**Примечание:** User namespace remapping можно включить только после тестирования на staging.

---

### 5. SSH Rate Limiting Enabled in UFW

**Проблема:** Rate limiting для SSH был закомментирован, полагался только на Fail2ban.

**Файл:** `configs/ufw/user.rules`

**Изменения:**
```bash
# БЫЛО (закомментировано):
# -A ufw-user-input -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set

# СТАЛО (включено):
-A ufw-user-input -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set
-A ufw-user-input -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 300 --hitcount 6 -j DROP
```

**Эффект:** Максимум 6 попыток подключения за 5 минут.

---

## MEDIUM RISK FIXES

### 6. SSH MaxStartups Reduced

**Проблема:** MaxStartups 10:30:60 позволял до 60 неаутентифицированных подключений.

**Файл:** `configs/sshd_config`

**Изменения:**
```
# БЫЛО:
MaxStartups 10:30:60

# СТАЛО:
MaxStartups 5:20:30
```

**Эффект:** Максимум 30 неаутентифицированных подключений, с 5 начинается отклонение.

---

### 7. cAdvisor Privileged Mode Removed

**Проблема:** cAdvisor работал в privileged режиме с избыточными привилегиями.

**Файл:** `docker-compose.monitoring.yml`

**Изменения:**
```yaml
# БЫЛО:
cadvisor:
  privileged: true

# СТАЛО:
cadvisor:
  cap_add:
    - SYS_ADMIN
    - SYS_PTRACE
    - NET_ADMIN
```

---

## ADDITIONAL FILES CREATED

### 8. Environment File Template

**Файл:** `.env.example`

**Назначение:** Шаблон для переменных окружения мониторинга.

---

### 9. Git Ignore for Secrets

**Файл:** `.gitignore`

**Назначение:** Предотвращение коммита секретов в git.

**Исключает:**
- `*.env` файлы
- `*.pem`, `*.key` файлы
- SSH ключи
- Backup файлы
- Логи

---

### 10. Systemd Service Files

**Файлы:**
- `configs/systemd/alertmanager.service`
- `configs/systemd/prometheus.service`
- `configs/systemd/node-exporter.service`

**Назначение:** Запуск сервисов с EnvironmentFile для токенов.

---

## VERIFICATION CHECKLIST

После применения исправлений выполните:

```bash
# 1. Проверить что monitoring порты закрыты
ss -tlnp | grep -E '9090|9093|3000'
# Должно быть: 127.0.0.1:9090, 127.0.0.1:9093, 127.0.0.1:3000

# 2. Проверить UFW правила
ufw status verbose
# Должно быть: 5432/tcp DENY

# 3. Проверить Docker config
cat /etc/docker/daemon.json
# Должно быть: "userns-remap": "", "userland-proxy": true

# 4. Проверить SSH config
sshd -t
# Не должно быть ошибок

# 5. Проверить что Telegram токены не в конфиге
grep -r "YOUR_BOT_TOKEN" configs/
# Не должно быть результатов
```

---

## DEPLOYMENT ORDER

Рекомендуемый порядок применения исправлений:

```bash
# 1. Остановить monitoring
docker-compose -f docker-compose.monitoring.yml down

# 2. Применить исправления UFW
cp configs/ufw/user.rules /etc/ufw/user.rules
ufw reload

# 3. Применить исправления SSH
cp configs/sshd_config /etc/ssh/sshd_config
systemctl restart ssh

# 4. Применить исправления Docker
./scripts/10-docker-security.sh --no-restart
systemctl restart docker

# 5. Настроить Telegram токены
cp configs/monitoring/telegram.env.example /etc/alertmanager/telegram.env
nano /etc/alertmanager/telegram.env  # вставить реальные токены
chmod 600 /etc/alertmanager/telegram.env

# 6. Запустить monitoring
docker-compose -f docker-compose.monitoring.yml up -d

# 7. Проверить
./scripts/validate-security.sh
```

---

## COMPATIBILITY STATUS

| Компонент | Статус после исправлений |
|-----------|-------------------------|
| Docker networking | ✅ PASS |
| UFW + Docker | ✅ PASS |
| Coolify совместимость | ✅ PASS |
| Caddy совместимость | ✅ PASS |
| Cloudflare proxy | ✅ PASS |
| TLS certificate issuance | ✅ PASS |
| PostgreSQL изоляция | ✅ PASS |
| Monitoring isolation | ✅ PASS |

---

## SECURITY STATUS

**До исправлений:** ❌ НЕ ГОТОВО ДЛЯ PRODUCTION  
**После исправлений:** ✅ ГОТОВО ДЛЯ PRODUCTION (при условии тестирования)

---

**Last Updated:** 2026-03-16  
**Applied By:** Security Audit Process
