#!/bin/bash
set -Eeuo pipefail

# =============================================================================
# Скрипт настройки мониторинга
# Описание: Установка и настройка Prometheus, Node Exporter, Alertmanager
#          с интеграцией Telegram уведомлений
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_FILE="/var/log/server-hardening/monitoring-setup.log"
readonly BACKUP_DIR="/var/backups/hardening"
readonly MONITORING_BASE="/opt/monitoring"
readonly CONFIG_SOURCE="${SCRIPT_DIR}/../configs/monitoring"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Версии компонентов
readonly NODE_EXPORTER_VERSION="1.7.0"
readonly PROMETHEUS_VERSION="2.48.0"
readonly ALERTMANAGER_VERSION="0.26.0"

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
    mkdir -p /var/log/monitoring
    mkdir -p "${MONITORING_BASE}"/{prometheus,alertmanager,node_exporter}
    mkdir -p "${MONITORING_BASE}"/prometheus/{rules,data}
    mkdir -p "${MONITORING_BASE}"/alertmanager/data
    mkdir -p /etc/systemd/system
}

# =============================================================================
# Проверка архитектуры
# =============================================================================

check_architecture() {
    local arch
    arch=$(dpkg --print-architecture)
    
    case "${arch}" in
        amd64)
            ARCH="linux-amd64"
            ;;
        arm64)
            ARCH="linux-arm64"
            ;;
        armhf)
            ARCH="linux-armv7"
            ;;
        *)
            log_error "Неподдерживаемая архитектура: ${arch}"
            exit 1
            ;;
    esac
    
    log_info "Архитектура: ${ARCH}"
}

# =============================================================================
# Установка Node Exporter
# =============================================================================

install_node_exporter() {
    log_info "Установка Node Exporter ${NODE_EXPORTER_VERSION}..."
    
    local download_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Загрузка
    wget -q --show-progress -O "${temp_dir}/node_exporter.tar.gz" "${download_url}"
    
    # Распаковка
    tar -xzf "${temp_dir}/node_exporter.tar.gz" -C "${temp_dir}"
    cp "${temp_dir}/node_exporter-${NODE_EXPORTER_VERSION}.${ARCH}/node_exporter" "${MONITORING_BASE}/node_exporter/"
    chmod +x "${MONITORING_BASE}/node_exporter/node_exporter"
    
    # Создание пользователя
    if ! id -u node_exporter &>/dev/null; then
        useradd --no-create-home --shell /bin/false node_exporter
    fi
    
    chown -R node_exporter:node_exporter "${MONITORING_BASE}/node_exporter"
    
    # Очистка
    rm -rf "${temp_dir}"
    
    log_success "Node Exporter установлен"
}

# =============================================================================
# Установка Prometheus
# =============================================================================

install_prometheus() {
    log_info "Установка Prometheus ${PROMETHEUS_VERSION}..."
    
    local download_url="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.${ARCH}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Загрузка
    wget -q --show-progress -O "${temp_dir}/prometheus.tar.gz" "${download_url}"
    
    # Распаковка
    tar -xzf "${temp_dir}/prometheus.tar.gz" -C "${temp_dir}"
    cp "${temp_dir}/prometheus-${PROMETHEUS_VERSION}.${ARCH}/prometheus" "${MONITORING_BASE}/prometheus/"
    cp "${temp_dir}/prometheus-${PROMETHEUS_VERSION}.${ARCH}/promtool" "${MONITORING_BASE}/prometheus/"
    chmod +x "${MONITORING_BASE}/prometheus"/{prometheus,promtool}
    
    # Создание пользователя
    if ! id -u prometheus &>/dev/null; then
        useradd --no-create-home --shell /bin/false prometheus
    fi
    
    chown -R prometheus:prometheus "${MONITORING_BASE}/prometheus"
    
    # Очистка
    rm -rf "${temp_dir}"
    
    log_success "Prometheus установлен"
}

# =============================================================================
# Установка Alertmanager
# =============================================================================

