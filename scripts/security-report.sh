#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Security Report Generator
# Описание: Генерация полного отчёта о безопасности сервера
# Использование: ./security-report.sh [--output file.txt]
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly OUTPUT_FILE="${1:-/var/log/server-hardening/security-report.$(date +%Y%m%d_%H%M%S).txt}"
readonly DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Цвета
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Счётчики
PASS=0
WARN=0
FAIL=0

# =============================================================================
# Functions
# =============================================================================

section() {
    local title="$1"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  ${title}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo "" | tee -a "${OUTPUT_FILE}"
    echo "═══════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
    echo "  ${title}" >> "${OUTPUT_FILE}"
    echo "═══════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
}

pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    echo "  [PASS] $1" >> "${OUTPUT_FILE}"
    ((PASS++))
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    echo "  [WARN] $1" >> "${OUTPUT_FILE}"
    ((WARN++))
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    echo "  [FAIL] $1" >> "${OUTPUT_FILE}"
    ((FAIL++))
}

info() {
    echo -e "  ℹ $1"
    echo "  [INFO] $1" >> "${OUTPUT_FILE}"
}

# =============================================================================
# Checks
# =============================================================================

check_system() {
    section "System Information"

    info "Hostname: $(hostname)"
    info "Kernel: $(uname -r)"
    info "Ubuntu: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    info "Uptime: $(uptime -p 2>/dev/null || uptime)"

    # Check updates
    local updates
    updates=$(apt-get upgrade --dry-run 2>/dev/null | grep -c "Inst" || echo "0")
    if [[ "${updates}" -eq 0 ]]; then
        pass "System is up to date"
    else
        warn "${updates} updates available"
    fi
}

check_ssh() {
    section "SSH Configuration"

    local sshd_config="/etc/ssh/sshd_config"

    if [[ ! -f "${sshd_config}" ]]; then
        fail "sshd_config not found"
        return
    fi

    grep -qE "^PermitRootLogin\s+no" "${sshd_config}" && pass "Root login disabled" || fail "Root login not disabled"
    grep -qE "^PasswordAuthentication\s+no" "${sshd_config}" && pass "Password auth disabled" || fail "Password auth not disabled"
    grep -qE "^PubkeyAuthentication\s+yes" "${sshd_config}" && pass "Key auth enabled" || warn "Key auth not explicitly enabled"
    grep -qE "^MaxAuthTries\s+[1-5]$" "${sshd_config}" && pass "MaxAuthTries limited" || warn "MaxAuthTries not limited"
    grep -qE "^X11Forwarding\s+no" "${sshd_config}" && pass "X11Forwarding disabled" || warn "X11Forwarding not disabled"

    if sshd -t 2>/dev/null; then
        pass "SSH config is valid"
    else
        fail "SSH config has errors"
    fi
}

check_firewall() {
    section "Firewall (UFW)"

    if ! command -v ufw &>/dev/null; then
        fail "UFW not installed"
        return
    fi

    if ufw status 2>/dev/null | grep -q "Status: active"; then
        pass "UFW is active"
    else
        fail "UFW is not active"
        return
    fi

    local status
    status=$(ufw status 2>/dev/null)

    echo "${status}" | grep -q "22/tcp.*ALLOW" && pass "SSH (22) open" || warn "SSH (22) not in rules"
    echo "${status}" | grep -q "80/tcp.*ALLOW" && pass "HTTP (80) open" || warn "HTTP (80) not in rules"
    echo "${status}" | grep -q "443/tcp.*ALLOW" && pass "HTTPS (443) open" || warn "HTTPS (443) not in rules"

    if echo "${status}" | grep -qE "5432.*ALLOW"; then
        warn "PostgreSQL (5432) is publicly accessible!"
    else
        pass "PostgreSQL (5432) not exposed"
    fi

    echo "${status}" | grep -q "Default: deny (incoming)" && pass "Default policy: deny" || fail "Default policy not secure"
}

