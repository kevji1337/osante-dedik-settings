#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт SSH хардинга
# Описание: Настройка безопасной конфигурации SSH
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/ssh-hardening.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly SSHD_CONFIG_SOURCE="${SCRIPT_DIR}/../configs/sshd_config"
readonly SSHD_CONFIG_TARGET="/etc/ssh/sshd_config"
readonly SSH_BANNER="/etc/ssh/banner"

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
# Резервное копирование текущей конфигурации
# =============================================================================

backup_ssh_config() {
    local backup_file="${BACKUP_DIR}/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
    
    log_info "Создание резервной копии SSH конфигурации..."
    
    if [[ -f "${SSHD_CONFIG_TARGET}" ]]; then
        cp "${SSHD_CONFIG_TARGET}" "${backup_file}"
        chmod 600 "${backup_file}"
        log_success "Резервная копия создана: ${backup_file}"
    else
        log_warn "Исходный файл конфигурации не найден"
    fi
}

# =============================================================================
# Создание баннера
# =============================================================================

create_banner() {
    log_info "Создание SSH баннера..."
    
    cat > "${SSH_BANNER}" << 'EOF'
================================================================================
                            ПРЕДУПРЕЖДЕНИЕ
================================================================================

Эта система предназначена только для авторизованного использования.

Все действия на этой системе регистрируются и контролируются.
Несанкционированный доступ запрещён и преследуется по закону.

Подключаясь к этой системе, вы подтверждаете, что имеете право
на доступ и соглашаетесь с мониторингом вашей деятельности.

================================================================================
EOF
    
    chmod 644 "${SSH_BANNER}"
    log_success "Баннер создан"
}

# =============================================================================
# Применение конфигурации SSH
# =============================================================================

apply_ssh_config() {
    log_info "Применение конфигурации SSH..."
    
    # Копирование конфигурации
    cp "${SSHD_CONFIG_SOURCE}" "${SSHD_CONFIG_TARGET}"
    chmod 600 "${SSHD_CONFIG_TARGET}"
    
    log_info "Конфигурация применена"
}

# =============================================================================
# Валидация конфигурации
# =============================================================================

validate_ssh_config() {
    log_info "Валидация конфигурации SSH..."
    
    if sshd -t 2>&1; then
        log_success "Конфигурация SSH валидна"
        return 0
    else
        log_error "Ошибка валидации конфигурации SSH"
        return 1
    fi
}

# =============================================================================
# Проверка SSH ключей перед перезапуском
# =============================================================================

