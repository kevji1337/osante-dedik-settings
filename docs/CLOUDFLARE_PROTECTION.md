# 🛡️ Cloudflare Origin Protection Guide

**Защита origin сервера от прямого доступа**

---

## 📋 Overview

Эта конфигурация обеспечивает защиту origin-сервера от прямого доступа, разрешая HTTP/HTTPS трафик **ТОЛЬКО** с IP-адресов Cloudflare.

### Проблема

Без этой защиты злоумышленник может:
1. Узнать реальный IP сервера (через DNS history, email headers и т.д.)
2. Подключиться напрямую к серверу в обход Cloudflare
3. Обойти WAF и DDoS защиту Cloudflare

### Решение

Фаервол разрешает подключения на порты 80/443 **ТОЛЬКО** с официальных IP диапазонов Cloudflare.

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                         Internet                                │
│                             │                                   │
│                      Cloudflare (WAF)                           │
│                     IP: 173.245.48.0/20                         │
│                     IP: 103.21.244.0/22                         │
│                     ... (22 ranges)                             │
└─────────────────────────────┼───────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Ubuntu 24.04 LTS │
                    │   UFW Firewall    │
                    │                   │
                    │  Port 80:         │
                    │  ✓ Cloudflare IP  │
                    │  ✗ Direct Access  │
                    │                   │
                    │  Port 443:        │
                    │  ✓ Cloudflare IP  │
                    │  ✗ Direct Access  │
                    │                   │
                    │  Port 22 (SSH):   │
                    │  ✓ Open for admin │
                    └───────────────────┘
```

---

## 🔧 Installation

### Вариант 1: Fresh Installation

```bash
# При первоначальной настройке используйте флаг --with-cloudflare
./scripts/03-firewall-setup.sh --with-cloudflare
```

### Вариант 2: Существующая Установка

```bash
# 1. Обновить правила UFW
cp configs/ufw/user.rules /etc/ufw/user.rules

# 2. Перезагрузить UFW
ufw reload

# 3. Проверить статус
ufw status verbose
```

---

## 📊 Cloudflare IP Ranges

### IPv4 Ranges (15 диапазонов)

```
173.245.48.0/20     103.21.244.0/22     103.22.200.0/22
103.31.4.0/22       141.101.64.0/18     108.162.192.0/18
190.93.240.0/20     188.114.96.0/20     197.234.240.0/22
198.41.128.0/17     162.158.0.0/15      104.16.0.0/13
104.24.0.0/14       172.64.0.0/13       131.0.72.0/22
```

### IPv6 Ranges (7 диапазонов)

```
2400:cb00::/32      2606:4700::/32      2803:f800::/32
2405:b500::/32      2405:8100::/32      2a06:98c0::/29
2c0f:f248::/32
```

**Источник:** https://www.cloudflare.com/ips/

---

## ✅ Verification

### Проверка правил UFW

```bash
# Проверить что Cloudflare IP добавлены
ufw status numbered | grep "173.245.48.0"

# Проверить что порты 80/443 заблокированы для остальных
ufw status numbered | grep -E "80.*DROP|443.*DROP"
```

### Проверка что Cloudflare может подключиться

```bash
# Симуляция подключения с Cloudflare IP
curl -H "CF-Connecting-IP: 173.245.48.1" http://localhost/

# Проверка заголовков Cloudflare
curl -I https://your-domain.com
# Должен быть заголовок: CF-Ray: ...
```

### Проверка что прямой доступ заблокирован

```bash
# С другого сервера (не Cloudflare) попробовать подключиться
telnet your-server-ip 80
# Должно быть: Connection refused/timed out

telnet your-server-ip 443
# Должно быть: Connection refused/timed out
```

---

## 🔄 Updating Cloudflare IP Ranges

Cloudflare может обновлять свои IP диапазоны. Автоматизируйте обновление:

### Автоматическое Обновление

```bash
# Запустить скрипт обновления
./scripts/update-cloudflare-ips.sh

# Применить новые правила
cp configs/ufw/cloudflare-ips.conf /etc/ufw/cloudflare-ips.conf
ufw reload
```

### Cron для Автоматического Обновления

```bash
# Добавить в cron (еженедельно)
0 3 * * 0 /opt/server-hardening/scripts/update-cloudflare-ips.sh >> /var/log/cloudflare-ips-update.log 2>&1
```

### Ручное Обновление

```bash
# 1. Загрузить актуальные диапазоны
curl https://www.cloudflare.com/ips-v4 > /tmp/cf-ipv4.txt
curl https://www.cloudflare.com/ips-v6 > /tmp/cf-ipv6.txt