check_fail2ban() {
    section "Fail2ban"

    if ! command -v fail2ban-client &>/dev/null; then
        fail "Fail2ban not installed"
        return
    fi

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        pass "Fail2ban service is running"
    else
        fail "Fail2ban service is not running"
    fi

    if fail2ban-client status sshd 2>/dev/null | grep -q "Active"; then
        pass "SSH jail is active"
        local banned
        banned=$(fail2ban-client get sshd banip 2>/dev/null | wc -l || echo "0")
        info "Currently banned IPs: $((banned - 1))"
    else
        warn "SSH jail is not active"
    fi
}

check_kernel() {
    section "Kernel Hardening"

    # IP Forwarding
    local ip_forward
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
    if [[ "${ip_forward}" == "1" ]]; then
        pass "IP forwarding enabled (required for Docker)"
    else
        fail "IP forwarding disabled"
    fi

    # SYN cookies
    local syn_cookies
    syn_cookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "0")
    [[ "${syn_cookies}" == "1" ]] && pass "SYN cookies enabled" || warn "SYN cookies disabled"

    # Redirects
    local accept_redirects
    accept_redirects=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null || echo "1")
    [[ "${accept_redirects}" == "0" ]] && pass "ICMP redirects disabled" || warn "ICMP redirects enabled"

    local send_redirects
    send_redirects=$(sysctl -n net.ipv4.conf.all.send_redirects 2>/dev/null || echo "1")
    [[ "${send_redirects}" == "0" ]] && pass "Sending redirects disabled" || warn "Sending redirects enabled"

    # RP filter
    local rp_filter
    rp_filter=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo "0")
    [[ "${rp_filter}" != "0" ]] && pass "Reverse path filtering enabled" || warn "Reverse path filtering disabled"

    # ASLR
    local aslr
    aslr=$(sysctl -n kernel.randomize_va_space 2>/dev/null || echo "0")
    [[ "${aslr}" == "2" ]] && pass "ASLR full" || [[ "${aslr}" == "1" ]] && warn "ASLR partial" || fail "ASLR disabled"
}

