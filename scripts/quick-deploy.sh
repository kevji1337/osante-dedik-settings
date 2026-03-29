#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Quick Deploy Script - Run all hardening scripts in sequence
# Описание: Автоматизированный запуск всех скриптов хардинга
# Использование: ./quick-deploy.sh --username admin --ssh-key "key" --email "you@example.com"
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/quick-deploy.log"
readonly COLORS=(
    '\033[0;31m' # Red
    '\033[0;32m' # Green
    '\033[0;33m' # Yellow
    '\033[0;34m' # Blue
    '\033[0;35m' # Magenta
    '\033[0;36m' # Cyan
)
readonly NC='\033[0m'

# =============================================================================
# Variables
# =============================================================================

ADMIN_USERNAME=""
ADMIN_SSH_KEY=""
TIMEZONE="UTC"
HOSTNAME=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
SKIP_CONFIRMATION=false

# =============================================================================
# Functions
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
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

print_header() {
    local title="$1"
    echo ""
    echo -e "${COLORS[3]}=============================================="
    echo -e "${title}"
    echo -e "==============================================${NC}"
    echo ""
}

print_step() {
    local step="$1"
    local title="$2"
    echo ""
    echo -e "${COLORS[1]}>>> Step ${step}: ${title}${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен выполняться от root"
        exit 1
    fi
}

usage() {
    cat << EOF
Использование: $0 [опции]

Обязательные опции:
  --username <name>       Имя админ-пользователя
  --ssh-key <key>         SSH публичный ключ

Опциональные опции:
  --timezone <tz>         Часовой пояс (по умолчанию: UTC)
  --hostname <name>       Имя хоста
  --telegram-token <tok>  Telegram bot token для алертов
  --telegram-chat <id>    Telegram chat ID для алертов
  --yes                   Пропустить подтверждения
  -h, --help              Показать эту справку

Пример:
  $0 --username admin \\
     --ssh-key "ssh-ed25519 AAAA..." \\
     --timezone Europe/Moscow \\
     --hostname prod-server-01
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --username)
                ADMIN_USERNAME="$2"
                shift 2
                ;;
            --ssh-key)
                ADMIN_SSH_KEY="$2"
                shift 2
                ;;
            --timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            --hostname)
                HOSTNAME="$2"
                shift 2
                ;;
            --telegram-token)
                TELEGRAM_BOT_TOKEN="$2"
                shift 2
                ;;
            --telegram-chat)
                TELEGRAM_CHAT_ID="$2"
                shift 2
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Неизвестная опция: $1"
                usage
                ;;
        esac
    done

    # Проверка обязательных параметров
    if [[ -z "${ADMIN_USERNAME}" ]]; then
        log_error "Требуется --username"
        usage
    fi

    if [[ -z "${ADMIN_SSH_KEY}" ]]; then
        log_error "Требуется --ssh-key"
        usage
    fi
}

confirm() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]]; then
        return 0
    fi

    local message="$1"
    echo -e "${COLORS[2]}${message} [y/N]: ${NC}"
    read -r response
    if [[ "${response}" != "y" && "${response}" != "Y" ]]; then
        log_warn "Отменено пользователем"
        exit 0
    fi
}

