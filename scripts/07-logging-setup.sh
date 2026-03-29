#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт настройки логирования и аудита
# Описание: Настройка auditd, journald, logrotate
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/logging-setup.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly LOGROTATE_SOURCE="${SCRIPT_DIR}/../configs/logrotate.d"

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
    mkdir -p /var/log/backup
    mkdir -p /var/log/monitoring
    mkdir -p /var/log/sudo-io
}

# =============================================================================
# Проверка установки пакетов
# =============================================================================

check_packages() {
    log_info "Проверка установленных пакетов..."
    
    local packages=(auditd rsyslog logrotate)
    local missing=()
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*${pkg}"; then
            missing+=("${pkg}")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Отсутствуют пакеты: ${missing[*]}"
        log_info "Установка отсутствующих пакетов..."
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
    fi
    
    log_success "Все пакеты установлены"
}

# =============================================================================
# Настройка auditd
# =============================================================================

configure_auditd() {
    log_info "Настройка auditd..."
    
    local audit_config="/etc/audit/auditd.conf"
    local audit_rules="/etc/audit/rules.d/audit.rules"
    
    # Резервное копирование
    if [[ -f "${audit_config}" ]]; then
        cp "${audit_config}" "${BACKUP_DIR}/auditd.conf.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Настройка auditd.conf
    cat > "${audit_config}" << 'EOF'
# Auditd Configuration - Production Hardening

# Лог файл
log_file = /var/log/audit/audit.log

# Формат логов
log_format = ENRICHED

# Максимальный размер файла (MB)
max_log_file = 100

# Действие при достижении размера
max_log_file_action = ROTATE

# Количество ротированных файлов
num_logs = 10

# Приоритет
flush = INCREMENTAL_ASYNC
flush_frequency = 50

# Максимальный размер буфера
max_log_file_action = ROTATE

# Действие при нехватке места
space_left = 75
space_left_action = SYSLOG
admin_space_left = 50
admin_space_left_action = SUSPEND
disk_full_action = SUSPEND
disk_error_action = SUSPEND

# Отправка логов в syslog
write_logs = YES

# Компьютерное имя
name_format = HOSTNAME
EOF
    
    # Настройка правил аудита
    cat > "${audit_rules}" << 'EOF'
# Audit Rules - Production Server

# Удалить все существующие правила
-D

# Буфер
-b 8192

# Режим (0=silent, 1=printk, 2=panic)
-f 1

# Мониторинг изменений времени
-w /etc/localtime -p wa -k time-change
-w /etc/timezone -p wa -k time-change

# Мониторинг изменений системы
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k identity
-w /etc/sudoers.d/ -p wa -k identity

# Мониторинг аутентификации
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Мониторинг сети
-w /etc/hosts -p wa -k network
-w /etc/network/ -p wa -k network

# Мониторинг SSH
-w /etc/ssh/sshd_config -p wa -k sshd

# Мониторинг sudo
-w /var/log/sudo.log -p wa -k sudo
-w /var/log/sudo-io -p wa -k sudo

# Мониторинг Docker
-w /var/run/docker.sock -p wa -k docker
-w /etc/docker/ -p wa -k docker

# Системные вызовы (опционально, может быть шумно)
# -a exit,always -F arch=b64 -S execve -k exec
# -a exit,always -F arch=b32 -S execve -k exec

# Запись всех действий root
-a exit,always -F arch=b64 -F euid=0 -S execve -k root-actions
-a exit,always -F arch=b32 -F euid=0 -S execve -k root-actions

# Неизменяемые правила (раскомментировать для продакшена)
# -e 2
EOF
    
    log_success "Auditd настроен"
}

# =============================================================================
# Настройка journald
# =============================================================================

configure_journald() {
    log_info "Настройка journald..."
    
    local journald_config="/etc/systemd/journald.conf"
    
    # Резервное копирование
    if [[ -f "${journald_config}" ]]; then
        cp "${journald_config}" "${BACKUP_DIR}/journald.conf.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Настройка
    cat > "${journald_config}" << 'EOF'
[Journal]
# Хранение логов (persistent, volatile, none)
Storage=persistent

# Сжатие старых логов
Compress=yes

# Формат хранения
Seal=yes

# Максимальный размер хранилища
SystemMaxUse=500M
SystemKeepFree=1G
SystemMaxFileSize=50M
SystemMaxFiles=10

# Максимальный размер для пользователя
RuntimeMaxUse=100M
RuntimeKeepFree=500M
RuntimeMaxFileSize=10M
RuntimeMaxFiles=5

# Время хранения (недели)
MaxRetentionSec=3month

# Пересылка в syslog
ForwardToSyslog=yes

# Скорость записи
RateLimitIntervalSec=30s
RateLimitBurst=10000
EOF
    
    # Перезапуск journald
    systemctl restart systemd-journald 2>/dev/null || true
    
    log_success "Journald настроен"
}

