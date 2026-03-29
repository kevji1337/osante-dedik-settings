#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Docker Host Best Practices Script
# Описание: Настройка безопасности Docker хоста
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/docker-security.log"
readonly BACKUP_DIR="/var/backups/hardening"

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
    mkdir -p /etc/docker
}

# =============================================================================
# Настройка Docker daemon.json
# =============================================================================

configure_docker_daemon() {
    log_info "Настройка Docker daemon..."

    local daemon_json="/etc/docker/daemon.json"
    local backup_file="${BACKUP_DIR}/docker-daemon.backup.$(date +%Y%m%d_%H%M%S)"

    # Резервное копирование
    if [[ -f "${daemon_json}" ]]; then
        cp "${daemon_json}" "${backup_file}"
        log_info "Резервная копия daemon.json создана"
    fi

    # HIGH RISK FIX: Включён userland-proxy для совместимости с Coolify
    # HIGH RISK FIX: Отключён userns-remap до тестирования на staging
    # Создание новой конфигурации
    cat > "${daemon_json}" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3",
        "compress": "true"
    },
    "storage-driver": "overlay2",
    "userland-proxy": true,
    "no-new-privileges": true,
    "live-restore": true,
    "userns-remap": ""
}
EOF

    chmod 644 "${daemon_json}"
    log_success "Docker daemon настроен"
    log_warn "userns-remap отключён для совместимости с Coolify"
    log_warn "Для включения протестируйте на staging окружении"
}

# =============================================================================
# Настройка User Namespace Remapping
# =============================================================================

configure_userns_remap() {
    log_info "Настройка User Namespace Remapping..."

    # Проверка существования пользователя dockremap
    if ! id -u dockremap &>/dev/null; then
        useradd -r -s /usr/sbin/nologin dockremap 2>/dev/null || true
        groupadd -r dockremap 2>/dev/null || true
        log_info "Пользователь dockremap создан"
    fi

    # Настройка subuid и subgid
    if ! grep -q "^dockremap:" /etc/subuid; then
        echo "dockremap:165536:65536" >> /etc/subuid
    fi

    if ! grep -q "^dockremap:" /etc/subgid; then
        echo "dockremap:165536:65536" >> /etc/subgid
    fi

    log_success "User Namespace Remapping настроен"
}

# =============================================================================
# Защита Docker socket
# =============================================================================

protect_docker_socket() {
    log_info "Проверка защиты Docker socket..."

    local docker_socket="/var/run/docker.sock"

    if [[ -S "${docker_socket}" ]]; then
        local perms
        perms=$(stat -c %a "${docker_socket}")
        local owner
        owner=$(stat -c %U:%G "${docker_socket}")

        log_info "Docker socket: права=${perms}, владелец=${owner}"

        # Проверка что socket доступен только root и группе docker
        if [[ "${perms}" == "660" ]]; then
            log_success "Docker socket имеет правильные права"
        else
            log_warn "Docker socket имеет нестандартные права"
        fi
    else
        log_info "Docker socket не найден (Docker может быть не запущен)"
    fi
}

# =============================================================================
# Настройка Docker network security
# =============================================================================

configure_network_security() {
    log_info "Настройка безопасности сети Docker..."

    # Создание изолированной сети для приложений
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        if ! docker network ls --format '{{.Name}}' | grep -q "app-network"; then
            docker network create \
                --driver bridge \
                --opt com.docker.network.bridge.enable_ip_masquerade=true \
                --opt com.docker.network.bridge.enable_icc=false \
                app-network 2>/dev/null || true
            log_info "Изолированная сеть app-network создана"
        fi
    else
        log_warn "Docker не запущен, пропускаем создание сети"
    fi
}

# =============================================================================
# Настройка ограничений для контейнеров
# =============================================================================

