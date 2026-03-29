# 🚇 Cloudflare Tunnel Setup Guide

**Настройка безопасного туннеля от Cloudflare**

---

## 📋 Overview

Cloudflare Tunnel — это безопасный способ предоставления доступа к серверу без открытия портов и без публичного IP.

### Преимущества

| Преимущество | Описание |
|-------------|----------|
| ✅ Скрытый IP | IP сервера не виден публике |
| ✅ Без открытых портов | Не нужно открывать 80/443 в фаерволе |
| ✅ DDoS защита | Защита на L3/L4 уровне |
| ✅ Работает за NAT | Не нужен публичный IP |
| ✅ Автоматический TLS | Cloudflare управляет сертификатами |

### Архитектура

```
Internet → Cloudflare Edge → Cloudflare Tunnel → Caddy → Docker Containers
```

---

## 🚀 Быстрая установка

### Шаг 1: Запустить скрипт установки

```bash
cd /opt/server-hardening
chmod +x scripts/11-cloudflare-tunnel.sh
./scripts/11-cloudflare-tunnel.sh
```

### Шаг 2: Ввести токен

Скрипт попросит ввести токен из Cloudflare Dashboard.

### Шаг 3: Настроить маршруты

В Cloudflare Dashboard добавить public hostnames.

---

## 📖 Подробная инструкция

### 1. Создание туннеля в Cloudflare

1. Зайдите в [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Перейдите в **Zero Trust** → **Networks** → **Tunnels**
3. Нажмите **Create a tunnel**
4. Введите имя туннеля (например: `osante-server`)
5. Нажмите **Save tunnel**
6. Выберите **Docker** как среду запуска
7. Скопируйте токен из команды (длинная строка после `--token`)

### 2. Установка на сервер

```bash
# Запустить скрипт
./scripts/11-cloudflare-tunnel.sh

# Вставить токен когда попросит
# Нажать Enter
```

### 3. Настройка маршрутов

В Cloudflare Dashboard (Zero Trust → Networks → Tunnels):

1. Нажмите на ваш туннель
2. Нажмите **Add a public hostname**
3. Заполните:

```
┌─────────────┬──────────────┬──────────────┬────────────┐
│ Subdomain   │ Domain       │ Service      │ Type       │
├─────────────┼──────────────┼──────────────┼────────────┤
│ @           │ osante.com   │ http://caddy │ HTTP       │
│ www         │ osante.com   │ http://caddy │ HTTP       │
│ api         │ osante.com   │ http://caddy │ HTTP       │
└─────────────┴──────────────┴──────────────┴────────────┘
```

4. Для каждого маршрута:
   - **Subdomain**: `@` (для корня) или `www`, `api` и т.д.
   - **Domain**: ваш домен (например: osanteclient.xyz)
   - **Service**: `http://caddy` (Caddy reverse proxy)
   - **Type**: HTTP
5. Сохраните маршрут

---

## 🔧 Управление туннелем

### Проверка статуса

```bash
# Через скрипт
./scripts/11-cloudflare-tunnel.sh --status

# Или через Docker
docker ps | grep cloudflared
docker logs cloudflared-tunnel --tail 50
```

### Остановить туннель

```bash
docker-compose -f docker-compose.cloudflared.yml down
```

### Запустить туннель

```bash
docker-compose -f docker-compose.cloudflared.yml up -d
```

### Перезапустить туннель

```bash
docker-compose -f docker-compose.cloudflared.yml restart
```

### Обновить cloudflared

```bash
docker-compose -f docker-compose.cloudflared.yml pull
docker-compose -f docker-compose.cloudflared.yml up -d
```

---

## 📊 Логи и мониторинг

### Просмотр логов

```bash
# Последние 50 строк
docker logs cloudflared-tunnel --tail 50

# В реальном времени
docker logs cloudflared-tunnel -f

# Через journalctl (если используется systemd)
journalctl -u cloudflared -f
```

### Health check

```bash
docker inspect cloudflared-tunnel --format='{{.State.Health.Status}}'
```

---

## 🔐 Безопасность

### Что защищает туннель

| Угроза | Защита |
|--------|--------|
| DDoS атаки | Cloudflare защита |
| Сканирование портов | Порты не открыты |
| IP enumeration | IP скрыт |
| MITM атаки | TLS шифрование |

### Рекомендации

1. **Не открывайте порты 80/443** если используете туннель
2. **Обновите UFW правила** — удалите Cloudflare IP если не нужны
3. **Мониторьте логи** — `docker logs cloudflared-tunnel -f`
4. **Ротируйте токен** — каждые 90 дней в Cloudflare Dashboard

---

## 🔄 Миграция с Public IP на Tunnel

### Шаг 1: Установить туннель

```bash
./scripts/11-cloudflare-tunnel.sh
```

### Шаг 2: Настроить маршруты

В Cloudflare Dashboard добавить все домены.

### Шаг 3: Проверить работу

```bash
curl https://your-domain.com
# Должен работать через туннель
```

### Шаг 4: Закрыть порты (опционально)

```bash
# Удалить правила для 80/443 из UFW
ufw delete allow 80/tcp
ufw delete allow 443/tcp
```

### Шаг 5: Обновить Cloudflare DNS

- Убедитесь что DNS записи используют Cloudflare Proxy (оранжевый значок)
- Или удалите A записи (туннель не требует DNS)

---

## ⚠️ Troubleshooting

### Туннель не подключается

```bash
# Проверить логи
docker logs cloudflared-tunnel

# Проверить токен
docker inspect cloudflared-tunnel | grep token

# Пересоздать с новым токеном
./scripts/11-cloudflare-tunnel.sh
```

### Маршруты не работают

1. Проверьте что туннель активен: `docker ps | grep cloudflared`
2. Проверьте Service в маршруте: должен быть `http://caddy`
3. Проверьте что Caddy слушает правильный порт

### Туннель часто отключается

```bash
# Проверить использование памяти
docker stats cloudflared-tunnel

# Увеличить restart policy
# В docker-compose.cloudflared.yml: restart: always
```

---

## 📖 Дополнительные ресурсы

- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [cloudflared GitHub](https://github.com/cloudflare/cloudflared)
- [Zero Trust Dashboard](https://one.dash.cloudflare.com)

---

**Last Updated:** 2026-03-16  
**Version:** 1.0  
**Status:** ✅ Production Ready
