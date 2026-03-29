#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Cloudflare Tunnel Setup Script
# Описание: Установка и настройка Cloudflare Tunnel через Docker
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/cloudflared-tunnel.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly COMPOSE_FILE="${SCRIPT_DIR}/../docker-compose.cloudflared.yml"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# =============================================================================
# Функции логирования
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# =============================================================================
# Проверка прав root
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен выполняться от root"
        exit 1
    fi
}

# =============================================================================
# Проверка Docker
# =============================================================================

check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker не установлен. Установите Docker перед запуском."
        exit 1
    fi

    if ! systemctl is-active --quiet docker; then
        log_error "Docker сервис не активен"
        exit 1
    fi

    log_info "Docker установлен и активен"
}

# =============================================================================
# Создание директорий
# =============================================================================

create_directories() {
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"
    mkdir -p /var/log/server-hardening
    mkdir -p /opt/cloudflared/config
    log_success "Директории созданы"
}

# =============================================================================
# Запрос токена у пользователя
# =============================================================================

request_tunnel_token() {
    echo ""
    echo -e "${BLUE}=============================================="
    echo "Cloudflare Tunnel Setup"
    echo "==============================================${NC}"
    echo ""
    echo "Для создания туннеля:"
    echo "1. Зайдите в Cloudflare Dashboard: https://dash.cloudflare.com"
    echo "2. Перейдите в: Zero Trust → Networks → Tunnels"
    echo "3. Нажмите 'Create a tunnel'"
    echo "4. Введите имя туннеля (например: osante-server)"
    echo "5. Выберите Docker как среду запуска"
    echo "6. Скопируйте токен из команды"
    echo ""
    echo "Токен выглядит так:"
    echo "eyJhIjoi... (длинная строка)"
    echo ""
    
    read -p "Введите Cloudflare Tunnel Token: " TUNNEL_TOKEN
    
    if [[ -z "${TUNNEL_TOKEN}" ]]; then
        log_error "Токен не введён"
        exit 1
    fi
    
    # Валидация формата токена (начинается с eyJ)
    if [[ ! "${TUNNEL_TOKEN}" =~ ^eyJ ]]; then
        log_error "Неверный формат токена. Токен должен начинаться с 'eyJ'"
        exit 1
    fi
    
    log_info "Токен получен"
    echo "${TUNNEL_TOKEN}"
}

# =============================================================================
# Создание docker-compose.cloudflared.yml
# =============================================================================

create_compose_file() {
    local tunnel_token="$1"
    
    log_info "Создание docker-compose файла..."
    
    cat > "${COMPOSE_FILE}" << EOF
# =============================================================================
# Docker Compose для Cloudflare Tunnel
# Описание: Cloudflared туннель для безопасного доступа к серверу
# =============================================================================

version: '3.8'

services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-tunnel
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token ${tunnel_token}
    networks:
      - cloudflared
    volumes:
      - cloudflared-config:/etc/cloudflared
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "cloudflared", "version"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

networks:
  cloudflared:
    driver: bridge

volumes:
  cloudflared-config:
    driver: local
EOF

    chmod 644 "${COMPOSE_FILE}"
    log_success "docker-compose.cloudflared.yml создан"
}

# =============================================================================
# Запуск Cloudflare Tunnel
# =============================================================================

start_tunnel() {
    log_info "Запуск Cloudflare Tunnel..."
    
    cd "$(dirname "${COMPOSE_FILE}")"
    
    # Проверка что файл существует
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        log_error "docker-compose файл не найден: ${COMPOSE_FILE}"
        exit 1
    fi
    
    # Запуск
    docker-compose -f "${COMPOSE_FILE}" up -d
    
    sleep 5
    
    # Проверка статуса
    if docker ps | grep -q cloudflared-tunnel; then
        log_success "Cloudflare Tunnel запущен"
    else
        log_error "Не удалось запустить Cloudflare Tunnel"
        docker logs cloudflared-tunnel 2>&1 | tail -20
        exit 1
    fi
}

# =============================================================================
# Проверка статуса
# =============================================================================

check_status() {
    echo ""
    echo "=== Cloudflare Tunnel Status ==="
    
    if docker ps | grep -q cloudflared-tunnel; then
        log_success "Cloudflare Tunnel активен"
        docker ps --filter name=cloudflared-tunnel --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        log_warn "Cloudflare Tunnel не активен"
    fi
    
    echo ""
    echo "=== Последние логи ==="
    docker logs cloudflared-tunnel --tail 20 2>&1
}

# =============================================================================
# Инструкция по настройке маршрутов
# =============================================================================

print_routing_instructions() {
    echo ""
    echo -e "${BLUE}=============================================="
    echo "Cloudflare Tunnel настроен!"
    echo "==============================================${NC}"
    echo ""
    echo "Следующие шаги:"
    echo ""
    echo "1. В Cloudflare Dashboard (Zero Trust → Networks → Tunnels):"
    echo "   - Нажмите на ваш туннель"
    echo "   - Нажмите 'Add a public hostname'"
    echo ""
    echo "2. Настройте маршруты:"
    echo ""
    echo "   ┌─────────────┬──────────────┬──────────────┬────────────┐"
    echo "   │ Subdomain   │ Domain       │ Service      │ Type       │"
    echo "   ├─────────────┼──────────────┼──────────────┼────────────┤"
    echo "   │ @           │ your.com     │ http://caddy │ HTTP       │"
    echo "   │ www         │ your.com     │ http://caddy │ HTTP       │"
    echo "   │ api         │ your.com     │ http://caddy │ HTTP       │"
    echo "   └─────────────┴──────────────┴──────────────┴────────────┘"
    echo ""
    echo "3. Для каждого маршрута:"
    echo "   - Subdomain: @ (для корня) или www, api и т.д."
    echo "   - Domain: ваш домен (например: osanteclient.xyz)"
    echo "   - Service: http://caddy (Caddy reverse proxy)"
    echo "   - Type: HTTP"
    echo ""
    echo "4. Сохраните маршрут"
    echo ""
    echo "Важно:"
    echo "  - Cloudflare Tunnel заменяет необходимость открывать порты 80/443"
    echo "  - Трафик идёт через Cloudflare сеть (защищено)"
    echo "  - IP сервера остаётся скрытым"
    echo ""
    echo "Полезные команды:"
    echo "  docker logs cloudflared-tunnel -f     # Логи туннеля"
    echo "  docker-compose -f docker-compose.cloudflared.yml down  # Остановить"
    echo "  docker-compose -f docker-compose.cloudflared.yml up -d # Запустить"
    echo "  docker ps | grep cloudflared          # Статус"
    echo ""
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                check_root
                check_status
                exit 0
                ;;
            --token)
                TUNNEL_TOKEN="$2"
                shift 2
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --status      Показать статус туннеля"
                echo "  --token <t>   Использовать указанный токен"
                echo "  -h, --help    Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "Cloudflare Tunnel Installation (Docker)"
    echo "=============================================="

    check_root
    check_docker
    create_directories

    # Получение токена
    if [[ -z "${TUNNEL_TOKEN:-}" ]]; then
        TUNNEL_TOKEN=$(request_tunnel_token)
    fi

    # Создание compose файла и запуск
    create_compose_file "${TUNNEL_TOKEN}"
    start_tunnel
    check_status
    print_routing_instructions

    log_success "Cloudflare Tunnel установка завершена!"
}

# Запуск основной функции
main "$@"
