#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт безопасности файловой системы
# Описание: Проверка и настройка прав доступа, umask, world-writable файлов
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/filesystem-security.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly REPORT_FILE="${BACKUP_DIR}/filesystem-report.$(date +%Y%m%d_%H%M%S).txt"

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
# Настройка безопасного umask
# =============================================================================

configure_umask() {
    log_info "Настройка безопасного umask..."
    
    # Umask 027 - файлы: 640, директории: 750
    local umask_value="027"
    
    # Обновление /etc/profile
    if ! grep -q "^umask ${umask_value}" /etc/profile; then
        echo "umask ${umask_value}" >> /etc/profile
        log_info "umask добавлен в /etc/profile"
    fi
    
    # Обновление /etc/bash.bashrc
    if ! grep -q "^umask ${umask_value}" /etc/bash.bashrc; then
        echo "umask ${umask_value}" >> /etc/bash.bashrc
        log_info "umask добавлен в /etc/bash.bashrc"
    fi
    
    # Обновление /etc/login.defs
    if grep -q "^UMASK" /etc/login.defs; then
        sed -i "s/^UMASK.*/UMASK		027/" /etc/login.defs
    else
        echo "UMASK		027" >> /etc/login.defs
    fi
    
    log_success "umask настроен: ${umask_value}"
}

# =============================================================================
# Поиск world-writable файлов
# =============================================================================

find_world_writable() {
    log_info "Поиск world-writable файлов и директорий..."
    
    local output_file="${BACKUP_DIR}/world-writable.$(date +%Y%m%d_%H%M%S).txt"
    
    # Поиск world-writable файлов без sticky bit
    find / -type f -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null > "${output_file}" || true
    
    # Поиск world-writable директорий без sticky bit
    find / -type d -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null >> "${output_file}" || true
    
    local count
    count=$(wc -l < "${output_file}")
    
    if [[ "${count}" -gt 0 ]]; then
        log_warn "Найдено world-writable файлов/директорий: ${count}"
        log_warn "Список сохранён: ${output_file}"
    else
        log_success "World-writable файлы не найдены"
    fi
    
    echo "${output_file}"
}

# =============================================================================
# Поиск SUID/SGID файлов
# =============================================================================

find_suid_sgid() {
    log_info "Поиск SUID/SGID файлов..."
    
    local suid_file="${BACKUP_DIR}/suid-files.$(date +%Y%m%d_%H%M%S).txt"
    local sgid_file="${BACKUP_DIR}/sgid-files.$(date +%Y%m%d_%H%M%S).txt"
    
    # Поиск SUID файлов
    find / -type f -perm -4000 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null > "${suid_file}" || true
    
    # Поиск SGID файлов
    find / -type f -perm -2000 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null > "${sgid_file}" || true
    
    local suid_count sgid_count
    suid_count=$(wc -l < "${suid_file}")
    sgid_count=$(wc -l < "${sgid_file}")
    
    log_info "Найдено SUID файлов: ${suid_count}"
    log_info "Найдено SGID файлов: ${sgid_count}"
    log_info "Отчёты: ${suid_file}, ${sgid_file}"
}

# =============================================================================
# Проверка критических файлов и директорий
# =============================================================================

