#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт хардинга ядра (sysctl)
# Описание: Применение безопасных настроек ядра
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/sysctl-hardening.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly SYSCTL_SOURCE="${SCRIPT_DIR}/../configs/sysctl.d/99-hardening.conf"
readonly SYSCTL_TARGET="/etc/sysctl.d/99-hardening.conf"

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
    mkdir -p /etc/sysctl.d
}

# =============================================================================
# Резервное копирование
# =============================================================================

backup_config() {
    log_info "Создание резервной копии текущих sysctl настроек..."
    
    local backup_file="${BACKUP_DIR}/sysctl.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Сохранение текущих значений
    sysctl -a > "${backup_file}.all" 2>/dev/null || true
    
    # Копирование существующих конфигов
    if [[ -d /etc/sysctl.d ]]; then
        cp -r /etc/sysctl.d "${backup_file}.d" 2>/dev/null || true
    fi
    
    log_success "Резервная копия создана: ${backup_file}.*"
}

# =============================================================================
# Применение конфигурации
# =============================================================================

apply_config() {
    log_info "Применение конфигурации sysctl..."
    
    if [[ ! -f "${SYSCTL_SOURCE}" ]]; then
        log_error "Файл конфигурации не найден: ${SYSCTL_SOURCE}"
        return 1
    fi
    
    cp "${SYSCTL_SOURCE}" "${SYSCTL_TARGET}"
    chmod 644 "${SYSCTL_TARGET}"
    
    log_info "Конфигурация скопирована в ${SYSCTL_TARGET}"
}

# =============================================================================
# Применение настроек
# =============================================================================

apply_settings() {
    log_info "Применение sysctl настроек..."
    
    # Применение конкретного файла
    if sysctl -p "${SYSCTL_TARGET}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Настройки применены"
    else
        log_error "Некоторые настройки не удалось применить"
        # Не прерываем выполнение - некоторые настройки могут быть недоступны в контейнере
    fi
    
    # Проверка критических настроек для Docker
    log_info "Проверка критических настроек для Docker..."
    
    local ip_forward
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    
    if [[ "${ip_forward}" == "1" ]]; then
        log_success "IP forwarding включён (требуется для Docker)"
    else
        log_warn "IP forwarding отключён - Docker networking может не работать"
    fi
}

# =============================================================================
# Проверка настроек
# =============================================================================

verify_settings() {
    log_info "Проверка применённых настроек..."
    
    echo ""
    echo "=== Ключевые параметры безопасности ==="
    
    local checks=(
        "net.ipv4.tcp_syncookies"
        "net.ipv4.conf.all.accept_redirects"
        "net.ipv4.conf.all.send_redirects"
        "net.ipv4.conf.all.rp_filter"
        "net.ipv4.conf.all.log_martians"
        "net.ipv4.ip_forward"
        "kernel.randomize_va_space"
        "kernel.yama.ptrace_scope"
        "fs.protected_hardlinks"
        "fs.protected_symlinks"
    )
    
    for param in "${checks[@]}"; do
        local value
        value=$(sysctl -n "${param}" 2>/dev/null || echo "N/A")
        printf "%-45s = %s\n" "${param}" "${value}"
    done
    
    echo ""
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verify)
                check_root
                verify_settings
                exit 0
                ;;
            --dry-run)
                log_info "Режим проверки - без внесения изменений"
                verify_settings
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --verify      Проверить текущие настройки"
                echo "  --dry-run     Проверка без применения"
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
    echo "Хардинг ядра (sysctl)"
    echo "=============================================="
    
    check_root
    create_directories
    backup_config
    apply_config
    apply_settings
    verify_settings
    
    echo "=============================================="
    log_success "Хардинг ядра завершён!"
    echo "=============================================="
    echo ""
    echo "Применённые настройки:"
    echo "  - Защита от spoofing"
    echo "  - Отключение ICMP redirects"
    echo "  - SYN cookies защита"
    echo "  - Логирование martian packets"
    echo "  - Защита filesystem (hardlinks/symlinks)"
    echo "  - ASLR включён"
    echo ""
    echo "Важно: IP forwarding оставлен включённым для Docker"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
    echo "Конфиг: ${SYSCTL_TARGET}"
}

# Запуск основной функции
main "$@"
