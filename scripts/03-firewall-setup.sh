#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт настройки фаервола UFW
# Описание: Настройка и активация UFW с правилами для Docker и Caddy
#           с защитой от прямого доступа (только Cloudflare IP)
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/firewall-setup.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly UFW_BEFORE_SOURCE="${SCRIPT_DIR}/../configs/ufw/before.rules"
readonly UFW_USER_SOURCE="${SCRIPT_DIR}/../configs/ufw/user.rules"
readonly CLOUDFLARE_IPS_SOURCE="${SCRIPT_DIR}/../configs/ufw/cloudflare-ips.conf"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
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
# Создание директорий
# =============================================================================

create_directories() {
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"
    mkdir -p /var/log/server-hardening
}

# =============================================================================
# Резервное копирование текущих правил UFW
# =============================================================================

backup_ufw_config() {
    log_info "Создание резервной копии конфигурации UFW..."

    local backup_subdir="${BACKUP_DIR}/ufw.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_subdir}"

    # Копирование конфигов UFW
    if [[ -d /etc/ufw ]]; then
        cp -r /etc/ufw "${backup_subdir}/etc_ufw"
    fi

    # Сохранение текущих правил
    if command -v ufw &>/dev/null; then
        ufw status verbose > "${backup_subdir}/ufw_status.txt" 2>/dev/null || true
        ufw status numbered > "${backup_subdir}/ufw_numbered.txt" 2>/dev/null || true
    fi

    log_success "Резервная копия создана: ${backup_subdir}"
}

# =============================================================================
# Проверка установки UFW
# =============================================================================

check_ufw_installed() {
    if ! command -v ufw &>/dev/null; then
        log_error "UFW не установлен. Установите: apt-get install ufw"
        exit 1
    fi

    log_info "UFW установлен"
}

# =============================================================================
# Сброс UFW к состоянию по умолчанию
# =============================================================================

reset_ufw() {
    log_info "Сброс UFW к состоянию по умолчанию..."

    ufw --force reset

    log_success "UFW сброшен"
}

# =============================================================================
# Применение правил Docker compatibility
# =============================================================================

apply_docker_rules() {
    log_info "Применение правил для Docker networking..."

    # Копирование before.rules
    if [[ -f "${UFW_BEFORE_SOURCE}" ]]; then
        cp "${UFW_BEFORE_SOURCE}" /etc/ufw/before.rules
        chmod 644 /etc/ufw/before.rules
        log_info "before.rules применён"
    fi

    # Настройка sysctl для пересылки пакетов (требуется для Docker)
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        sysctl -w net.ipv4.ip_forward=1
        log_info "IP forwarding включён"
    fi

    log_success "Правила Docker применены"
}

# =============================================================================
# Настройка политик по умолчанию
# =============================================================================

set_default_policies() {
    log_info "Настройка политик по умолчанию..."

    # По умолчанию: запретить входящие, разрешить исходящие
    ufw default deny incoming
    ufw default allow outgoing
    ufw default deny forward

    log_success "Политики по умолчанию настроены"
}

# =============================================================================
# Добавление правил
# =============================================================================

add_rules() {
    local use_cloudflare="${1:-false}"
    
    log_info "Добавление правил фаервола..."

    if [[ "${use_cloudflare}" == "true" ]]; then
        log_info "Использование Cloudflare IP protection..."
        
        # Проверка наличия файла с Cloudflare IP
        if [[ -f "${CLOUDFLARE_IPS_SOURCE}" ]]; then
            log_info "Загрузка Cloudflare IP ranges из ${CLOUDFLARE_IPS_SOURCE}"
            # Правила Cloudflare уже включены в user.rules
        else
            log_warn "Файл Cloudflare IP не найден, используем стандартные правила"
        fi
    fi

    # SSH
    ufw allow 22/tcp comment 'SSH access'

    if [[ "${use_cloudflare}" == "false" ]]; then
        # HTTP (для Caddy и TLS) - только если не используем Cloudflare protection
        ufw allow 80/tcp comment 'HTTP - Caddy/TLS'

        # HTTPS
        ufw allow 443/tcp comment 'HTTPS - Caddy'
    else
        log_info "HTTP/HTTPS правила применяются из Cloudflare IP ranges"
        log_warn "Прямой доступ к портам 80/443 будет ЗАБЛОКИРОВАН"
        log_warn "Трафик разрешён ТОЛЬКО с IP адресов Cloudflare"
    fi

    # Логирование (уровень: low, medium, high, full)
    ufw logging medium

    log_success "Правила добавлены"
}

