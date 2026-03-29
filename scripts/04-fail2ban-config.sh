#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт настройки Fail2ban
# Описание: Установка и конфигурация Fail2ban для защиты SSH
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/fail2ban-setup.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly JAIL_LOCAL_SOURCE="${SCRIPT_DIR}/../configs/fail2ban/jail.local"
readonly FILTER_CADDY_SOURCE="${SCRIPT_DIR}/../configs/fail2ban/filter.d/caddy.conf"

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
    mkdir -p /var/run/fail2ban
}

# =============================================================================
# Проверка установки Fail2ban
# =============================================================================

check_fail2ban_installed() {
    if ! command -v fail2ban-server &>/dev/null; then
        log_error "Fail2ban не установлен. Установите: apt-get install fail2ban"
        exit 1
    fi
    
    log_info "Fail2ban установлен"
}

# =============================================================================
# Резервное копирование конфигурации
# =============================================================================

backup_config() {
    log_info "Создание резервной копии конфигурации Fail2ban..."
    
    local backup_subdir="${BACKUP_DIR}/fail2ban.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${backup_subdir}"
    
    if [[ -d /etc/fail2ban ]]; then
        cp -r /etc/fail2ban "${backup_subdir}/etc_fail2ban"
    fi
    
    log_success "Резервная копия создана: ${backup_subdir}"
}

# =============================================================================
# Применение конфигурации
# =============================================================================

apply_config() {
    log_info "Применение конфигурации Fail2ban..."
    
    # Создание директории если не существует
    mkdir -p /etc/fail2ban
    
    # Копирование jail.local
    if [[ -f "${JAIL_LOCAL_SOURCE}" ]]; then
        cp "${JAIL_LOCAL_SOURCE}" /etc/fail2ban/jail.local
        chmod 644 /etc/fail2ban/jail.local
        log_info "jail.local применён"
    fi
    
    # Копирование фильтра Caddy
    if [[ -f "${FILTER_CADDY_SOURCE}" ]]; then
        cp "${FILTER_CADDY_SOURCE}" /etc/fail2ban/filter.d/caddy.conf
        chmod 644 /etc/fail2ban/filter.d/caddy.conf
        log_info "Фильтр Caddy применён"
    fi
    
    log_success "Конфигурация применена"
}

# =============================================================================
# Перезапуск службы
# =============================================================================

restart_service() {
    log_info "Перезапуск службы Fail2ban..."
    
    # Создание директории для socket
    mkdir -p /var/run/fail2ban
    chown root:root /var/run/fail2ban
    chmod 755 /var/run/fail2ban
    
    systemctl daemon-reload
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    sleep 3
    
    if systemctl is-active --quiet fail2ban; then
        log_success "Fail2ban перезапущен"
    else
        log_error "Не удалось перезапустить Fail2ban"
        return 1
    fi
}

# =============================================================================
# Проверка статуса
# =============================================================================

check_status() {
    log_info "Проверка статуса Fail2ban..."
    
    echo ""
    echo "=== Статус службы ==="
    systemctl status fail2ban --no-pager -l
    
    echo ""
    echo "=== Активные jails ==="
    fail2ban-client status || true
    
    echo ""
    echo "=== Статус SSH jail ==="
    fail2ban-client status sshd || true
    
    echo ""
    echo "=== Последние записи лога ==="
    tail -20 /var/log/fail2ban.log 2>/dev/null || echo "Лог пуст или не существует"
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
            --unban)
                check_root
                log_info "Сброс всех банов..."
                fail2ban-client reload --unban --all || true
                log_success "Все баны сброшены"
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --status      Показать статус Fail2ban"
                echo "  --unban       Сбросить все баны"
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
    echo "Настройка Fail2ban"
    echo "=============================================="
    
    check_root
    create_directories
    check_fail2ban_installed
    backup_config
    apply_config
    restart_service
    check_status
    
    echo "=============================================="
    log_success "Настройка Fail2ban завершена!"
    echo "=============================================="
    echo ""
    echo "Активные защиты:"
    echo "  - SSH (sshd): 5 попыток, бан на 1 час"
    echo "  - SSH рецидивисты: бан на 24 часа"
    echo ""
    echo "Полезные команды:"
    echo "  fail2ban-client status           - общий статус"
    echo "  fail2ban-client status sshd      - статус SSH jail"
    echo "  fail2ban-client set sshd unbanip <IP> - разбанить IP"
    echo ""
    echo "Лог файл: /var/log/fail2ban.log"
    echo "Лог скрипта: ${LOG_FILE}"
}

# Запуск основной функции
main "$@"