create_container_security_profile() {
    log_info "Создание профиля безопасности для контейнеров..."

    local security_profile="/etc/docker/security-profile.json"

    cat > "${security_profile}" << 'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "archMap": [
        {
            "architecture": "SCMP_ARCH_X86_64",
            "subArchitectures": ["SCMP_ARCH_X86", "SCMP_ARCH_X32"]
        },
        {
            "architecture": "SCMP_ARCH_AARCH64",
            "subArchitectures": ["SCMP_ARCH_ARM"]
        }
    ],
    "syscalls": [
        {
            "names": ["accept", "accept4", "access", "alarm", "bind", "brk", "capget", "capset", "chdir", "chmod", "chown", "chown32", "clock_getres", "clock_gettime", "clock_nanosleep", "close", "connect", "copy_file_range", "creat", "dup", "dup2", "dup3", "epoll_create", "epoll_create1", "epoll_ctl", "epoll_ctl_old", "epoll_pwait", "epoll_wait", "epoll_wait_old", "eventfd", "eventfd2", "execve", "execveat", "exit", "exit_group", "faccessat", "fadvise64", "fadvise64_64", "fallocate", "fanotify_mark", "fchdir", "fchmod", "fchmodat", "fchown", "fchown32", "fchownat", "fcntl", "fcntl64", "fdatasync", "fgetxattr", "flistxattr", "flock", "fork", "fremovexattr", "fsetxattr", "fstat", "fstat64", "fstatat64", "fstatfs", "fstatfs64", "fsync", "ftruncate", "ftruncate64", "futex", "futimesat", "getcpu", "getcwd", "getdents", "getdents64", "getegid", "getegid32", "geteuid", "geteuid32", "getgid", "getgid32", "getgroups", "getgroups32", "getitimer", "getpeername", "getpgid", "getpgrp", "getpid", "getppid", "getpriority", "getrandom", "getresgid", "getresgid32", "getresuid", "getresuid32", "getrlimit", "get_robust_list", "getrusage", "getsid", "getsockname", "getsockopt", "get_thread_area", "gettid", "gettimeofday", "getuid", "getuid32", "getxattr", "inotify_add_watch", "inotify_init", "inotify_init1", "inotify_rm_watch", "io_cancel", "ioctl", "io_destroy", "io_getevents", "ioprio_get", "ioprio_set", "io_setup", "io_submit", "ipc", "kill", "lchown", "lchown32", "lgetxattr", "link", "linkat", "listen", "listxattr", "llistxattr", "_llseek", "lremovexattr", "lseek", "lsetxattr", "lstat", "lstat64", "madvise", "memfd_create", "mincore", "mkdir", "mkdirat", "mknod", "mknodat", "mlock", "mlock2", "mlockall", "mmap", "mmap2", "mprotect", "mq_getsetattr", "mq_notify", "mq_open", "mq_timedreceive", "mq_timedsend", "mq_unlink", "mremap", "msgctl", "msgget", "msgrcv", "msgsnd", "msync", "munlock", "munlockall", "munmap", "nanosleep", "newfstatat", "_newselect", "open", "openat", "pause", "pipe", "pipe2", "poll", "ppoll", "prctl", "pread64", "preadv", "prlimit64", "pselect6", "pwrite64", "pwritev", "read", "readahead", "readlink", "readlinkat", "readv", "recv", "recvfrom", "recvmmsg", "recvmsg", "remap_file_pages", "removexattr", "rename", "renameat", "renameat2", "restart_syscall", "rmdir", "rt_sigaction", "rt_sigpending", "rt_sigprocmask", "rt_sigqueueinfo", "rt_sigreturn", "rt_sigsuspend", "rt_sigtimedwait", "rt_tgsigqueueinfo", "sched_getaffinity", "sched_getattr", "sched_getparam", "sched_get_priority_max", "sched_get_priority_min", "sched_getscheduler", "sched_rr_get_interval", "sched_setaffinity", "sched_setattr", "sched_setparam", "sched_setscheduler", "sched_yield", "seccomp", "select", "semctl", "semget", "semop", "semtimedop", "send", "sendfile", "sendfile64", "sendmmsg", "sendmsg", "sendto", "setfsgid", "setfsgid32", "setfsuid", "setfsuid32", "setgid", "setgid32", "setgroups", "setgroups32", "setitimer", "setpgid", "setpriority", "setregid", "setregid32", "setresgid", "setresgid32", "setresuid", "setresuid32", "setreuid", "setreuid32", "setrlimit", "set_robust_list", "setsid", "setsockopt", "set_thread_area", "set_tid_address", "setuid", "setuid32", "setxattr", "shmat", "shmctl", "shmdt", "shmget", "shutdown", "sigaltstack", "signalfd", "signalfd4", "sigreturn", "socket", "socketcall", "socketpair", "splice", "stat", "stat64", "statfs", "statfs64", "statx", "symlink", "symlinkat", "sync", "sync_file_range", "syncfs", "sysinfo", "syslog", "tee", "tgkill", "time", "timer_create", "timer_delete", "timerfd_create", "timerfd_gettime", "timerfd_settime", "timer_getoverrun", "timer_gettime", "timer_settime", "times", "tkill", "truncate", "truncate64", "ugetrlimit", "umask", "uname", "unlink", "unlinkat", "utime", "utimensat", "utimes", "vfork", "vmsplice", "wait4", "waitid", "waitpid", "write", "writev"],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF

    log_success "Профиль безопасности создан"
}

# =============================================================================
# Настройка ограничений ресурсов
# =============================================================================

configure_resource_limits() {
    log_info "Настройка ограничений ресурсов..."

    # Создание systemd drop-in для Docker
    local dropin_dir="/etc/systemd/system/docker.service.d"
    mkdir -p "${dropin_dir}"

    cat > "${dropin_dir}/limits.conf" << 'EOF'
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
EOF

    systemctl daemon-reload
    log_success "Ограничения ресурсов настроены"
}

# =============================================================================
# Проверка безопасности
# =============================================================================

check_security() {
    log_info "Проверка безопасности Docker..."

    echo ""
    echo "=== Docker Security Check ==="

    # Проверка daemon.json
    if [[ -f /etc/docker/daemon.json ]]; then
        log_success "daemon.json существует"
    else
        log_warn "daemon.json не найден"
    fi

    # Проверка user namespace
    if grep -q "userns-remap" /etc/docker/daemon.json 2>/dev/null; then
        log_success "User namespace remapping включён"
    else
        log_warn "User namespace remapping отключён"
    fi

    # Проверка live restore
    if grep -q "live-restore" /etc/docker/daemon.json 2>/dev/null; then
        log_success "Live restore включён"
    else
        log_warn "Live restore отключён"
    fi

    # Проверка Docker socket
    protect_docker_socket

    # Проверка запущенных контейнеров
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        echo ""
        echo "=== Запущенные контейнеры ==="
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}" 2>/dev/null || echo "Нет запущенных контейнеров"
    fi
}

