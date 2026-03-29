#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Security Validation Script
# Описание: Комплексная проверка безопасности сервера
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/security-validation.log"
readonly REPORT_FILE="/var/log/server-hardening/security-report.$(date +%Y%m%d_%H%M%S).txt"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Счётчики
declare -i PASS_COUNT=0
declare -i WARN_COUNT=0
declare -i FAIL_COUNT=0

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
# Функции проверки
# =============================================================================

check_pass() {
    local message="$1"
    echo -e "${GREEN}[PASS]${NC} ${message}"
    echo "[PASS] ${message}" >> "${REPORT_FILE}"
    ((PASS_COUNT++))
}

check_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} ${message}"
    echo "[WARN] ${message}" >> "${REPORT_FILE}"
    ((WARN_COUNT++))
}

check_fail() {
    local message="$1"
    echo -e "${RED}[FAIL]${NC} ${message}"
    echo "[FAIL] ${message}" >> "${REPORT_FILE}"
    ((FAIL_COUNT++))
}

section_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}${title}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "" >> "${REPORT_FILE}"
    echo "========================================" >> "${REPORT_FILE}"
    echo "${title}" >> "${REPORT_FILE}"
    echo "========================================" >> "${REPORT_FILE}"
}

# =============================================================================
# Проверка SSH конфигурации
# =============================================================================

check_ssh() {
    section_header "SSH Configuration"
    
    local sshd_config="/etc/ssh/sshd_config"
    
    if [[ ! -f "${sshd_config}" ]]; then
        check_fail "sshd_config не найден"
        return
    fi
    
    # PermitRootLogin
    if grep -qE "^PermitRootLogin\s+no" "${sshd_config}"; then
        check_pass "PermitRootLogin отключён"
    else
        check_fail "PermitRootLogin не отключён"
    fi
    
    # PasswordAuthentication
    if grep -qE "^PasswordAuthentication\s+no" "${sshd_config}"; then
        check_pass "PasswordAuthentication отключён"
    else
        check_fail "PasswordAuthentication не отключён"
    fi
    
    # PubkeyAuthentication
    if grep -qE "^PubkeyAuthentication\s+yes" "${sshd_config}"; then
        check_pass "PubkeyAuthentication включён"
    else
        check_warn "PubkeyAuthentication не настроен явно"
    fi
    
    # MaxAuthTries
    local max_auth
    max_auth=$(grep -E "^MaxAuthTries" "${sshd_config}" | awk '{print $2}')
    if [[ -n "${max_auth}" ]] && [[ "${max_auth}" -le 5 ]]; then
        check_pass "MaxAuthTries = ${max_auth} (≤5)"
    else
        check_warn "MaxAuthTries не настроен или слишком высокий"
    fi
    
    # X11Forwarding
    if grep -qE "^X11Forwarding\s+no" "${sshd_config}"; then
        check_pass "X11Forwarding отключён"
    else
        check_warn "X11Forwarding не отключён"
    fi
    
    # ClientAliveInterval
    if grep -qE "^ClientAliveInterval" "${sshd_config}"; then
        check_pass "ClientAliveInterval настроен"
    else
        check_warn "ClientAliveInterval не настроен"
    fi
    
    # Проверка валидности конфигурации
    if sshd -t 2>/dev/null; then
        check_pass "SSH конфигурация валидна"
    else
        check_fail "SSH конфигурация содержит ошибки"
    fi
}

# =============================================================================
# Проверка фаервола
# =============================================================================