check_ssh_keys() {
    log_info "Проверка SSH ключей..."

    local keys_found=0

    # Проверка authorized_keys для root
    if [[ -f /root/.ssh/authorized_keys ]] && [[ -s /root/.ssh/authorized_keys ]]; then
        local root_keys
        root_keys=$(wc -l < /root/.ssh/authorized_keys)
        log_info "Найдено ключей для root: ${root_keys}"
        ((keys_found += root_keys))
    fi

    # Проверка authorized_keys для admin пользователя
    if [[ -d /home/admin ]] && [[ -f /home/admin/.ssh/authorized_keys ]]; then
        local admin_keys
        admin_keys=$(wc -l < /home/admin/.ssh/authorized_keys)
        log_info "Найдено ключей для admin: ${admin_keys}"
        ((keys_found += admin_keys))
    fi

    # Проверка других пользователей с sudo
    for user_dir in /home/*; do
        if [[ -d "${user_dir}" ]] && [[ -f "${user_dir}/.ssh/authorized_keys" ]]; then
            if grep -q "sudo" /etc/group 2>/dev/null; then
                local username
                username=$(basename "${user_dir}")
                if id "${username}" &>/dev/null && id "${username}" | grep -q "sudo"; then
                    local user_keys
                    user_keys=$(wc -l < "${user_dir}/.ssh/authorized_keys")
                    log_info "Найдено ключей для ${username}: ${user_keys}"
                    ((keys_found += user_keys))
                fi
            fi
        fi
    done

    if [[ ${keys_found} -eq 0 ]]; then
        log_error "SSH ключи не найдены! Перезапуск SSH заблокирует доступ!"
        echo ""
        echo "⚠️  ВНИМАНИЕ: SSH ключи не обнаружены!"
        echo "Перезапуск SSH с текущей конфигурацией заблокирует доступ к серверу."
        echo ""
        echo "Добавьте SSH ключ перед перезапуском:"
        echo "  mkdir -p /root/.ssh"
        echo "  chmod 700 /root/.ssh"
        echo "  echo 'your-public-key' >> /root/.ssh/authorized_keys"
        echo "  chmod 600 /root/.ssh/authorized_keys"
        echo ""
        read -p "Вы хотите продолжить? (N/y): " confirm
        if [[ "${confirm}" != "y" ]] && [[ "${confirm}" != "Y" ]]; then
            log_warn "Перезапуск SSH отменён пользователем"
            return 1
        fi
    else
        log_success "Найдено SSH ключей: ${keys_found}"
    fi

    return 0
}

# =============================================================================
# Перезапуск SSH службы
# =============================================================================

restart_ssh() {
    log_info "Перезапуск SSH службы..."

    # Проверка SSH ключей перед перезапуском
    if ! check_ssh_keys; then
        log_error "Перезапуск SSH отменён - SSH ключи не найдены"
        return 1
    fi

    # Проверка, что SSH запущен
    if ! systemctl is-active --quiet ssh; then
        log_warn "SSH служба не активна"
    fi

    # Перезапуск с тестированием
    if validate_ssh_config; then
        systemctl restart ssh
        sleep 2

        if systemctl is-active --quiet ssh; then
            log_success "SSH служба перезапущена"
        else
            log_error "Не удалось перезапустить SSH службу"
            return 1
        fi
    else
        log_error "Не перезапускаем SSH из-за ошибок в конфигурации"
        return 1
    fi
}

# =============================================================================
# Настройка SSH ключей для существующих пользователей
# =============================================================================

setup_user_keys() {
    local username="$1"
    local public_key="$2"
    
    if [[ -z "${username}" ]] || [[ -z "${public_key}" ]]; then
        log_warn "Имя пользователя или ключ не указаны"
        return 0
    fi
    
    log_info "Настройка SSH ключей для пользователя: ${username}"
    
    local ssh_dir="/home/${username}/.ssh"
    
    if [[ ! -d "/home/${username}" ]]; then
        log_error "Домашняя директория пользователя не найдена"
        return 1
    fi
    
    mkdir -p "${ssh_dir}"
    echo "${public_key}" >> "${ssh_dir}/authorized_keys"
    chmod 700 "${ssh_dir}"
    chmod 600 "${ssh_dir}/authorized_keys"
    chown -R "${username}:${username}" "${ssh_dir}"
    
    log_success "SSH ключ настроен для ${username}"
}

# =============================================================================
# Проверка статуса SSH
# =============================================================================

check_ssh_status() {
    log_info "Проверка статуса SSH..."
    
    echo ""
    echo "=== Статус SSH службы ==="
    systemctl status ssh --no-pager -l
    
    echo ""
    echo "=== Активные SSH сессии ==="
    who
    
    echo ""
    echo "=== Прослушиваемые порты ==="
    ss -tlnp | grep ssh || true
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    local public_key=""
    local username=""
    local skip_restart=false
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --public-key)
                public_key="$2"
                shift 2
                ;;
            --username)
                username="$2"
                shift 2
                ;;
            --no-restart)
                skip_restart=true
                shift
                ;;
            --status)
                check_root
                check_ssh_status
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --public-key <key>   SSH публичный ключ для добавления"
                echo "  --username <name>    Имя пользователя для ключа"
                echo "  --no-restart         Не перезапускать SSH службу"
                echo "  --status             Показать статус SSH"
                echo "  -h, --help           Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "SSH Хардинг для Ubuntu 24.04 LTS"
    echo "=============================================="
    
    check_root
    create_directories
    backup_ssh_config
    create_banner
    apply_ssh_config
    
    if [[ "${skip_restart}" == "false" ]]; then
        restart_ssh
    else
        log_info "Перезапуск SSH пропущен"
        validate_ssh_config
    fi
    
    if [[ -n "${username}" ]] && [[ -n "${public_key}" ]]; then
        setup_user_keys "${username}" "${public_key}"
    fi
    
    echo "=============================================="
    log_success "SSH хардинг завершён!"
    echo "=============================================="
    echo ""
    echo "Важно: Не закрывайте текущую SSH сессию,"
    echo "пока не проверите возможность нового подключения!"
    echo ""
    echo "Для проверки: ssh -p 22 ${username:-user}@<server-ip>"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
    echo "Резервная копия: ${BACKUP_DIR}/sshd_config.backup.*"
}

# Запуск основной функции
main "$@"
