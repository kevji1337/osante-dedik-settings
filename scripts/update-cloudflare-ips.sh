#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Cloudflare IP Ranges Update Script
# Описание: Автоматическая загрузка актуальных IP диапазонов Cloudflare
# Использование: ./scripts/update-cloudflare-ips.sh
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly CLOUDFLARE_IPV4_URL="https://www.cloudflare.com/ips-v4"
readonly CLOUDFLARE_IPV6_URL="https://www.cloudflare.com/ips-v6"
readonly OUTPUT_FILE="${SCRIPT_DIR}/../configs/ufw/cloudflare-ips.conf"
readonly LOG_FILE="/var/log/server-hardening/cloudflare-ips-update.log"

# Цвета для вывода
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log() {
    local level="$1"
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

mkdir -p "$(dirname "${LOG_FILE}")"

log_info "Загрузка актуальных IP диапазонов Cloudflare..."

# Загрузка IPv4 диапазонов
log_info "Загрузка IPv4 диапазонов..."
IPV4_RANGES=$(curl -s --max-time 30 "${CLOUDFLARE_IPV4_URL}")

if [[ -z "${IPV4_RANGES}" ]]; then
    log_error "Не удалось загрузить IPv4 диапазоны"
    exit 1
fi

# Загрузка IPv6 диапазонов
log_info "Загрузка IPv6 диапазонов..."
IPV6_RANGES=$(curl -s --max-time 30 "${CLOUDFLARE_IPV6_URL}")

if [[ -z "${IPV6_RANGES}" ]]; then
    log_error "Не удалось загрузить IPv6 диапазоны"
    exit 1
fi

# Создание конфига
cat > "${OUTPUT_FILE}" << 'EOF'
# =============================================================================
# Cloudflare IP Ranges - UFW Configuration
# Описание: Разрешить HTTP/HTTPS только с IP адресов Cloudflare
# Обновлено: AUTO_UPDATED
# Источник: https://www.cloudflare.com/ips/
# =============================================================================

# =============================================================================
# CLOUDFLARE IPv4 RANGES
# =============================================================================
EOF

# Добавление IPv4 диапазонов
echo "${IPV4_RANGES}" | while read -r cidr; do
    if [[ -n "${cidr}" ]]; then
        echo "-A ufw-user-input -p tcp -s ${cidr} --dport 80 -j ACCEPT" >> "${OUTPUT_FILE}"
        echo "-A ufw-user-input -p tcp -s ${cidr} --dport 443 -j ACCEPT" >> "${OUTPUT_FILE}"
    fi
done

# Добавление IPv6 диапазонов
echo "${IPV6_RANGES}" | while read -r cidr; do
    if [[ -n "${cidr}" ]]; then
        echo "-A ufw-user-input -p tcp -s ${cidr} --dport 80 -j ACCEPT" >> "${OUTPUT_FILE}"
        echo "-A ufw-user-input -p tcp -s ${cidr} --dport 443 -j ACCEPT" >> "${OUTPUT_FILE}"
    fi
done

# Добавление закрывающих правил (блокировка прямого доступа)
cat >> "${OUTPUT_FILE}" << 'EOF'

# =============================================================================
# BLOCK DIRECT ACCESS (Not from Cloudflare)
# =============================================================================
# Эти правила блокируют прямой доступ к портам 80/443
# Трафик должен идти только через Cloudflare

# Блокировать весь остальной HTTP трафик
-A ufw-user-input -p tcp --dport 80 -j DROP

# Блокировать весь остальной HTTPS трафик
-A ufw-user-input -p tcp --dport 443 -j DROP

# =============================================================================
# END OF CLOUDFLARE RULES
# =============================================================================
EOF

# Обновление даты в файле
sed -i "s/AUTO_UPDATED/$(date '+%Y-%m-%d %H:%M:%S')/" "${OUTPUT_FILE}"

# Подсчёт количества правил
IPV4_COUNT=$(echo "${IPV4_RANGES}" | grep -c '.' || echo 0)
IPV6_COUNT=$(echo "${IPV6_RANGES}" | grep -c '.' || echo 0)

log_success "Конфигурация обновлена!"
log_info "IPv4 диапазонов: ${IPV4_COUNT}"
log_info "IPv6 диапазонов: ${IPV6_COUNT}"
log_info "Файл сохранён: ${OUTPUT_FILE}"

echo ""
echo "=============================================="
echo "Cloudflare IP Ranges Updated"
echo "=============================================="
echo ""
echo "Для применения правил выполните:"
echo "  cp ${OUTPUT_FILE} /etc/ufw/cloudflare-ips.conf"
echo "  ufw reload"
echo ""
echo "Или запустите firewall скрипт:"
echo "  ./scripts/03-firewall-setup.sh --with-cloudflare"
echo ""
