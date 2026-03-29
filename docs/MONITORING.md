# Monitoring Guide - Server Hardening & Infrastructure

Complete guide for monitoring stack setup, configuration, and Telegram alert integration.

## Overview

This monitoring stack provides comprehensive server and container monitoring with real-time Telegram alerts.

### Components

| Component | Port | Description |
|-----------|------|-------------|
| Node Exporter | 9100 | System metrics (CPU, RAM, Disk, Network) |
| Prometheus | 9090 | Metrics collection and storage |
| Alertmanager | 9093 | Alert routing and notifications |
| Grafana | 3000 | Visualization dashboards |
| cAdvisor | 9323 | Docker container metrics |

### Architecture

```
┌─────────────────┐     ┌─────────────────┐
│  Node Exporter  │────▶│   Prometheus    │
│  (port 9100)    │     │   (port 9090)   │
└─────────────────┘     └────────┬────────┘
                                 │
┌─────────────────┐     ┌────────▼────────┐
│    cAdvisor     │────▶│  Alertmanager   │
│  (port 9323)    │     │   (port 9093)   │
└─────────────────┘     └────────┬────────┘
                                 │
┌─────────────────┐     ┌────────▼────────┐
│    Grafana      │     │    Telegram     │
│  (port 3000)    │     │     Bot API     │
└─────────────────┘     └─────────────────┘
```

## Installation

### Option A: Using Setup Script (Recommended)

```bash
./scripts/08-monitoring-setup.sh
```

This installs Node Exporter, Prometheus, and Alertmanager as systemd services.

### Option B: Using Docker Compose

```bash
# Create monitoring directory
mkdir -p /opt/monitoring
cd /opt/monitoring

# Copy configuration files
cp /path/to/docker-compose.monitoring.yml ./docker-compose.yml
cp -r /path/to/configs/monitoring ./prometheus/
cp -r /path/to/configs/monitoring ./alertmanager/

# Start monitoring stack
docker-compose up -d
```

## Telegram Bot Setup

### Step 1: Create Telegram Bot

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` command
3. Follow the prompts:
   - Enter bot name: `Server Monitor`
   - Enter bot username: `my_server_monitor_bot`
4. Save the bot token (looks like: `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz`)

### Step 2: Get Chat ID

**For Private Chat:**

1. Add your bot to a conversation (or just message it)
2. Send any message to the bot
3. Visit in browser:
   ```
   https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
   ```
4. Find `"chat":{"id":123456789,...}`
5. Copy the `id` value (this is your CHAT_ID)

**For Group/Channel:**

1. Add bot to your group/channel
2. Make bot an admin (for channels)
3. Send a message in the group/channel
4. Visit the same URL above
5. The chat ID for groups is usually negative (e.g., `-987654321`)

### Step 3: Configure Alertmanager

Edit `/opt/monitoring/alertmanager/alertmanager.yml`:

```yaml
receivers:
  - name: 'telegram-critical'
    telegram_configs:
      - bot_token: '1234567890:ABCdefGHIjklMNOpqrsTUVwxyz'  # Your bot token
        chat_id: '123456789'  # Your chat ID
        send_resolved: true
        parse_mode: Markdown
        api_url: 'https://api.telegram.org'
```

### Step 4: Restart Alertmanager

```bash
# For systemd installation
systemctl restart alertmanager

# For Docker Compose installation
cd /opt/monitoring
docker-compose restart alertmanager
```

### Step 5: Test Notification

```bash
# Send test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "instance": "test-server"
    },
    "annotations": {
      "summary": "Test alert",
      "description": "This is a test notification"
    }
  }]'
```

Check Telegram - you should receive a message.

## Accessing Dashboards

### Via SSH Tunneling (Secure)

```bash
# Grafana
ssh -L 3000:localhost:3000 admin@your-server-ip
# Open: http://localhost:3000
# Default credentials: admin / admin (change after first login!)

# Prometheus
ssh -L 9090:localhost:9090 admin@your-server-ip
# Open: http://localhost:9090