run_script() {
    local script="$1"
    local description="$2"
    local args="${3:-}"

    print_step "${STEP_NUM}" "${description}"
    ((STEP_NUM++))

    if [[ ! -f "${script}" ]]; then
        log_error "Скрипт не найден: ${script}"
        return 1
    fi

    chmod +x "${script}"

    if bash "${script}" ${args}; then
        log_success "${description} завершён"
        return 0
    else
        log_error "${description} завершился с ошибкой"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"
    check_root

    mkdir -p "$(dirname "${LOG_FILE}")"

    print_header "🚀 Server Hardening Quick Deploy"

    echo "Конфигурация:"
    echo "  Username:    ${ADMIN_USERNAME}"
    echo "  Timezone:    ${TIMEZONE}"
    echo "  Hostname:    ${HOSTNAME:-<not set>}"
    echo "  SSH Key:     ${ADMIN_SSH_KEY:0:30}..."
    echo "  Telegram:    ${TELEGRAM_BOT_TOKEN:+configured}"
    echo ""

    confirm "Начать процесс хардинга? (ВНИМАНИЕ: Это может разорвать SSH сессию)"

    local STEP_NUM=1
    local failed=0

    # Step 1: System Preparation
    if run_script "${SCRIPT_DIR}/01-system-prep.sh" \
                  "System Preparation" \
                  "--username ${ADMIN_USERNAME} --ssh-key '${ADMIN_SSH_KEY}' --timezone ${TIMEZONE} ${HOSTNAME:+--hostname ${HOSTNAME}}"; then
        log_info "Step 1 completed successfully"
    else
        log_error "Step 1 failed"
        ((failed++))
    fi

    echo ""
    echo "⚠️  ВАЖНО: Следующий шаг (SSH хардинг) может разорвать SSH сессию!"
    echo "   Убедитесь, что у вас есть консольный доступ к серверу."
    confirm "Продолжить SSH хардинг?"

    # Step 2: SSH Hardening
    if run_script "${SCRIPT_DIR}/02-ssh-hardening.sh" \
                  "SSH Hardening" \
                  "--username ${ADMIN_USERNAME} --public-key '${ADMIN_SSH_KEY}'"; then
        log_info "Step 2 completed successfully"
    else
        log_error "Step 2 failed"
        ((failed++))
    fi

    # Step 3: Firewall
    if run_script "${SCRIPT_DIR}/03-firewall-setup.sh" \
                  "Firewall Setup" \
                  ""; then
        log_info "Step 3 completed successfully"
    else
        log_error "Step 3 failed"
        ((failed++))
    fi

    # Step 4: Fail2ban
    if run_script "${SCRIPT_DIR}/04-fail2ban-config.sh" \
                  "Fail2ban Configuration" \
                  ""; then
        log_info "Step 4 completed successfully"
    else
        log_error "Step 4 failed"
        ((failed++))
    fi

    # Step 5: Kernel Hardening
    if run_script "${SCRIPT_DIR}/05-sysctl-hardening.sh" \
                  "Kernel Hardening" \
                  ""; then
        log_info "Step 5 completed successfully"
    else
        log_error "Step 5 failed"
        ((failed++))
    fi

    # Step 6: Filesystem Security
    if run_script "${SCRIPT_DIR}/06-filesystem-security.sh" \
                  "Filesystem Security" \
                  ""; then
        log_info "Step 6 completed successfully"
    else
        log_error "Step 6 failed"
        ((failed++))
    fi

    # Step 7: Logging
    if run_script "${SCRIPT_DIR}/07-logging-setup.sh" \
                  "Logging Configuration" \
                  ""; then
        log_info "Step 7 completed successfully"
    else
        log_error "Step 7 failed"
        ((failed++))
    fi

    # Step 8: Monitoring
    if run_script "${SCRIPT_DIR}/08-monitoring-setup.sh" \
                  "Monitoring Setup" \
                  ""; then
        log_info "Step 8 completed successfully"
    else
        log_error "Step 8 failed"
        ((failed++))
    fi

    # Step 9: Backup
    if run_script "${SCRIPT_DIR}/09-backup-setup.sh" \
                  "Backup Setup" \
                  ""; then
        log_info "Step 9 completed successfully"
    else
        log_error "Step 9 failed"
        ((failed++))
    fi

    # Step 10: Validation
    print_step "${STEP_NUM}" "Security Validation"
    ((STEP_NUM++))

    if bash "${SCRIPT_DIR}/validate-security.sh" 2>&1 | tee -a "${LOG_FILE}"; then
        log_info "Step 10 completed successfully"
    else
        log_warn "Step 10 completed with warnings"
    fi

    # Summary
    print_header "📊 Deployment Summary"

    if [[ ${failed} -eq 0 ]]; then
        echo -e "${COLORS[1]}✅ Все шаги выполнены успешно!${NC}"
        echo ""
        echo "Следующие шаги:"
        echo "  1. Проверьте SSH подключение в новой сессии"
        echo "  2. Настройте Telegram алерты (см. docs/MONITORING.md)"
        echo "  3. Настройте Cloudflare R2 для backup (см. docs/BACKUP-RESTORE.md)"
        echo "  4. Запустите Docker security: ./scripts/10-docker-security.sh"
        echo ""
        echo "Лог файл: ${LOG_FILE}"
    else
        echo -e "${COLORS[0]}❌ ${failed} шагов завершились с ошибками${NC}"
        echo ""
        echo "Проверьте лог файл: ${LOG_FILE}"
        exit 1
    fi
}

# Запуск
main "$@"
