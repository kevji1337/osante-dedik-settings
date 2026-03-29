#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# UFW + Docker Compatibility Check Script
# Описание: Проверка что UFW не ломает Docker networking
# Использование: ./scripts/check-ufw-docker.sh
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/ufw-docker-check.log"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Счётчики тестов
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

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
# Функции тестирования
# =============================================================================

test_header() {
    local test_name="$1"
    echo ""
    echo -e "${BLUE}=== ${test_name} ===${NC}"
    log_info "Тест: ${test_name}"
}

test_pass() {
    local test_name="$1"
    echo -e "${GREEN}✓ PASS${NC}: ${test_name}"
    log_success "PASS: ${test_name}"
    ((TESTS_PASSED++))
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    echo -e "${RED}✗ FAIL${NC}: ${test_name}"
    echo "  Причина: ${reason}"
    log_error "FAIL: ${test_name} - ${reason}"
    ((TESTS_FAILED++))
}

test_skip() {
    local test_name="$1"
    local reason="$2"
    echo -e "${YELLOW}○ SKIP${NC}: ${test_name}"
    echo "  Причина: ${reason}"
    log_warn "SKIP: ${test_name} - ${reason}"
    ((TESTS_SKIPPED++))
}

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
# ТЕСТ 1: Проверка UFW статуса
# =============================================================================

test_ufw_status() {
    test_header "UFW Status Check"
    
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$(ufw status 2>&1)
        
        if echo "${ufw_status}" | grep -q "Status: active"; then
            test_pass "UFW активен"
        else
            test_fail "UFW активен" "UFW не активен"
        fi
        
        # Проверка что SSH порт открыт
        if echo "${ufw_status}" | grep -q "22/tcp.*ALLOW"; then
            test_pass "SSH порт 22 открыт"
        else
            test_fail "SSH порт 22 открыт" "Порт 22 не найден в правилах UFW"
        fi
        
        # Проверка что Docker правила есть
        if ufw status | grep -q "docker0"; then
            test_pass "Docker bridge правила присутствуют"
        else
            test_fail "Docker bridge правила присутствуют" "Правила для docker0 не найдены"
        fi
    else
        test_skip "UFW статус" "UFW не установлен"
    fi
}

# =============================================================================
# ТЕСТ 2: Проверка before.rules
# =============================================================================

test_before_rules() {
    test_header "UFW Before Rules Check"
    
    local before_rules="/etc/ufw/before.rules"
    
    if [[ -f "${before_rules}" ]]; then
        # Проверка правил для Docker bridge
        if grep -q "\-A ufw-before-input -i docker0 -j ACCEPT" "${before_rules}"; then
            test_pass "Docker bridge input разрешён"
        else
            test_fail "Docker bridge input разрешён" "Правило не найдено в before.rules"
        fi
        
        if grep -q "\-A ufw-before-output -o docker0 -j ACCEPT" "${before_rules}"; then
            test_pass "Docker bridge output разрешён"
        else
            test_fail "Docker bridge output разрешён" "Правило не найдено в before.rules"
        fi
        
        # Проверка установленных соединений
        if grep -q "ESTABLISHED,RELATED" "${before_rules}"; then
            test_pass "Established/Related соединения разрешены"
        else
            test_fail "Established/Related соединения разрешены" "Правило не найдено"
        fi
        
        # Проверка IP forwarding
        if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
            test_pass "IP forwarding включён"
        else
            test_fail "IP forwarding включён" "net.ipv4.ip_forward не найден в sysctl.conf"
        fi
    else
        test_fail "before.rules существует" "Файл /etc/ufw/before.rules не найден"
    fi
}

# =============================================================================
# ТЕСТ 3: Проверка user.rules
# =============================================================================