# 2. Сравнить с текущими
diff /tmp/cf-ipv4.txt configs/ufw/cloudflare-ips.conf

# 3. Если есть изменения - обновить правила
./scripts/update-cloudflare-ips.sh
```

---

## 🔍 Troubleshooting

### Проблема: Cloudflare не может подключиться

**Симптомы:**
- Cloudflare показывает ошибку 521/522
- Сайт не доступен

**Проверка:**
```bash
# Проверить правила UFW
ufw status verbose

# Проверить логи UFW
tail -f /var/log/ufw.log | grep "DPT=80\|DPT=443"
```

**Решение:**
```bash
# Убедиться что Cloudflare IP добавлены
grep "173.245.48.0" /etc/ufw/user.rules

# Перезагрузить UFW
ufw reload

# Проверить что Caddy слушает порты
ss -tlnp | grep -E ":80|:443"
```

---

### Проблема: TLS сертификаты не обновляются

**Симптомы:**
- ACME challenge не проходит
- Certificates не обновляются

**Причина:**
- ACME challenge требует доступа к порту 80

**Решение:**
```bash
# Cloudflare IP уже включают доступ к порту 80
# Проверить что правила применены:
ufw status numbered | grep "80.*ACCEPT"

# Если используется HTTP-01 challenge через Cloudflare -
# Cloudflare сам проксирует запрос к вашему серверу
```

---

### Проблема: SSH заблокирован

**Симптомы:**
- Не могу подключиться по SSH после применения правил

**Причина:**
- SSH порт (22) должен быть ОТДЕЛЬНО разрешён

**Проверка:**
```bash
ufw status | grep "22/tcp"
# Должно быть: 22/tcp ALLOW
```

**Решение:**
```bash
# Добавить правило для SSH
ufw allow 22/tcp comment 'SSH access'
ufw reload
```

---

## 🔒 Security Considerations

### Что защищает эта конфигурация

✅ **Прямой доступ к серверу** — заблокирован  
✅ **DDoS атаки мимо Cloudflare** — смягчены  
✅ **Обход WAF** — невозможен  
✅ **Сканирование портов** — порты 80/443 скрыты  

### Что НЕ защищает

❌ **SSH брутфорс** — используйте Fail2ban  
❌ **Уязвимости в приложениях** — используйте WAF  
❌ **DDoS на SSH порт** — используйте non-standard port  
❌ **Cloudflare компрометация** — маловероятно  

### Рекомендации

1. **Мониторинг логов UFW:**
   ```bash
   tail -f /var/log/ufw.log | grep "BLOCK"
   ```

2. **Alerting на подозрительную активность:**
   ```bash
   # Добавить в fail2ban
   # Мониторинг ufw.log на предмет сканирования
   ```

3. **Регулярное обновление IP диапазонов:**
   ```bash
   # Еженедельное обновление
   ./scripts/update-cloudflare-ips.sh
   ```

---

## 📊 Compatibility

| Компонент | Совместимость | Примечание |
|-----------|--------------|------------|
| Docker networking | ✅ PASS | Правила не влияют на Docker |
| Coolify deployments | ✅ PASS | Coolify работает через Cloudflare |
| Caddy reverse proxy | ✅ PASS | Caddy получает трафик от Cloudflare |
| TLS certificate issuance | ✅ PASS | ACME challenge работает через Cloudflare |
| Cloudflare proxy | ✅ PASS | Официальные IP диапазоны |
| SSH access | ✅ PASS | Порт 22 открыт |

---

## 🚀 Quick Commands

```bash
# Проверка статуса
ufw status verbose

# Проверка Cloudflare protection
ufw status | grep "173.245.48.0"

# Обновление IP диапазонов
./scripts/update-cloudflare-ips.sh

# Перезагрузка правил
ufw reload

# Просмотр заблокированных подключений
ufw status numbered | grep DROP

# Логи UFW
tail -f /var/log/ufw.log
```

---

## 📖 Additional Resources

- [Cloudflare IP Ranges](https://www.cloudflare.com/ips/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW)
- [Caddy Cloudflare Setup](https://caddy.community/t/cloudflare-setup/)

---

**Last Updated:** 2026-03-16  
**Version:** 1.0  
**Status:** ✅ Production Ready