check_firewall() {
    section_header "Firewall (UFW)"
    
    if ! command -v ufw &>/dev/null; then
        check_fail "UFW не установлен"
        return
    fi
    
    # Статус UFW
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        check_pass "UFW активен"
    else
        check_fail "UFW не активен"
    fi
    
    # Проверка правил
    local ufw_status
    ufw_status=$(ufw status 2>/dev/null)
    
    if echo "${ufw_status}" | grep -q "22/tcp.*ALLOW"; then
        check_pass "SSH порт 22 открыт"
    else
        check_warn "SSH порт 22 не найден в правилах"
    fi
    
    if echo "${ufw_status}" | grep -q "80/tcp.*ALLOW"; then
        check_pass "HTTP порт 80 открыт"
    else
        check_warn "HTTP порт 80 не найден в правилах"
    fi
    
    if echo "${ufw_status}" | grep -q "443/tcp.*ALLOW"; then
        check_pass "HTTPS порт 443 открыт"
    else
        check_warn "HTTPS порт 443 не найден в правилах"
    fi
    
    # Проверка что 5432 НЕ открыт публично
    if echo "${ufw_status}" | grep -qE "5432.*ALLOW"; then
        check_warn "PostgreSQL порт 5432 открыт (должен быть закрыт)"
    else
        check_pass "PostgreSQL порт 5432 не открыт публично"
    fi
    
    # Default policy
    if echo "${ufw_status}" | grep -q "Default: deny (incoming)"; then
        check_pass "Default policy: deny incoming"
    else
        check_fail "Default policy не настроена правильно"
    fi
}

# =============================================================================
# Проверка Fail2ban
# =============================================================================

check_fail2ban() {
    section_header "Fail2ban"
    
    if ! command -v fail2ban-client &>/dev/null; then
        check_fail "Fail2ban не установлен"
        return
    fi
    
    # Статус службы
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        check_pass "Fail2ban служба активна"
    else
        check_fail "Fail2ban служба не активна"
    fi
    
    # Статус SSH jail
    if fail2ban-client status sshd 2>/dev/null | grep -q "Active"; then
        check_pass "SSH jail активен"
    else
        check_warn "SSH jail не активен"
    fi
    
    # Проверка конфигурации
    if [[ -f /etc/fail2ban/jail.local ]]; then
        check_pass "jail.local существует"
    else
        check_warn "jail.local не найден"
    fi
}

# =============================================================================
# Проверка Sysctl настроек
# =============================================================================

check_sysctl() {
    section_header "Kernel Sysctl Settings"
    
    # IP Forwarding (должен быть включён для Docker)
    local ip_forward
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [[ "${ip_forward}" == "1" ]]; then
        check_pass "IP forwarding включён (требуется для Docker)"
    else
        check_fail "IP forwarding отключён (Docker не будет работать)"
    fi
    
    # SYN cookies
    local syn_cookies
    syn_cookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "0")
    if [[ "${syn_cookies}" == "1" ]]; then
        check_pass "SYN cookies включены"
    else
        check_warn "SYN cookies отключены"
    fi
    
    # Accept redirects
    local accept_redirects
    accept_redirects=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null || echo "1")
    if [[ "${accept_redirects}" == "0" ]]; then
        check_pass "ICMP redirects отключены"
    else
        check_warn "ICMP redirects включены"
    fi
    
    # Send redirects
    local send_redirects
    send_redirects=$(sysctl -n net.ipv4.conf.all.send_redirects 2>/dev/null || echo "1")
    if [[ "${send_redirects}" == "0" ]]; then
        check_pass "Отправка ICMP redirects отключена"
    else
        check_warn "Отправка ICMP redirects включена"
    fi
    
    # RP filter
    local rp_filter
    rp_filter=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "0")
    if [[ "${rp_filter}" != "0" ]]; then
        check_pass "Reverse path filtering включён"
    else
        check_warn "Reverse path filtering отключён"
    fi
    
    # ASLR
    local aslr
    aslr=$(sysctl -n kernel.randomize_va_space 2>/dev/null || echo "0")
    if [[ "${aslr}" == "2" ]]; then
        check_pass "ASLR включён (full)"
    elif [[ "${aslr}" == "1" ]]; then
        check_warn "ASLR включён частично"
    else
        check_fail "ASLR отключён"
    fi
}

# =============================================================================
# Проверка Docker статуса
# =============================================================================