install_alertmanager() {
    log_info "Установка Alertmanager ${ALERTMANAGER_VERSION}..."
    
    local download_url="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.${ARCH}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Загрузка
    wget -q --show-progress -O "${temp_dir}/alertmanager.tar.gz" "${download_url}"
    
    # Распаковка
    tar -xzf "${temp_dir}/alertmanager.tar.gz" -C "${temp_dir}"
    cp "${temp_dir}/alertmanager-${ALERTMANAGER_VERSION}.${ARCH}"/{alertmanager,amtool} "${MONITORING_BASE}/alertmanager/"
    chmod +x "${MONITORING_BASE}/alertmanager"/{alertmanager,amtool}
    
    # Создание пользователя
    if ! id -u alertmanager &>/dev/null; then
        useradd --no-create-home --shell /bin/false alertmanager
    fi
    
    chown -R alertmanager:alertmanager "${MONITORING_BASE}/alertmanager"
    
    # Очистка
    rm -rf "${temp_dir}"
    
    log_success "Alertmanager установлен"
}

# =============================================================================
# Настройка конфигураций
# =============================================================================

configure_prometheus() {
    log_info "Настройка конфигурации Prometheus..."
    
    # Конфигурация Prometheus
    cat > "${MONITORING_BASE}/prometheus/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'production-server'

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

rule_files:
  - /opt/monitoring/prometheus/rules/*.yml

scrape_configs:
  # Prometheus сам себя
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter - метрики сервера
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  # Docker cAdvisor (если установлен)
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']
EOF
    
    # Копирование правил алертов
    if [[ -f "${CONFIG_SOURCE}/alert_rules.yml" ]]; then
        cp "${CONFIG_SOURCE}/alert_rules.yml" "${MONITORING_BASE}/prometheus/rules/"
    fi
    
    chown -R prometheus:prometheus "${MONITORING_BASE}/prometheus"
    
    log_success "Конфигурация Prometheus создана"
}

configure_alertmanager() {
    log_info "Настройка конфигурации Alertmanager..."
    
    if [[ -f "${CONFIG_SOURCE}/alertmanager.yml" ]]; then
        cp "${CONFIG_SOURCE}/alertmanager.yml" "${MONITORING_BASE}/alertmanager/"
        chown alertmanager:alertmanager "${MONITORING_BASE}/alertmanager/alertmanager.yml"
    fi
    
    log_success "Конфигурация Alertmanager создана"
}

# =============================================================================
# Создание systemd служб
# =============================================================================

create_systemd_services() {
    log_info "Создание systemd служб..."
    
    # Node Exporter service
    cat > /etc/systemd/system/node-exporter.service << 'EOF'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/opt/monitoring/node_exporter/node_exporter \
    --web.listen-address=":9100" \
    --collector.systemd \
    --collector.docker \
    --path.rootfs=/host \
    --no-collector.ipvs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Prometheus service
    cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus Monitoring System
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/monitoring/prometheus/prometheus \
    --config.file=/opt/monitoring/prometheus/prometheus.yml \
    --storage.tsdb.path=/opt/monitoring/prometheus/data \
    --storage.tsdb.retention.time=15d \
    --web.listen-address=":9090" \
    --web.enable-lifecycle
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Alertmanager service
    cat > /etc/systemd/system/alertmanager.service << 'EOF'
[Unit]
Description=Prometheus Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/opt/monitoring/alertmanager/alertmanager \
    --config.file=/opt/monitoring/alertmanager/alertmanager.yml \
    --storage.path=/opt/monitoring/alertmanager/data \
    --web.listen-address=":9093" \
    --cluster.listen-address=""
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    # Перезагрузка systemd
    systemctl daemon-reload
    
    log_success "Systemd службы созданы"
}

# =============================================================================
# Запуск служб
# =============================================================================

start_services() {
    log_info "Запуск служб мониторинга..."
    
    systemctl enable node-exporter
    systemctl start node-exporter
    
    systemctl enable prometheus
    systemctl start prometheus
    
    systemctl enable alertmanager
    systemctl start alertmanager
    
    sleep 3
    
    # Проверка статуса
    local failed=0
    
    if systemctl is-active --quiet node-exporter; then
        log_success "Node Exporter запущен (порт 9100)"
    else
        log_error "Node Exporter не запустился"
        ((failed++))
    fi
    
    if systemctl is-active --quiet prometheus; then
        log_success "Prometheus запущен (порт 9090)"
    else
        log_error "Prometheus не запустился"
        ((failed++))
    fi
    
    if systemctl is-active --quiet alertmanager; then
        log_success "Alertmanager запущен (порт 9093)"
    else
        log_error "Alertmanager не запустился"
        ((failed++))
    fi
    
    return ${failed}
}

# =============================================================================
# Инструкция по настройке Telegram
# =============================================================================

print_telegram_instructions() {
    echo ""
    echo "=============================================="
    echo "Настройка Telegram уведомлений"
    echo "=============================================="
    echo ""
    echo "1. Создайте бота в Telegram:"
    echo "   - Откройте @BotFather в Telegram"
    echo "   - Отправьте /newbot"
    echo "   - Введите имя и username бота"
    echo "   - Сохраните полученный токен"
    echo ""
    echo "2. Узнайте Chat ID:"
    echo "   - Добавьте бота в ваш чат/канал"
    echo "   - Отправьте любое сообщение"
    echo "   - Перейдите по ссылке: https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates"
    echo "   - Найдите 'chat': {'id': <CHAT_ID>}"
    echo ""
    echo "3. Обновите конфигурацию Alertmanager:"
    echo "   nano ${MONITORING_BASE}/alertmanager/alertmanager.yml"
    echo "   Замените YOUR_BOT_TOKEN и YOUR_CHAT_ID"
    echo ""
    echo "4. Перезапустите Alertmanager:"
    echo "   systemctl restart alertmanager"
    echo ""
    echo "5. Проверьте уведомления:"
    echo "   curl -X POST http://localhost:9093/api/v1/alerts \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '[{\"labels\":{\"alertname\":\"Test\",\"severity\":\"warning\"}}]'"
    echo ""
}

# =============================================================================
# Проверка статуса
# =============================================================================

check_status() {
    echo ""
    echo "=== Статус служб ==="
    systemctl status node-exporter --no-pager -l 2>/dev/null || echo "Node Exporter: не активен"
    echo ""
    systemctl status prometheus --no-pager -l 2>/dev/null || echo "Prometheus: не активен"
    echo ""
    systemctl status alertmanager --no-pager -l 2>/dev/null || echo "Alertmanager: не активен"
    
    echo ""
    echo "=== Прослушиваемые порты ==="
    ss -tlnp | grep -E '9090|9093|9100' || echo "Порты не найдены"
    
    echo ""
    echo "=== Prometheus Targets ==="
    curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets[].labels.job' || echo "Prometheus недоступен"
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
            --telegram)
                print_telegram_instructions
                exit 0
                ;;
            --uninstall)
                log_info "Удаление мониторинга..."
                systemctl stop node-exporter prometheus alertmanager 2>/dev/null || true
                systemctl disable node-exporter prometheus alertmanager 2>/dev/null || true
                rm -f /etc/systemd/system/{node-exporter,prometheus,alertmanager}.service
                rm -rf "${MONITORING_BASE}"
                log_success "Мониторинг удалён"
                exit 0
                ;;
            -h|--help)
                echo "Использование: $0 [опции]"
                echo "Опции:"
                echo "  --status      Показать статус служб"
                echo "  --telegram    Инструкция по настройке Telegram"
                echo "  --uninstall   Удалить мониторинг"
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
    echo "Настройка мониторинга (Prometheus Stack)"
    echo "=============================================="
    
    check_root
    create_directories
    check_architecture
    install_node_exporter
    install_prometheus
    install_alertmanager
    configure_prometheus
    configure_alertmanager
    create_systemd_services
    start_services
    print_telegram_instructions
    
    echo "=============================================="
    log_success "Настройка мониторинга завершена!"
    echo "=============================================="
    echo ""
    echo "Компоненты:"
    echo "  - Node Exporter:  http://localhost:9100/metrics"
    echo "  - Prometheus:     http://localhost:9090"
    echo "  - Alertmanager:   http://localhost:9093"
    echo ""
    echo "Лог файл: ${LOG_FILE}"
    echo "Данные: ${MONITORING_BASE}"
}

# Запуск основной функции
main "$@"