test_user_rules() {
    test_header "UFW User Rules Check"
    
    local user_rules="/etc/ufw/user.rules"
    
    if [[ -f "${user_rules}" ]]; then
        # Проверка Docker правил
        if grep -q "\-A ufw-user-input -i docker0 -j ACCEPT" "${user_rules}"; then
            test_pass "Docker user input разрешён"
        else
            test_fail "Docker user input разрешён" "Правило не найдено в user.rules"
        fi
        
        if grep -q "\-A ufw-user-forward -i docker0 -o docker0 -j ACCEPT" "${user_rules}"; then
            test_pass "Docker container-to-container разрешён"
        else
            test_fail "Docker container-to-container разрешён" "Правило не найдено"
        fi
        
        # Проверка Cloudflare IP
        if grep -q "173.245.48.0/20" "${user_rules}"; then
            test_pass "Cloudflare IPv4 диапазоны присутствуют"
        else
            test_fail "Cloudflare IPv4 диапазоны присутствуют" "IP диапазоны не найдены"
        fi
        
        # Проверка блокировки PostgreSQL
        if grep -q "\-\-dport 5432 -j DROP" "${user_rules}"; then
            test_pass "PostgreSQL порт 5432 заблокирован"
        else
            test_fail "PostgreSQL порт 5432 заблокирован" "Правило DROP не найдено"
        fi
    else
        test_fail "user.rules существует" "Файл /etc/ufw/user.rules не найден"
    fi
}

# =============================================================================
# ТЕСТ 4: Проверка Docker networking
# =============================================================================

test_docker_networking() {
    test_header "Docker Networking Check"
    
    if ! command -v docker &>/dev/null; then
        test_skip "Docker networking" "Docker не установлен"
        return
    fi
    
    if ! systemctl is-active --quiet docker; then
        test_skip "Docker networking" "Docker сервис не активен"
        return
    fi
    
    # Проверка что docker0 интерфейс существует
    if ip link show docker0 &>/dev/null; then
        test_pass "Docker bridge интерфейс docker0 существует"
    else
        test_fail "Docker bridge интерфейс docker0 существует" "Интерфейс docker0 не найден"
    fi
    
    # Проверка IP forwarding
    local ip_forward
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    
    if [[ "${ip_forward}" == "1" ]]; then
        test_pass "IP forwarding включён (net.ipv4.ip_forward=1)"
    else
        test_fail "IP forwarding включён" "net.ipv4.ip_forward = ${ip_forward}"
    fi
    
    # Тестовый контейнер (если Docker работает)
    if docker ps &>/dev/null; then
        test_pass "Docker daemon отвечает"
    else
        test_fail "Docker daemon отвечает" "Docker daemon не отвечает"
    fi
}

# =============================================================================
# ТЕСТ 5: Проверка iptables правил Docker
# =============================================================================

test_iptables_docker() {
    test_header "iptables Docker Rules Check"
    
    if ! command -v iptables &>/dev/null; then
        test_skip "iptables rules" "iptables не установлен"
        return
    fi
    
    # Проверка DOCKER цепи
    if iptables -L DOCKER -n &>/dev/null; then
        test_pass "DOCKER iptables цепь существует"
        
        local docker_rules
        docker_rules=$(iptables -L DOCKER -n 2>/dev/null | wc -l)
        
        if [[ "${docker_rules}" -gt 1 ]]; then
            test_pass "DOCKER цепь содержит правила (${docker_rules} правил)"
        else
            test_fail "DOCKER цепь содержит правила" "Цепь пуста"
        fi
    else
        test_fail "DOCKER iptables цепь существует" "Цепь DOCKER не найдена"
    fi
    
    # Проверка FORWARD цепи
    if iptables -L FORWARD -n | grep -q "docker0"; then
        test_pass "FORWARD цепь содержит правила для docker0"
    else
        test_warn "FORWARD цепь содержит правила для docker0" "Правила не найдены (может быть нормально)"
    fi
}

# =============================================================================
# ТЕСТ 6: Проверка Cloudflare Protection
# =============================================================================