# =============================================================================
# Настройка logrotate
# =============================================================================

configure_logrotate() {
    log_info "Настройка logrotate..."
    
    # Копирование конфигов logrotate
    if [[ -d "${LOGROTATE_SOURCE}" ]]; then
        cp "${LOGROTATE_SOURCE}/auditd" /etc/logrotate.d/auditd
        cp "${LOGROTATE_SOURCE}/custom-apps" /etc/logrotate.d/custom-apps
        chmod 644 /etc/logrotate.d/auditd
        chmod 644 /etc/logrotate.d/custom-apps
        log_success "Конфиги logrotate применены"
    else
        log_warn "Директория с конфигами не найдена"
    fi
    
    # Тестирование конфигурации
    if logrotate -d /etc/logrotate.conf &>/dev/null; then
        log_success "Конфигурация logrotate валидна"
    else
        log_error "Ошибка в конфигурации logrotate"
        return 1
    fi
}

# =============================================================================
# Настройка rsyslog
# =============================================================================

configure_rsyslog() {
    log_info "Настройка rsyslog..."
    
    local rsyslog_config="/etc/rsyslog.conf"
    
    # Резервное копирование
    if [[ -f "${rsyslog_config}" ]]; then
        cp "${rsyslog_config}" "${BACKUP_DIR}/rsyslog.conf.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Создание конфига для безопасности
    cat > /etc/rsyslog.d/99-security.conf << 'EOF'
# Security logging configuration

# Логирование аутентификации
auth,authpriv.*                 /var/log/auth.log

# Логирование всех сообщений безопасности
*.*;auth,authpriv.none          -/var/log/syslog

# Отдельный лог для ошибок ядра
kern.*                          -/var/log/kern.log

# Логирование демонов
daemon.*                        -/var/log/daemon.log

# Формат с высокоточным временем
$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat
$ActionFileEnableSync on
EOF
    
    # Перезапуск rsyslog
    systemctl restart rsyslog 2>/dev/null || true
    
    log_success "Rsyslog настроен"
}

# =============================================================================
# Проверка статуса
# =============================================================================

check_status() {
    log_info "Проверка статуса служб логирования..."
    
    echo ""
    echo "=== Статус служб ==="
    systemctl status auditd --no-pager -l 2>/dev/null || echo "auditd: не активен"
    echo ""
    systemctl status rsyslog --no-pager -l 2>/dev/null || echo "rsyslog: не активен"
    echo ""
    systemctl status systemd-journald --no-pager -l 2>/dev/null || echo "journald: не активен"
    
    echo ""
    echo "=== Размер логов ==="
    du -sh /var/log/* 2>/dev/null | sort -hr | head -10
    
    echo ""
    echo "=== Последние записи auth.log ==="
    tail -5 /var/log/auth.log 2>/dev/null || echo "auth.log пуст"
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
            --audit-only)
                check_root
                configure_auditd
                systemctl restart auditd 2>/dev/null || true
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --status      Показать статус служб"
                echo "  --audit-only  Настроить только auditd"
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
    echo "Настройка логирования и аудита"
    echo "=============================================="
    
    check_root
    create_directories
    check_packages
    configure_auditd
    configure_journald
    configure_logrotate
    configure_rsyslog
    
    # Перезапуск служб
    log_info "Перезапуск служб логирования..."
    systemctl restart auditd 2>/dev/null || log_warn "Не удалось перезапустить auditd"
    systemctl restart rsyslog 2>/dev/null || log_warn "Не удалось перезапустить rsyslog"
    systemctl restart systemd-journald 2>/dev/null || log_warn "Не удалось перезапустить journald"
    
    check_status
    
    echo "=============================================="
    log_success "Настройка логирования завершена!"
    echo "=============================================="
    echo ""
    echo "Настроенные компоненты:"
    echo "  - auditd: аудит безопасности"
    echo "  - journald: системные логи с ротацией"
    echo "  - rsyslog: классическое логирование"
    echo "  - logrotate: ротация логов"
    echo ""
    echo "Полезные команды:"
    echo "  journalctl -f              - просмотр логов в реальном времени"
    echo "  ausearch -k <key>          - поиск по ключу аудита"
    echo "  aureport                     - отчёт аудита"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
}

# Запуск основной функции
main "$@"