check_critical_permissions() {
    log_info "Проверка прав критических файлов..."
    
    local issues=0
    
    # Проверка /etc/passwd
    if [[ -f /etc/passwd ]]; then
        local perms
        perms=$(stat -c %a /etc/passwd)
        if [[ "${perms}" != "644" ]]; then
            log_warn "/etc/passwd имеет права: ${perms} (ожидалось 644)"
            ((issues++))
        fi
    fi
    
    # Проверка /etc/shadow
    if [[ -f /etc/shadow ]]; then
        local perms
        perms=$(stat -c %a /etc/shadow)
        if [[ "${perms}" != "640" ]] && [[ "${perms}" != "600" ]]; then
            log_warn "/etc/shadow имеет права: ${perms} (ожидалось 640 или 600)"
            ((issues++))
        fi
    fi
    
    # Проверка /etc/group
    if [[ -f /etc/group ]]; then
        local perms
        perms=$(stat -c %a /etc/group)
        if [[ "${perms}" != "644" ]]; then
            log_warn "/etc/group имеет права: ${perms} (ожидалось 644)"
            ((issues++))
        fi
    fi
    
    # Проверка /etc/ssh/sshd_config
    if [[ -f /etc/ssh/sshd_config ]]; then
        local perms
        perms=$(stat -c %a /etc/ssh/sshd_config)
        if [[ "${perms}" != "600" ]]; then
            log_warn "/etc/ssh/sshd_config имеет права: ${perms} (ожидалось 600)"
            ((issues++))
        fi
    fi
    
    # Проверка /root
    if [[ -d /root ]]; then
        local perms
        perms=$(stat -c %a /root)
        if [[ "${perms}" != "700" ]]; then
            log_warn "/root имеет права: ${perms} (ожидалось 700)"
            ((issues++))
        fi
    fi
    
    if [[ ${issues} -eq 0 ]]; then
        log_success "Все критические файлы имеют правильные права"
    else
        log_warn "Найдено проблем с правами: ${issues}"
    fi
    
    return ${issues}
}

# =============================================================================
# Исправление прав Docker socket
# =============================================================================

fix_docker_socket() {
    log_info "Проверка Docker socket..."
    
    if [[ -S /var/run/docker.sock ]]; then
        local perms
        perms=$(stat -c %a /var/run/docker.sock)
        local owner
        owner=$(stat -c %U:%G /var/run/docker.sock)
        
        log_info "Docker socket: ${perms}, владелец: ${owner}"
        
        # Docker socket должен быть доступен только root и группе docker
        if [[ "${perms}" != "660" ]]; then
            log_warn "Docker socket имеет нестандартные права"
        fi
    else
        log_info "Docker socket не найден (Docker может быть не запущен)"
    fi
}

# =============================================================================
# Генерация отчёта
# =============================================================================

generate_report() {
    log_info "Генерация отчёта о безопасности ФС..."
    
    {
        echo "=============================================="
        echo "Отчёт о безопасности файловой системы"
        echo "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=============================================="
        echo ""
        
        echo "=== Umask настройки ==="
        grep -h "^umask" /etc/profile /etc/bash.bashrc 2>/dev/null || echo "Не настроено"
        echo ""
        
        echo "=== Критические файлы ==="
        echo "Файл                  Права    Владелец"
        echo "----------------------------------------"
        for file in /etc/passwd /etc/shadow /etc/group /etc/ssh/sshd_config /root; do
            if [[ -e "${file}" ]]; then
                printf "%-20s  %-8s  %s\n" \
                    "${file}" \
                    "$(stat -c %a "${file}")" \
                    "$(stat -c %U:%G "${file}")"
            fi
        done
        echo ""
        
        echo "=== World-writable файлы (первые 20) ==="
        find / -type f -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | head -20 || echo "Не найдено"
        echo ""
        
        echo "=== SUID файлы (первые 20) ==="
        find / -type f -perm -4000 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | head -20 || echo "Не найдено"
        echo ""
        
    } > "${REPORT_FILE}"
    
    log_success "Отчёт сохранён: ${REPORT_FILE}"
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --report)
                check_root
                generate_report
                cat "${REPORT_FILE}"
                exit 0
                ;;
            --check-only)
                check_root
                check_critical_permissions
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --report      Сгенерировать полный отчёт"
                echo "  --check-only  Только проверка без изменений"
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
    echo "Безопасность файловой системы"
    echo "=============================================="
    
    check_root
    create_directories
    configure_umask
    find_world_writable
    find_suid_sgid
    check_critical_permissions
    fix_docker_socket
    generate_report
    
    echo "=============================================="
    log_success "Проверка файловой системы завершена!"
    echo "=============================================="
    echo ""
    echo "Рекомендации:"
    echo "  - Проверьте world-writable файлы в отчёте"
    echo "  - Аудитируйте SUID/SGID файлы периодически"
    echo "  - Используйте минимальные права для сервисов"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
    echo "Отчёт: ${REPORT_FILE}"
}

# Запуск основной функции
main "$@"