check_docker() {
    section "Docker Security"

    if ! command -v docker &>/dev/null; then
        info "Docker not installed (skip if not needed)"
        return
    fi

    if systemctl is-active --quiet docker 2>/dev/null; then
        pass "Docker service is running"
    else
        warn "Docker service is not running"
    fi

    # Docker socket
    if [[ -S /var/run/docker.sock ]]; then
        local perms
        perms=$(stat -c %a /var/run/docker.sock)
        [[ "${perms}" == "660" ]] && pass "Docker socket permissions correct" || warn "Docker socket permissions: ${perms}"
    fi

    # User namespace
    if grep -q "userns-remap" /etc/docker/daemon.json 2>/dev/null; then
        pass "User namespace remapping enabled"
    else
        warn "User namespace remapping not enabled"
    fi

    # Running containers
    local containers
    containers=$(docker ps --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")
    info "Running containers: ${containers}"
}

check_filesystem() {
    section "Filesystem Security"

    # World-writable files
    local ww_files
    ww_files=$(find / -type f -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | wc -l)
    [[ "${ww_files}" -eq 0 ]] && pass "No world-writable files" || warn "${ww_files} world-writable files found"

    # World-writable directories
    local ww_dirs
    ww_dirs=$(find / -type d -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | wc -l)
    [[ "${ww_dirs}" -eq 0 ]] && pass "No world-writable directories" || warn "${ww_dirs} world-writable directories"

    # Critical files
    [[ "$(stat -c %a /etc/passwd 2>/dev/null)" == "644" ]] && pass "/etc/passwd permissions correct" || warn "/etc/passwd permissions incorrect"
    [[ "$(stat -c %a /etc/shadow 2>/dev/null)" =~ ^(640|600)$ ]] && pass "/etc/shadow permissions correct" || warn "/etc/shadow permissions incorrect"
    [[ "$(stat -c %a /etc/ssh/sshd_config 2>/dev/null)" == "600" ]] && pass "sshd_config permissions correct" || warn "sshd_config permissions incorrect"
}

check_logging() {
    section "Logging & Auditing"

    systemctl is-active --quiet auditd 2>/dev/null && pass "Auditd is running" || warn "Auditd is not running"
    systemctl is-active --quiet rsyslog 2>/dev/null && pass "Rsyslog is running" || warn "Rsyslog is not running"
    systemctl is-active --quiet systemd-journald 2>/dev/null && pass "Journald is running" || warn "Journald is not running"

    # Log size
    local log_size
    log_size=$(du -sh /var/log 2>/dev/null | cut -f1 || echo "unknown")
    info "Log directory size: ${log_size}"
}

check_services() {
    section "Critical Services"

    local services=(ssh docker ufw fail2ban auditd prometheus alertmanager node-exporter)

    for service in "${services[@]}"; do
        if systemctl is-active --quiet "${service}" 2>/dev/null; then
            pass "${service} is running"
        elif systemctl list-unit-files | grep -q "^${service}"; then
            warn "${service} is installed but not running"
        else
            info "${service} not installed"
        fi
    done
}

generate_summary() {
    section "Security Summary"

    local total=$((PASS + WARN + FAIL))
    local score=0

    if [[ ${total} -gt 0 ]]; then
        score=$((PASS * 100 / total))
    fi

    echo ""
    echo "  ┌─────────────────────────────────────┐"
    echo "  │  Total Checks:  $(printf "%-18d" ${total})│"
    echo "  │  ${GREEN}Passed:${NC}        $(printf "%-18d" ${PASS})│"
    echo "  │  ${YELLOW}Warnings:${NC}      $(printf "%-18d" ${WARN})│"
    echo "  │  ${RED}Failed:${NC}        $(printf "%-18d" ${FAIL})│"
    echo "  ├─────────────────────────────────────┤"
    echo "  │  Security Score: $(printf "%-16d" ${score})%│"
    echo "  └─────────────────────────────────────┘"

    echo "" >> "${OUTPUT_FILE}"
    echo "═══════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
    echo "  Security Summary" >> "${OUTPUT_FILE}"
    echo "═══════════════════════════════════════════════════════════" >> "${OUTPUT_FILE}"
    echo "  Total Checks:  ${total}" >> "${OUTPUT_FILE}"
    echo "  Passed:        ${PASS}" >> "${OUTPUT_FILE}"
    echo "  Warnings:      ${WARN}" >> "${OUTPUT_FILE}"
    echo "  Failed:        ${FAIL}" >> "${OUTPUT_FILE}"
    echo "  Score:         ${score}%" >> "${OUTPUT_FILE}"
    echo "  Generated:     ${DATE}" >> "${OUTPUT_FILE}"

    if [[ ${score} -ge 90 ]]; then
        echo -e "\n  ${GREEN}Excellent! Your server is well hardened.${NC}"
    elif [[ ${score} -ge 70 ]]; then
        echo -e "\n  ${YELLOW}Good, but some improvements recommended.${NC}"
    elif [[ ${score} -ge 50 ]]; then
        echo -e "\n  ${YELLOW}Several security issues need attention.${NC}"
    else
        echo -e "\n  ${RED}Critical! Immediate action required.${NC}"
    fi

    echo ""
    echo "  Full report saved to: ${OUTPUT_FILE}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    mkdir -p "$(dirname "${OUTPUT_FILE}")"

    # Header
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Server Security Report Generator                   ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Date: ${DATE}"
    echo "  Host: $(hostname)"
    echo "  Output: ${OUTPUT_FILE}"
    echo ""

    # Initialize report file
    {
        echo "═══════════════════════════════════════════════════════════"
        echo "  Server Security Report"
        echo "═══════════════════════════════════════════════════════════"
        echo "  Date: ${DATE}"
        echo "  Host: $(hostname)"
        echo ""
    } > "${OUTPUT_FILE}"

    # Run checks
    check_system
    check_ssh
    check_firewall
    check_fail2ban
    check_kernel
    check_docker
    check_filesystem
    check_logging
    check_services

    # Summary
    generate_summary
}

main "$@"
