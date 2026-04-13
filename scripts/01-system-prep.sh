#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт подготовки системы Ubuntu 24.04 LTS
# Описание: Обновление системы, установка пакетов, создание админ-пользователя
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/system-prep.log"
readonly BACKUP_DIR="/var/backups/hardening"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

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
    log_info "Создание необходимых директорий..."
    
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "$(dirname "${LOG_FILE}")"
    mkdir -p /var/log/server-hardening
    
    log_success "Директории созданы"
}

# =============================================================================
# Обновление системы
# =============================================================================

update_system() {
    log_info "Обновление списков пакетов..."
    apt-get update -qq
    
    log_info "Обновление установленных пакетов..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    
    log_info "Удаление ненужных пакетов..."
    apt-get autoremove -y -qq
    
    log_info "Очистка кэша пакетов..."
    apt-get clean -y
    
    log_success "Система обновлена"
}

# =============================================================================
# Установка базовых пакетов
# =============================================================================

install_packages() {
    log_info "Установка базовых пакетов..."
    
    local packages=(
        # Утилиты
        curl
        wget
        git
        vim
        nano
        htop
        tmux
        jq
        unzip
        rsync
        
        # Безопасность
        ufw
        fail2ban
        auditd
        rsyslog
        logrotate
        
        # Обновление
        needrestart
        unattended-upgrades
        apt-listchanges
        debsums
        
        # Утилиты анализа
        ncdu
        tree
        bash-completion
        
        # Дополнительно для мониторинга
        prometheus-node-exporter
    )
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
    
    log_success "Пакеты установлены: ${packages[*]}"
}

# =============================================================================
# Настройка часового пояса
# =============================================================================

setup_timezone() {
    local timezone="${1:-UTC}"
    
    log_info "Настройка часового пояса: ${timezone}..."
    
    timedatectl set-timezone "${timezone}"
    
    # Проверка
    local current_tz
    current_tz=$(timedatectl show -p Timezone --value)
    
    if [[ "${current_tz}" == "${timezone}" ]]; then
        log_success "Часовой пояс установлен: ${timezone}"
    else
        log_error "Не удалось установить часовой пояс"
        return 1
    fi
}

# =============================================================================
# Создание админ-пользователя
# =============================================================================

create_admin_user() {
    local username="${1:-}"
    local ssh_public_key="${2:-}"
    
    if [[ -z "${username}" ]]; then
        log_error "Имя пользователя не указано"
        echo "Использование: $0 --username <name> --ssh-key <key>"
        return 1
    fi
    
    log_info "Создание админ-пользователя: ${username}..."
    
    # Проверка существования пользователя
    if id "${username}" &>/dev/null; then
        log_warn "Пользователь ${username} уже существует"
    else
        # Создание пользователя без пароля (только SSH ключ)
        useradd -m -s /bin/bash -G sudo "${username}"
        log_success "Пользователь ${username} создан"
    fi
    
    # Настройка SSH ключа
    if [[ -n "${ssh_public_key}" ]]; then
        local ssh_dir="/home/${username}/.ssh"
        mkdir -p "${ssh_dir}"
        
        echo "${ssh_public_key}" >> "${ssh_dir}/authorized_keys"
        chmod 700 "${ssh_dir}"
        chmod 600 "${ssh_dir}/authorized_keys"
        chown -R "${username}:${username}" "${ssh_dir}"
        
        log_success "SSH ключ добавлен для ${username}"
    else
        log_warn "SSH ключ не указан - пользователь не сможет войти по SSH"
    fi
}

# =============================================================================
# Настройка sudo
# =============================================================================

configure_sudo() {
    log_info "Настройка sudo..."
    
    local sudoers_backup="${BACKUP_DIR}/etc_sudoers.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/sudoers "${sudoers_backup}"
    chmod 440 "${sudoers_backup}"
    
    # Создание конфига sudo для админ-группы
    local sudo_config="/etc/sudoers.d/admin-hardening"
    cat > "${sudo_config}" << 'EOF'
# Настройки sudo для безопасности
# Требовать пароль при использовании sudo
Defaults    passwd_timeout=5
Defaults    timestamp_timeout=15

# Требовать tty для sudo
Defaults    requiretty

# Логирование команд sudo
Defaults    logfile="/var/log/sudo.log"

# Безопасный PATH
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

# Отключить env_keep для безопасности
Defaults    env_reset

# Разрешить группе sudo выполнять все команды
%sudo   ALL=(ALL:ALL) ALL
EOF
    
    chmod 440 "${sudo_config}"
    visudo -c -f "${sudo_config}"
    
    log_success "Sudo настроен"
}

# =============================================================================
# Настройка автоматических обновлений безопасности
# =============================================================================

configure_auto_updates() {
    log_info "Настройка автоматических обновлений безопасности..."
    
    # Конфигурация unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
EOF
    
    # Включение автоматических обновлений
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
    
    log_success "Автоматические обновления настроены"
}

# =============================================================================
# Настройка hostname
# =============================================================================

setup_hostname() {
    local hostname="${1:-}"
    
    if [[ -z "${hostname}" ]]; then
        log_info "Hostname не указан, пропускаем..."
        return 0
    fi
    
    log_info "Настройка hostname: ${hostname}..."
    
    hostnamectl set-hostname "${hostname}"
    
    # Обновление /etc/hosts
    if ! grep -q "${hostname}" /etc/hosts; then
        echo "127.0.1.1 ${hostname}" >> /etc/hosts
    fi
    
    log_success "Hostname установлен: ${hostname}"
}

# =============================================================================
# Отключение ненужных служб
# =============================================================================

disable_services() {
    log_info "Отключение ненужных служб..."
    
    local services=(
        bluetooth
        cups
        modemmanager
    )
    
    for service in "${services[@]}"; do
        if systemctl is-enabled "${service}" &>/dev/null; then
            systemctl disable "${service}" --now 2>/dev/null || true
            log_info "Служба ${service} отключена"
        fi
    done
    
    log_success "Некоторые службы отключены"
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    local username=""
    local ssh_key=""
    local timezone="UTC"
    local hostname=""
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --username)
                username="$2"
                shift 2
                ;;
            --ssh-key)
                ssh_key="$2"
                shift 2
                ;;
            --timezone)
                timezone="$2"
                shift 2
                ;;
            --hostname)
                hostname="$2"
                shift 2
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --username <name>   Имя админ-пользователя"
                echo "  --ssh-key <key>     SSH публичный ключ"
                echo "  --timezone <tz>     Часовой пояс (по умолчанию: UTC)"
                echo "  --hostname <name>   Имя хоста"
                echo "  -h, --help          Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "Подготовка системы Ubuntu 24.04 LTS"
    echo "=============================================="
    
    check_root
    create_directories
    
    update_system
    install_packages
    setup_timezone "${timezone}"
    
    if [[ -n "${username}" ]]; then
        create_admin_user "${username}" "${ssh_key}"
        configure_sudo
    fi
    
    configure_auto_updates
    setup_hostname "${hostname}"
    disable_services
    
    echo "=============================================="
    log_success "Подготовка системы завершена!"
    echo "=============================================="
    echo ""
    echo "Следующие шаги:"
    echo "1. Настройте SSH хардинг: scripts/02-ssh-hardening.sh"
    echo "2. Настройте фаервол: scripts/03-firewall-setup.sh"
    echo "3. Настройте Fail2ban: scripts/04-fail2ban-config.sh"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
}

# Запуск основной функции
main "$@"
