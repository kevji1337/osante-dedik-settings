#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт настройки системы备份 (Restic + Cloudflare R2)
# Описание: Установка restic, настройка переменных окружения, cron jobs
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/backup-setup.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly CONFIG_SOURCE="${SCRIPT_DIR}/../configs/backup"
readonly BACKUP_INSTALL_DIR="/opt/backup"

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
    mkdir -p /var/backups/restic/temp
    mkdir -p /var/backups/configs
    mkdir -p "${BACKUP_INSTALL_DIR}"
}

# =============================================================================
# Установка Restic
# =============================================================================

install_restic() {
    log_info "Установка restic..."
    
    if command -v restic &>/dev/null; then
        log_info "Restic уже установлен"
        restic version
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local arch
    
    # Определение архитектуры
    case "$(dpkg --print-architecture)" in
        amd64) arch="amd64" ;;
        arm64) arch="arm64" ;;
        armhf) arch="arm" ;;
        *)
            log_error "Неподдерживаемая архитектура"
            return 1
            ;;
    esac
    
    # Загрузка последней версии
    local version
    version=$(curl -s https://api.github.com/repos/restic/restic/releases/latest | jq -r .tag_name | tr -d v)
    local download_url="https://github.com/restic/restic/releases/download/v${version}/restic_${version}_linux_${arch}.bz2"
    
    log_info "Загрузка restic ${version}..."
    wget -q --show-progress -O "${temp_dir}/restic.bz2" "${download_url}"
    
    # Распаковка
    bunzip2 -f "${temp_dir}/restic.bz2"
    chmod +x "${temp_dir}/restic"
    
    # Установка
    mv "${temp_dir}/restic" /usr/local/bin/
    
    # Очистка
    rm -rf "${temp_dir}"
    
    log_success "Restic установлен: $(restic version)"
}

# =============================================================================
# Установка PostgreSQL клиента (для backup БД)
# =============================================================================

install_postgres_client() {
    log_info "Установка PostgreSQL клиента..."
    
    if command -v pg_dump &>/dev/null; then
        log_info "PostgreSQL клиент уже установлен"
        return 0
    fi
    
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql-client
    
    log_success "PostgreSQL клиент установлен"
}

# =============================================================================
# Создание файла переменных окружения
# =============================================================================

create_env_file() {
    log_info "Создание файла переменных окружения..."
    
    local env_file="/etc/profile.d/restic-backup.sh"
    
    cat > "${env_file}" << 'EOF'
# Restic Backup Environment Variables
# Заполните эти значения перед использованием backup

# Cloudflare R2 настройки
export RESTIC_REPOSITORY="r2:YOUR_BUCKET_NAME"
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_ACCESS_KEY"
export AWS_ENDPOINT_URL_S3="https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com"

# Пароль для шифрования backup (ОБЯЗАТЕЛЬНО!)
export RESTIC_PASSWORD="YOUR_STRONG_PASSWORD"

# PostgreSQL настройки (для backup БД)
export POSTGRES_CONTAINER="coolify-db"
export POSTGRES_HOST="localhost"
export POSTGRES_USER="postgres"
export POSTGRES_PASSWORD=""
EOF
    
    chmod 644 "${env_file}"
    
    log_success "Файл переменных создан: ${env_file}"
    log_warn "ВАЖНО: Заполните переменные в ${env_file} перед использованием!"
}

# =============================================================================
# Копирование скриптов backup
# =============================================================================