check_docker() {
    section_header "Docker Status"
    
    if ! command -v docker &>/dev/null; then
        check_fail "Docker не установлен"
        return
    fi
    
    # Статус службы
    if systemctl is-active --quiet docker 2>/dev/null; then
        check_pass "Docker служба активна"
    else
        check_fail "Docker служба не активна"
    fi
    
    # Проверка docker socket
    if [[ -S /var/run/docker.sock ]]; then
        local perms
        perms=$(stat -c %a /var/run/docker.sock)
        if [[ "${perms}" == "660" ]]; then
            check_pass "Docker socket имеет правильные права (660)"
        else
            check_warn "Docker socket имеет права: ${perms}"
        fi
    else
        check_warn "Docker socket не найден"
    fi
    
    # Проверка работающих контейнеров
    local running_containers
    running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l)
    if [[ "${running_containers}" -gt 0 ]]; then
        check_pass "Запущено контейнеров: ${running_containers}"
    else
        check_warn "Нет запущенных контейнеров"
    fi
}

# =============================================================================
# Проверка открытых портов
# =============================================================================

check_open_ports() {
    section_header "Open Ports"
    
    local listening_ports
    listening_ports=$(ss -tlnp 2>/dev/null)
    
    echo "Прослушиваемые порты:"
    echo "${listening_ports}" | grep LISTEN | head -20
    
    # Проверка критических портов
    if echo "${listening_ports}" | grep -q ":22 "; then
        check_pass "SSH (22) слушает"
    else
        check_warn "SSH (22) не слушает"
    fi
    
    if echo "${listening_ports}" | grep -q ":80 "; then
        check_pass "HTTP (80) слушает"
    else
        check_warn "HTTP (80) не слушает"
    fi
    
    if echo "${listening_ports}" | grep -q ":443 "; then
        check_pass "HTTPS (443) слушает"
    else
        check_warn "HTTPS (443) не слушает"
    fi
    
    # Проверка что 5432 не слушает на всех интерфейсах
    if echo "${listening_ports}" | grep -qE "0\.0\.0\.0:5432|:5432.*LISTEN"; then
        check_warn "PostgreSQL (5432) слушает на всех интерфейсах!"
    else
        check_pass "PostgreSQL (5432) не открыт наружу"
    fi
}

# =============================================================================
# Проверка sudo конфигурации
# =============================================================================

check_sudo() {
    section_header "Sudo Configuration"
    
    # Проверка файла sudoers
    if visudo -c &>/dev/null; then
        check_pass "sudoers файл валиден"
    else
        check_fail "sudoers файл содержит ошибки"
    fi
    
    # Проверка логов sudo
    if [[ -f /var/log/sudo.log ]]; then
        check_pass "Логирование sudo включено"
    else
        check_warn "Логирование sudo не настроено"
    fi
    
    # Проверка что у root есть пароль
    if passwd -S root 2>/dev/null | grep -qE "^root (L|LK)"; then
        check_warn "Root аккаунт заблокирован (рекомендуется для безопасности)"
    else
        check_info "Root аккаунт активен"
    fi
}

# =============================================================================
# Проверка world-writable файлов
# =============================================================================

check_world_writable() {
    section_header "World-Writable Files"
    
    local ww_files
    ww_files=$(find / -type f -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | wc -l)
    
    if [[ "${ww_files}" -eq 0 ]]; then
        check_pass "World-writable файлы не найдены"
    elif [[ "${ww_files}" -lt 10 ]]; then
        check_warn "Найдено world-writable файлов: ${ww_files}"
    else
        check_fail "Много world-writable файлов: ${ww_files}"
    fi
    
    # World-writable директории без sticky bit
    local ww_dirs
    ww_dirs=$(find / -type d -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | wc -l)
    
    if [[ "${ww_dirs}" -eq 0 ]]; then
        check_pass "World-writable директории без sticky bit не найдены"
    else
        check_warn "Найдено world-writable директорий: ${ww_dirs}"
    fi
}

# =============================================================================
# Проверка обновлений системы
# =============================================================================