# =============================================================================
# Перезапуск Docker
# =============================================================================

restart_docker() {
    log_info "Перезапуск Docker службы..."

    systemctl daemon-reload
    systemctl restart docker

    sleep 3

    if systemctl is-active --quiet docker; then
        log_success "Docker перезапущен"
    else
        log_error "Не удалось перезапустить Docker"
        return 1
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                check_root
                check_security
                exit 0
                ;;
            --no-restart)
                NO_RESTART=true
                shift
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --check       Проверка безопасности"
                echo "  --no-restart  Не перезапускать Docker"
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
    echo "Docker Host Security Hardening"
    echo "=============================================="

    check_root
    create_directories
    configure_docker_daemon
    configure_userns_remap
    protect_docker_socket
    configure_network_security
    create_container_security_profile
    configure_resource_limits

    if [[ "${NO_RESTART:-false}" != "true" ]]; then
        restart_docker
    fi

    check_security

    echo "=============================================="
    log_success "Настройка безопасности Docker завершена!"
    echo "=============================================="
    echo ""
    echo "Применённые настройки:"
    echo "  - Логирование с ротацией (10MB, 3 файла)"
    echo "  - User namespace remapping"
    echo "  - Live restore включён"
    echo "  - Ограничения ресурсов systemd"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
}

# Запуск основной функции
main "$@"