# Alertmanager
ssh -L 9093:localhost:9093 admin@your-server-ip
# Open: http://localhost:9093
```

### Via Firewall Rules (Not Recommended for Production)

```bash
# Allow specific IP (your office/home)
ufw allow from YOUR.IP.ADDRESS to any port 3000 comment 'Grafana access'
ufw allow from YOUR.IP.ADDRESS to any port 9090 comment 'Prometheus access'
```

## Alert Rules

### Default Alerts

| Alert Name | Severity | Description |
|------------|----------|-------------|
| HighCPUUsage | warning | CPU > 80% for 5 minutes |
| CriticalCPUUsage | critical | CPU > 95% for 2 minutes |
| HighMemoryUsage | warning | RAM > 85% for 5 minutes |
| CriticalMemoryUsage | critical | RAM > 95% for 2 minutes |
| HighDiskUsage | warning | Disk > 80% for 5 minutes |
| CriticalDiskUsage | critical | Disk > 95% for 2 minutes |
| DiskWillFillIn24Hours | warning | Disk predicted to fill in 24h |
| HighNetworkReceive | warning | Incoming traffic > 100MB/s |
| HighNetworkTransmit | warning | Outgoing traffic > 100MB/s |
| HighLoadAverage | warning | Load > CPU count × 1.5 |
| DockerContainerDown | critical | Container stopped |
| DockerContainerHighMemory | warning | Container RAM > 90% |
| SSHBruteForce | warning | Multiple SSH ban events |

### Adding Custom Alerts

Edit `/opt/monitoring/prometheus/rules/alert_rules.yml`:

```yaml
groups:
  - name: custom-alerts
    rules:
      - alert: WebsiteDown
        expr: probe_success{job="blackbox"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Website is down"
          description: "Website {{ $labels.instance }} is not responding"
          telegram_message: "🔴 Website Down\nURL: {{ $labels.instance }}"
```

Reload Prometheus:

```bash
curl -X POST http://localhost:9090/-/reload
```

## Grafana Dashboards

### Import Pre-configured Dashboard

1. Login to Grafana (http://localhost:3000)
2. Go to Dashboards → Import
3. Upload `configs/grafana/dashboards/server-monitoring.json`
4. Select Prometheus datasource
5. Click Import

### Recommended Grafana Dashboards (from grafana.com)

| Dashboard ID | Description |
|--------------|-------------|
| 1860 | Node Exporter Full |
| 893 | Prometheus Blackbox Exporter |
| 179 | Docker and System Monitoring |

## Monitoring Best Practices

### 1. Set Up Multiple Receivers

Configure different receivers for different severity levels:

```yaml
route:
  routes:
    - match:
        severity: critical
      receiver: 'telegram-critical'
    - match:
        severity: warning
      receiver: 'telegram-warning'
    - match:
        severity: info
      receiver: 'email-info'
```

### 2. Configure Alert Inhibition

Prevent alert storms:

```yaml
inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

### 3. Set Up Backup Monitoring

Monitor the monitoring system:

```yaml
- alert: PrometheusDown
  expr: up{job="prometheus"} == 0
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "Prometheus is down!"
```

### 4. Regular Maintenance

**Weekly:**
- Check alert history
- Review disk usage trends
- Verify backup completion

**Monthly:**
- Update monitoring components
- Review and tune alert thresholds
- Clean up old metrics data

## Troubleshooting

### Issue: No Alerts in Telegram

```bash
# Check Alertmanager status
systemctl status alertmanager

# Check Alertmanager logs
journalctl -u alertmanager -f

# Test Telegram API manually
curl -s "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" \
  -d "text=Test message"
```

### Issue: Prometheus Not Scraping Targets

```bash
# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq

# Check Node Exporter
systemctl status node-exporter
curl http://localhost:9100/metrics | head -20
```

### Issue: Grafana Shows No Data

1. Check datasource configuration
2. Verify Prometheus is running
3. Check time range selector
4. Verify metrics exist: `curl http://localhost:9090/api/v1/query?query=up`

### Issue: High Resource Usage

```bash
# Reduce retention
# Edit /etc/systemd/system/prometheus.service
# Change: --storage.tsdb.retention.time=15d to 7d

# Reduce scrape frequency
# Edit prometheus.yml: scrape_interval: 30s

# Restart Prometheus
systemctl daemon-reload
systemctl restart prometheus
```

## Metrics Reference

### System Metrics (Node Exporter)

```promql
# CPU Usage
100 - (avg(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory Usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk Usage
(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100

# Network Traffic
rate(node_network_receive_bytes_total{device="eth0"}[5m])
rate(node_network_transmit_bytes_total{device="eth0"}[5m])

# System Load
node_load1
node_load5
node_load15
```

### Docker Metrics (cAdvisor)

```promql
# Container CPU
rate(container_cpu_usage_seconds_total{name!="",name=~".+"}[5m])

# Container Memory
container_memory_usage_bytes{name!="",name=~".+"}

# Container Network
rate(container_network_receive_bytes_total{name!="",name=~".+"}[5m])
```

## Security Considerations

1. **Bind to localhost only** - All services should listen on `127.0.0.1`
2. **Use SSH tunneling** - Access dashboards via SSH tunnels
3. **Change default passwords** - Especially for Grafana admin
4. **Enable authentication** - Consider adding basic auth for Prometheus
5. **Limit Telegram bot permissions** - Only send messages, don't read

## Quick Reference

```bash
# Check all services status
systemctl status node-exporter prometheus alertmanager

# View logs
journalctl -u prometheus -f
journalctl -u alertmanager -f

# Test alert
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"Test"}}]'

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].labels.job'

# Check Alertmanager config
amtool check-config /opt/monitoring/alertmanager/alertmanager.yml
```

---

**Monitoring is only useful if you act on the alerts!**

Make sure to:
- Respond to critical alerts immediately
- Review warning alerts daily
- Tune thresholds to reduce false positives
- Document common issues and resolutions