check_updates() {
    section_header "System Updates"
    
    # Проверка доступных обновлений безопасности
    local updates
    updates=$(apt-get upgrade --dry-run 2>/dev/null | grep -c "Inst" || echo "0")
    
    if [[ "${updates}" -eq 0 ]]; then
        check_pass "Система обновлена"
    elif [[ "${updates}" -lt 20 ]]; then
        check_warn "Доступно обновлений: ${updates}"
    else
        check_fail "Много доступных обновлений: ${updates}"
    fi
    
    # Проверка unattended-upgrades
    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        check_pass "Автоматические обновления включены"
    else
        check_warn "Автоматические обновления не активны"
    fi
}

# =============================================================================
# Проверка логов и аудита
# =============================================================================

check_logging() {
    section_header "Logging & Auditing"
    
    # Auditd
    if systemctl is-active --quiet auditd 2>/dev/null; then
        check_pass "Auditd активен"
    else
        check_warn "Auditd не активен"
    fi
    
    # Rsyslog
    if systemctl is-active --quiet rsyslog 2>/dev/null; then
        check_pass "Rsyslog активен"
    else
        check_warn "Rsyslog не активен"
    fi
    
    # Journald
    if systemctl is-active --quiet systemd-journald 2>/dev/null; then
        check_pass "Journald активен"
    else
        check_warn "Journald не активен"
    fi
    
    # Проверка размера логов
    local log_size
    log_size=$(du -sh /var/log 2>/dev/null | cut -f1)
    check_info "Размер /var/log: ${log_size}"
}

# =============================================================================
# Генерация итогового отчёта
# =============================================================================

generate_summary() {
    section_header "Security Summary"
    
    local total=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
    local score=$((PASS_COUNT * 100 / total))
    
    echo ""
    echo "============================================"
    echo "ИТОГОВЫЙ ОТЧЁТ"
    echo "============================================"
    echo ""
    echo -e "Всего проверок: ${total}"
    echo -e "${GREEN}Прошло: ${PASS_COUNT}${NC}"
    echo -e "${YELLOW}Предупреждения: ${WARN_COUNT}${NC}"
    echo -e "${RED}Не прошло: ${FAIL_COUNT}${NC}"
    echo ""
    echo "Оценка безопасности: ${score}%"
    echo ""
    
    if [[ ${score} -ge 90 ]]; then
        echo -e "${GREEN}Отличный результат!${NC}"
    elif [[ ${score} -ge 70 ]]; then
        echo -e "${YELLOW}Хорошо, но есть что улучшить${NC}"
    elif [[ ${score} -ge 50 ]]; then
        echo -e "${YELLOW}Требуются улучшения${NC}"
    else
        echo -e "${RED}Критические проблемы безопасности!${NC}"
    fi
    
    echo ""
    echo "============================================"
    
    # Запись в отчёт
    {
        echo ""
        echo "============================================"
        echo "ИТОГОВЫЙ ОТЧЁТ"
        echo "============================================"
        echo "Всего проверок: ${total}"
        echo "Прошло: ${PASS_COUNT}"
        echo "Предупреждения: ${WARN_COUNT}"
        echo "Не прошло: ${FAIL_COUNT}"
        echo "Оценка безопасности: ${score}%"
        echo "Дата проверки: $(date '+%Y-%m-%d %H:%M:%S')"
    } >> "${REPORT_FILE}"
    
    echo ""
    echo "Полный отчёт сохранён: ${REPORT_FILE}"
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Создание директорий
    mkdir -p "$(dirname "${LOG_FILE}")"
    mkdir -p "$(dirname "${REPORT_FILE}")"
    
    # Заголовок
    echo ""
    echo "=============================================="
    echo "  Security Validation Script"
    echo "  Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Хост: $(hostname)"
    echo "=============================================="
    echo ""
    
    # Начало отчёта
    {
        echo "========================================"
        echo "Security Validation Report"
        echo "Host: $(hostname)"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
    } > "${REPORT_FILE}"
    
    # Запуск проверок
    check_ssh
    check_firewall
    check_fail2ban
    check_sysctl
    check_docker
    check_open_ports
    check_sudo
    check_world_writable
    check_updates
    check_logging
    
    # Итоговый отчёт
    generate_summary
}

# Запуск основной функции
main "$@"