test_cloudflare_protection() {
    test_header "Cloudflare Protection Check"
    
    local user_rules="/etc/ufw/user.rules"
    
    if [[ ! -f "${user_rules}" ]]; then
        test_skip "Cloudflare protection" "user.rules не найден"
        return
    fi
    
    # Подсчёт IPv4 диапазонов
    local ipv4_count
    ipv4_count=$(grep -c "\-A ufw-user-input -p tcp -s [0-9].*--dport 80 -j ACCEPT" "${user_rules}" || echo "0")
    
    if [[ "${ipv4_count}" -ge 15 ]]; then
        test_pass "Cloudflare IPv4 диапазоны (${ipv4_count} диапазонов)"
    else
        test_fail "Cloudflare IPv4 диапазоны" "Найдено только ${ipv4_count} диапазонов (ожидалось ≥15)"
    fi
    
    # Подсчёт IPv6 диапазонов
    local ipv6_count
    ipv6_count=$(grep -c "\-A ufw-user-input -p tcp -s [0-9a-f:].*::/32 --dport 80 -j ACCEPT" "${user_rules}" || echo "0")
    
    if [[ "${ipv6_count}" -ge 7 ]]; then
        test_pass "Cloudflare IPv6 диапазоны (${ipv6_count} диапазонов)"
    else
        test_fail "Cloudflare IPv6 диапазоны" "Найдено только ${ipv6_count} диапазонов (ожидалось ≥7)"
    fi
    
    # Проверка блокировки прямого доступа
    if grep -q "\-A ufw-user-input -p tcp --dport 80 -j DROP" "${user_rules}"; then
        test_pass "Прямой доступ к порту 80 заблокирован"
    else
        test_fail "Прямой доступ к порту 80 заблокирован" "Правило DROP не найдено"
    fi
    
    if grep -q "\-A ufw-user-input -p tcp --dport 443 -j DROP" "${user_rules}"; then
        test_pass "Прямой доступ к порту 443 заблокирован"
    else
        test_fail "Прямой доступ к порту 443 заблокирован" "Правило DROP не найдено"
    fi
}

# =============================================================================
# ТЕСТ 7: Проверка Coolify совместимости
# =============================================================================

test_coolify_compatibility() {
    test_header "Coolify Compatibility Check"
    
    # Проверка что Coolify контейнеры существуют (если установлен)
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        if docker ps --format '{{.Names}}' | grep -q "coolify"; then
            test_pass "Coolify контейнеры запущены"
            
            # Проверка что порты Coolify доступны
            if docker port coolify 8000 &>/dev/null; then
                test_pass "Coolify порт 8000 проброшен"
            else
                test_fail "Coolify порт 8000 проброшен" "Порт не найден"
            fi
        else
            test_skip "Coolify контейнеры" "Coolify не установлен"
        fi
    else
        test_skip "Coolify совместимость" "Docker не активен"
    fi
    
    # Проверка что PostgreSQL изолирован
    local user_rules="/etc/ufw/user.rules"
    if grep -q "\-\-dport 5432 -j DROP" "${user_rules}"; then
        test_pass "PostgreSQL порт 5432 заблокирован (Coolify safe)"
    else
        test_fail "PostgreSQL порт 5432 заблокирован" "Правило DROP не найдено"
    fi
}

# =============================================================================
# Итоговый отчёт
# =============================================================================

print_summary() {
    echo ""
    echo "=============================================="
    echo "UFW + Docker Compatibility Check Summary"
    echo "=============================================="
    echo ""
    echo -e "${GREEN}PASSED:${NC}  ${TESTS_PASSED}"
    echo -e "${RED}FAILED:${NC}  ${TESTS_FAILED}"
    echo -e "${YELLOW}SKIPPED:${NC} ${TESTS_SKIPPED}"
    echo ""
    
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    local pass_rate=0
    
    if [[ ${total} -gt 0 ]]; then
        pass_rate=$((TESTS_PASSED * 100 / total))
    fi
    
    echo "Pass Rate: ${pass_rate}%"
    echo ""
    
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
        echo ""
        echo "UFW конфигурация безопасна для Docker и Coolify!"
    else
        echo -e "${RED}✗ SOME TESTS FAILED${NC}"
        echo ""
        echo "Рекомендуется исправить следующие проблемы:"
        echo ""
    fi
    
    echo ""
    echo "Лог файл: ${LOG_FILE}"
    echo ""
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  -h, --help    Показать эту справку"
                exit 0
                ;;
            *)
                log_error "Неизвестная опция: $1"
                exit 1
                ;;
        esac
    done
    
    mkdir -p "$(dirname "${LOG_FILE}")"
    
    echo ""
    echo "=============================================="
    echo "UFW + Docker Compatibility Check"
    echo "=============================================="
    
    check_root
    
    # Запуск тестов
    test_ufw_status
    test_before_rules
    test_user_rules
    test_docker_networking
    test_iptables_docker
    test_cloudflare_protection
    test_coolify_compatibility
    
    # Итоговый отчёт
    print_summary
    
    # Выход с кодом ошибки если есть неудачные тесты
    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Запуск основной функции
main "$@"