# =============================================================================
# Активация UFW
# =============================================================================

activate_ufw() {
    log_info "Активация UFW..."

    # Предупреждение
    echo ""
    echo -e "${YELLOW}ВНИМАНИЕ: Активация фаервола может разорвать SSH сессию${NC}"
    echo "Убедитесь, что порт 22 разрешён в правилах."
    echo ""

    # Активация с подтверждением
    ufw --force enable

    sleep 2

    if ufw status | grep -q "Status: active"; then
        log_success "UFW активирован"
    else
        log_error "Не удалось активировать UFW"
        return 1
    fi
}

# =============================================================================
# Проверка статуса
# =============================================================================

check_status() {
    log_info "Проверка статуса фаервола..."

    echo ""
    echo "=== Статус UFW ==="
    ufw status verbose

    echo ""
    echo "=== Правила UFW ==="
    ufw status numbered

    echo ""
    echo "=== Прослушиваемые порты ==="
    ss -tlnp | grep -E 'LISTEN' || true
    
    echo ""
    echo "=== Cloudflare Protection Status ==="
    if ufw status | grep -q "80.*173.245.48.0/20"; then
        log_success "Cloudflare IP protection ACTIVE"
    else
        log_warn "Cloudflare IP protection NOT DETECTED"
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    local skip_activate=false
    local use_cloudflare=false

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                check_root
                check_status
                exit 0
                ;;
            --dry-run)
                log_info "Режим проверки - без внесения изменений"
                skip_activate=true
                shift
                ;;
            --with-cloudflare)
                use_cloudflare=true
                shift
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --status          Показать статус фаервола"
                echo "  --dry-run         Проверка без активации"
                echo "  --with-cloudflare Включить Cloudflare IP protection"
                echo "  -h, --help        Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                exit 1
                ;;
        esac
    done

    echo "=============================================="
    echo "Настройка фаервола UFW"
    if [[ "${use_cloudflare}" == "true" ]]; then
        echo "с Cloudflare IP Protection"
    fi
    echo "=============================================="

    check_root
    create_directories
    check_ufw_installed
    backup_ufw_config
    reset_ufw
    apply_docker_rules
    set_default_policies
    add_rules "${use_cloudflare}"

    if [[ "${skip_activate}" == "false" ]]; then
        activate_ufw
    else
        log_info "Активация пропущена (dry-run)"
    fi

    check_status

    echo "=============================================="
    log_success "Настройка фаервола завершена!"
    echo "=============================================="
    echo ""
    
    if [[ "${use_cloudflare}" == "true" ]]; then
        echo "Cloudflare Protection: ВКЛЮЧЕНА"
        echo ""
        echo "Открытые порты:"
        echo "  - 22/tcp  (SSH) - ОТКРЫТ ДЛЯ ВСЕХ"
        echo "  - 80/tcp  (HTTP) - ТОЛЬКО Cloudflare IP"
        echo "  - 443/tcp (HTTPS) - ТОЛЬКО Cloudflare IP"
        echo ""
        echo "⚠️ ПРЯМОЙ ДОСТУП ЗАПРЕЩЁН:"
        echo "   Порты 80/443 принимают трафик ТОЛЬКО от Cloudflare"
        echo "   Прямой доступ к серверу заблокирован"
    else
        echo "Открытые порты:"
        echo "  - 22/tcp  (SSH)"
        echo "  - 80/tcp  (HTTP - Caddy/TLS)"
        echo "  - 443/tcp (HTTPS)"
    fi
    
    echo ""
    echo "PostgreSQL порт 5432 НЕ открыт (только локальный доступ)"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
    echo ""
    
    if [[ "${use_cloudflare}" == "true" ]]; then
        echo "=============================================="
        echo "Cloudflare IP Ranges"
        echo "=============================================="
        echo ""
        echo "Для обновления IP диапазонов Cloudflare:"
        echo "  ./scripts/update-cloudflare-ips.sh"
        echo ""
        echo "Источник: https://www.cloudflare.com/ips/"
    fi
}

# Запуск основной функции
main "$@"