copy_backup_scripts() {
    log_info "Копирование скриптов backup..."
    
    if [[ -d "${CONFIG_SOURCE}" ]]; then
        cp "${CONFIG_SOURCE}/restic-profile.sh" "${BACKUP_INSTALL_DIR}/"
        cp "${CONFIG_SOURCE}/backup-postgresql.sh" "${BACKUP_INSTALL_DIR}/"
        cp "${CONFIG_SOURCE}/backup-configs.sh" "${BACKUP_INSTALL_DIR}/"
        
        chmod +x "${BACKUP_INSTALL_DIR}"/*.sh
        
        log_success "Скрипты скопированы в ${BACKUP_INSTALL_DIR}"
    else
        log_warn "Директория с конфигами не найдена"
    fi
}

# =============================================================================
# Настройка Cron jobs
# =============================================================================

configure_cron() {
    log_info "Настройка cron jobs для backup..."
    
    local cron_file="/etc/cron.d/restic-backup"
    
    cat > "${cron_file}" << 'EOF'
# Restic Backup Cron Jobs
# PostgreSQL backup - ежедневно в 2:00
0 2 * * * root /opt/backup/backup-postgresql.sh >> /var/log/backup/cron-postgresql.log 2>&1

# Configs backup - ежедневно в 3:00
0 3 * * * root /opt/backup/backup-configs.sh >> /var/log/backup/cron-configs.log 2>&1

# Очистка старых временных файлов - еженедельно в воскресенье в 4:00
0 4 * * 0 root find /var/backups/restic/temp -type f -mtime +7 -delete 2>/dev/null
EOF
    
    chmod 644 "${cron_file}"
    
    log_success "Cron jobs настроены"
}

# =============================================================================
# Создание systemd таймеров (альтернатива cron)
# =============================================================================

create_systemd_timers() {
    log_info "Создание systemd таймеров..."
    
    # PostgreSQL backup timer
    cat > /etc/systemd/system/backup-postgresql.service << 'EOF'
[Unit]
Description=PostgreSQL Backup with Restic
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-/etc/profile.d/restic-backup.sh
ExecStart=/opt/backup/backup-postgresql.sh
EOF
    
    cat > /etc/systemd/system/backup-postgresql.timer << 'EOF'
[Unit]
Description=Run PostgreSQL Backup Daily
Requires=backup-postgresql.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Configs backup timer
    cat > /etc/systemd/system/backup-configs.service << 'EOF'
[Unit]
Description=Server Configs Backup with Restic
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-/etc/profile.d/restic-backup.sh
ExecStart=/opt/backup/backup-configs.sh
EOF
    
    cat > /etc/systemd/system/backup-configs.timer << 'EOF'
[Unit]
Description=Run Configs Backup Daily
Requires=backup-configs.service

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Перезагрузка systemd и запуск таймеров
    systemctl daemon-reload
    systemctl enable backup-postgresql.timer
    systemctl start backup-postgresql.timer
    systemctl enable backup-configs.timer
    systemctl start backup-configs.timer
    
    log_success "Systemd таймеры созданы и запущены"
}

# =============================================================================
# Инициализация Restic репозитория
# =============================================================================

init_restic_repo() {
    log_info "Инициализация Restic репозитория..."
    
    # Проверка переменных окружения
    if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
        log_warn "RESTIC_REPOSITORY не установлен, пропускаем инициализацию"
        log_info "Заполните /etc/profile.d/restic-backup.sh и выполните: restic init"
        return 0
    fi
    
    if restic snapshots &>/dev/null; then
        log_info "Репозиторий уже инициализирован"
    else
        log_info "Инициализация нового репозитория..."
        restic init
        log_success "Репозиторий инициализирован"
    fi
}

# =============================================================================
# Инструкция по настройке Cloudflare R2
# =============================================================================

print_r2_instructions() {
    echo ""
    echo "=============================================="
    echo "Настройка Cloudflare R2 для backup"
    echo "=============================================="
    echo ""
    echo "1. Создайте R2 bucket в Cloudflare:"
    echo "   - Зайдите в Cloudflare Dashboard"
    echo "   - Перейдите в R2 Storage"
    echo "   - Создайте новый bucket"
    echo ""
    echo "2. Создайте API токен:"
    echo "   - R2 API Tokens -> Create API Token"
    echo "   - Выберите permissions: Object Read & Write"
    echo "   - Сохраните Access Key ID и Secret Access Key"
    echo ""
    echo "3. Узнайте Account ID:"
    echo "   - Находится в Cloudflare Dashboard (справа внизу)"
    echo ""
    echo "4. Заполните /etc/profile.d/restic-backup.sh:"
    echo "   export RESTIC_REPOSITORY=\"r2:YOUR_BUCKET_NAME\""
    echo "   export AWS_ACCESS_KEY_ID=\"YOUR_KEY_ID\""
    echo "   export AWS_SECRET_ACCESS_KEY=\"YOUR_SECRET_KEY\""
    echo "   export AWS_ENDPOINT_URL_S3=\"https://ACCOUNT_ID.r2.cloudflarestorage.com\""
    echo "   export RESTIC_PASSWORD=\"YOUR_ENCRYPTION_PASSWORD\""
    echo ""
    echo "5. Примените переменные:"
    echo "   source /etc/profile.d/restic-backup.sh"
    echo ""
    echo "6. Инициализируйте репозиторий:"
    echo "   restic init"
    echo ""
}

# =============================================================================
# Проверка статуса
# =============================================================================

check_status() {
    echo ""
    echo "=== Restic версия ==="
    restic version 2>/dev/null || echo "Restic не установлен"
    
    echo ""
    echo "=== Статус systemd таймеров ==="
    systemctl list-timers | grep backup || echo "Таймеры не найдены"
    
    echo ""
    echo "=== Cron jobs ==="
    cat /etc/cron.d/restic-backup 2>/dev/null || echo "Cron jobs не настроены"
    
    echo ""
    echo "=== Переменные окружения ==="
    env | grep -E 'RESTIC_|AWS_' | sed 's/=.*//g' || echo "Не установлены"
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
            --instructions)
                print_r2_instructions
                exit 0
                ;;
            --init-only)
                check_root
                init_restic_repo
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --status        Показать статус backup системы"
                echo "  --instructions  Инструкция по настройке R2"
                echo "  --init-only     Только инициализация репозитория"
                echo "  -h, --help      Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "Настройка системы backup (Restic + R2)"
    echo "=============================================="
    
    check_root
    create_directories
    install_restic
    install_postgres_client
    create_env_file
    copy_backup_scripts
    configure_cron
    create_systemd_timers
    print_r2_instructions
    
    echo "=============================================="
    log_success "Настройка backup системы завершена!"
    echo "=============================================="
    echo ""
    echo "Скрипты backup:"
    echo "  - /opt/backup/backup-postgresql.sh  (backup БД)"
    echo "  - /opt/backup/backup-configs.sh     (backup конфигов)"
    echo ""
    echo "Следующие шаги:"
    echo "  1. Заполните /etc/profile.d/restic-backup.sh"
    echo "  2. Выполните: source /etc/profile.d/restic-backup.sh"
    echo "  3. Инициализируйте: restic init"
    echo "  4. Проверьте: /opt/backup/backup-configs.sh --local-only"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
}

# Запуск основной функции
main "$@"
