---
name: network-monitoring
description: Network monitoring and diagnostics — Prometheus network targets, blackbox_exporter, Grafana dashboards, tcpdump, iperf3, SNMP, syslog, Alertmanager, and flow analysis
---

# Network Monitoring and Diagnostics

## Purpose

Guide agents in implementing comprehensive network monitoring and diagnostics using Prometheus with network-specific exporters, Grafana dashboards, packet analysis tools, bandwidth testing, SNMP polling, syslog aggregation, and network flow analysis. This skill covers both proactive monitoring (metrics, alerting, dashboards) and reactive diagnostics (packet capture, path analysis, bandwidth testing).

## Table of Contents

1. [Prometheus Scrape Config for Network Targets](#1-prometheus-scrape-config-for-network-targets)
2. [Blackbox Exporter Probe Types](#2-blackbox-exporter-probe-types)
3. [Node Exporter for Network Metrics](#3-node-exporter-for-network-metrics)
4. [Grafana Dashboard Provisioning](#4-grafana-dashboard-provisioning)
5. [Netdata Real-Time Monitoring](#5-netdata-real-time-monitoring)
6. [tcpdump and Wireshark Packet Analysis](#6-tcpdump-and-wireshark-packet-analysis)
7. [iperf3 Bandwidth Testing](#7-iperf3-bandwidth-testing)
8. [MTR and Traceroute Path Analysis](#8-mtr-and-traceroute-path-analysis)
9. [SNMP Monitoring](#9-snmp-monitoring)
10. [Syslog Aggregation with rsyslog and syslog-ng](#10-syslog-aggregation-with-rsyslog-and-syslog-ng)
11. [Alertmanager Routing and Receivers](#11-alertmanager-routing-and-receivers)
12. [Network Flow Analysis (NetFlow/sFlow)](#12-network-flow-analysis-netflowsflow)
13. [Latency Percentile Tracking and Bandwidth Monitoring](#13-latency-percentile-tracking-and-bandwidth-monitoring)
14. [Best Practices](#14-best-practices)
15. [Anti-Patterns](#15-anti-patterns)
16. [Sources & References](#16-sources--references)

---

## 1. Prometheus Scrape Config for Network Targets

Prometheus pulls metrics from network exporters via HTTP scrape endpoints. Network monitoring requires scraping node_exporter for interface stats, blackbox_exporter for probe results, and SNMP exporter for device metrics.

### Full Network-Oriented prometheus.yml

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: "network-monitoring"
    environment: "production"

rule_files:
  - "network_recording_rules.yml"
  - "network_alerting_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]

scrape_configs:
  # --- Node Exporter: host-level network interface metrics ---
  - job_name: "node-exporter"
    static_configs:
      - targets:
          - "server-01:9100"
          - "server-02:9100"
          - "router-gw:9100"
        labels:
          datacenter: "us-east-1"
      - targets:
          - "server-03:9100"
        labels:
          datacenter: "eu-west-1"
    relabel_configs:
      - source_labels: [__address__]
        regex: "(.+):9100"
        target_label: hostname
        replacement: "${1}"

  # --- Blackbox Exporter: ICMP, TCP, HTTP, DNS probes ---
  - job_name: "blackbox-icmp"
    metrics_path: /probe
    params:
      module: [icmp]
    static_configs:
      - targets:
          - "8.8.8.8"
          - "1.1.1.1"
          - "gateway.internal"
          - "core-switch.internal"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: "blackbox-exporter:9115"

  - job_name: "blackbox-http"
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - "https://www.example.com"
          - "https://api.example.com/health"
          - "http://internal-app:8080/healthz"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: "blackbox-exporter:9115"

  - job_name: "blackbox-dns"
    metrics_path: /probe
    params:
      module: [dns_resolve]
    static_configs:
      - targets:
          - "8.8.8.8"
          - "1.1.1.1"
          - "ns1.internal:53"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: "blackbox-exporter:9115"

  - job_name: "blackbox-tcp"
    metrics_path: /probe
    params:
      module: [tcp_connect]
    static_configs:
      - targets:
          - "db-primary:5432"
          - "redis-master:6379"
          - "rabbitmq:5672"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: "blackbox-exporter:9115"

  # --- SNMP Exporter: switch/router device metrics ---
  - job_name: "snmp-switches"
    metrics_path: /snmp
    params:
      module: [if_mib]
    static_configs:
      - targets:
          - "switch-core-01"
          - "switch-access-01"
          - "router-border-01"
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: "snmp-exporter:9116"

  # --- Netdata: real-time per-second metrics ---
  - job_name: "netdata"
    metrics_path: /api/v1/allmetrics
    params:
      format: [prometheus]
    static_configs:
      - targets:
          - "server-01:19999"
          - "server-02:19999"
```

### Key Points for Network Scrape Config

- **Relabeling** is essential for blackbox/SNMP exporters because the target address becomes a parameter, not the scrape endpoint.
- Use `file_sd_configs` for dynamic target discovery instead of hardcoding large target lists.
- Set `scrape_timeout` to be less than `scrape_interval` (default 10s timeout with 15s interval works well).
- Group targets by probe type (ICMP, HTTP, TCP, DNS) into separate jobs for clear labeling.

---

## 2. Blackbox Exporter Probe Types

The blackbox_exporter allows Prometheus to probe endpoints over ICMP, TCP, HTTP, and DNS. Each probe type is defined as a module in the blackbox configuration.

### blackbox.yml Configuration

```yaml
# blackbox.yml
modules:
  # --- ICMP Probe: ping reachability and round-trip time ---
  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: ip4
      dont_fragment: true
      payload_size: 64

  # --- TCP Probe: port reachability and TLS handshake ---
  tcp_connect:
    prober: tcp
    timeout: 5s
    tcp:
      preferred_ip_protocol: ip4

  tcp_tls:
    prober: tcp
    timeout: 5s
    tcp:
      preferred_ip_protocol: ip4
      tls: true
      tls_config:
        insecure_skip_verify: false

  # --- HTTP Probe: endpoint health, status codes, TLS cert expiry ---
  http_2xx:
    prober: http
    timeout: 10s
    http:
      method: GET
      preferred_ip_protocol: ip4
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 201, 204]
      no_follow_redirects: false
      fail_if_ssl: false
      fail_if_not_ssl: false
      tls_config:
        insecure_skip_verify: false

  http_post_2xx:
    prober: http
    timeout: 10s
    http:
      method: POST
      headers:
        Content-Type: application/json
      body: '{"check": "health"}'
      valid_status_codes: [200]

  http_tls_cert_check:
    prober: http
    timeout: 10s
    http:
      method: GET
      fail_if_not_ssl: true
      tls_config:
        insecure_skip_verify: false

  # --- DNS Probe: resolution time and correctness ---
  dns_resolve:
    prober: dns
    timeout: 5s
    dns:
      transport_protocol: udp
      preferred_ip_protocol: ip4
      query_name: "example.com"
      query_type: A
      valid_rcodes:
        - NOERROR

  dns_tcp_resolve:
    prober: dns
    timeout: 5s
    dns:
      transport_protocol: tcp
      query_name: "example.com"
      query_type: A
```

### Key Blackbox Metrics

| Metric | Description |
|--------|-------------|
| `probe_success` | 1 if probe succeeded, 0 if it failed |
| `probe_duration_seconds` | Total probe duration |
| `probe_dns_lookup_time_seconds` | Time for DNS resolution |
| `probe_ip_protocol` | Protocol used (4 or 6) |
| `probe_ssl_earliest_cert_expiry` | Unix timestamp of TLS cert expiry |
| `probe_http_status_code` | HTTP response status code |
| `probe_icmp_duration_seconds` | ICMP round-trip time |

### Useful PromQL for Blackbox

```
# Targets that are down
probe_success == 0

# ICMP round-trip time in milliseconds
probe_icmp_duration_seconds * 1000

# TLS certificate days until expiry
(probe_ssl_earliest_cert_expiry - time()) / 86400

# HTTP probe latency by phase
probe_http_duration_seconds{phase="resolve"}
probe_http_duration_seconds{phase="connect"}
probe_http_duration_seconds{phase="tls"}
probe_http_duration_seconds{phase="processing"}
probe_http_duration_seconds{phase="transfer"}
```

---

## 3. Node Exporter for Network Metrics

The node_exporter exposes host-level network interface statistics. These are critical for tracking bandwidth utilization, error rates, and interface health.

### Key Network Metrics from node_exporter

| Metric | Description |
|--------|-------------|
| `node_network_receive_bytes_total` | Total bytes received on an interface |
| `node_network_transmit_bytes_total` | Total bytes transmitted on an interface |
| `node_network_receive_packets_total` | Total packets received |
| `node_network_transmit_packets_total` | Total packets transmitted |
| `node_network_receive_errs_total` | Receive errors |
| `node_network_transmit_errs_total` | Transmit errors |
| `node_network_receive_drop_total` | Dropped incoming packets |
| `node_network_transmit_drop_total` | Dropped outgoing packets |
| `node_network_up` | Interface operational status |
| `node_network_speed_bytes` | Interface speed in bytes/sec |

### PromQL for Interface Bandwidth

```
# Receive bandwidth in Mbps per interface (excluding loopback and virtual)
rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m]) * 8 / 1e6

# Transmit bandwidth in Mbps
rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m]) * 8 / 1e6

# Interface utilization as percentage of link speed
rate(node_network_receive_bytes_total{device="eth0"}[5m])
/ node_network_speed_bytes{device="eth0"} * 100

# Packet error rate
rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m])

# Packet drop rate
rate(node_network_receive_drop_total[5m]) + rate(node_network_transmit_drop_total[5m])
```

---

## 4. Grafana Dashboard Provisioning

Grafana dashboards can be provisioned as code so they are version-controlled and repeatable. Network dashboards should cover interface bandwidth, probe status, SNMP device health, and latency tracking.

### Dashboard Provisioning Directory Structure

```
grafana/
  provisioning/
    dashboards/
      dashboards.yml          # Dashboard provider config
    datasources/
      datasources.yml         # Prometheus datasource
  dashboards/
    network-overview.json     # Dashboard JSON model
    blackbox-probes.json
    snmp-interfaces.json
```

### datasources.yml

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

### dashboards.yml (Provider Config)

```yaml
apiVersion: 1
providers:
  - name: "Network Dashboards"
    orgId: 1
    folder: "Network"
    type: file
    disableDeletion: true
    editable: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
```

### Network Overview Dashboard Panels

A well-structured network dashboard uses the RED method adapted for network contexts: Reachability, Errors, Delay.

Key panels to include:

- **Probe Status Map**: Table or stat panel showing `probe_success` for all monitored targets with color coding (green=up, red=down).
- **Interface Bandwidth**: Time series panel with `rate(node_network_receive_bytes_total[5m]) * 8 / 1e6` for each server interface.
- **ICMP Latency Heatmap**: Heatmap of `probe_icmp_duration_seconds` across targets to spot latency outliers.
- **TLS Certificate Expiry**: Stat panel showing `(probe_ssl_earliest_cert_expiry - time()) / 86400` with thresholds at 30/14/7 days.
- **Interface Error Rate**: Time series of `rate(node_network_receive_errs_total[5m])` per device.
- **Top Talkers**: Bar gauge ranking interfaces by bandwidth consumption.

### Grafana Variables for Dynamic Filtering

Use template variables so a single dashboard works across all hosts and interfaces:

- `$hostname` sourced from `label_values(node_network_up, instance)`
- `$device` sourced from `label_values(node_network_up{instance="$hostname"}, device)`
- `$probe_target` sourced from `label_values(probe_success, instance)`

---

## 5. Netdata Real-Time Monitoring

Netdata provides per-second granularity metrics with zero configuration for network interfaces. It is useful for real-time troubleshooting when Prometheus 15-second intervals are too coarse.

### Installation

```bash
# One-line install (Linux)
bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait

# Docker
docker run -d --name=netdata \
  -p 19999:19999 \
  -v netdataconfig:/etc/netdata \
  -v netdatalib:/var/lib/netdata \
  -v netdatacache:/var/cache/netdata \
  -v /etc/passwd:/host/etc/passwd:ro \
  -v /etc/group:/host/etc/group:ro \
  -v /etc/localtime:/host/etc/localtime:ro \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /etc/os-release:/host/etc/os-release:ro \
  --restart unless-stopped \
  --cap-add SYS_PTRACE \
  --security-opt apparmor=unconfined \
  netdata/netdata
```

### Network Charts in Netdata

Netdata automatically collects per-interface metrics at one-second intervals:

- `net.eth0` -- bandwidth in/out in kilobits/sec
- `net_packets.eth0` -- packets in/out per second
- `net_errors.eth0` -- errors in/out per second
- `net_drops.eth0` -- drops in/out per second
- `net_speed.eth0` -- link speed

### Streaming Netdata Metrics to Prometheus

Configure Netdata as a Prometheus endpoint by adding it to the Prometheus scrape config (see Section 1). Netdata exposes all metrics at `/api/v1/allmetrics?format=prometheus`.

### Netdata Alarms for Network

Edit `/etc/netdata/health.d/net.conf` to customize thresholds:

```
alarm: interface_drops
on: net_drops.eth0
lookup: sum -1m unaligned absolute
every: 10s
warn: $this > 10
crit: $this > 100
info: Number of dropped packets on eth0 in the last minute
```

---

## 6. tcpdump and Wireshark Packet Analysis

Packet capture is essential for diagnosing connectivity issues, protocol errors, and performance problems at the wire level.

### tcpdump Filter Expressions

```bash
# Capture all traffic on interface eth0
sudo tcpdump -i eth0 -nn

# Capture only TCP traffic on port 443 (HTTPS)
sudo tcpdump -i eth0 -nn tcp port 443

# Capture ICMP traffic (ping)
sudo tcpdump -i eth0 -nn icmp

# Capture DNS traffic (port 53, UDP and TCP)
sudo tcpdump -i eth0 -nn port 53

# Capture traffic to/from a specific host
sudo tcpdump -i eth0 -nn host 192.168.1.100

# Capture traffic between two hosts
sudo tcpdump -i eth0 -nn host 192.168.1.100 and host 192.168.1.200

# Capture SYN packets only (connection attempts)
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & (tcp-syn) != 0 and tcp[tcpflags] & (tcp-ack) == 0'

# Capture TCP RST packets (connection resets)
sudo tcpdump -i eth0 -nn 'tcp[tcpflags] & (tcp-rst) != 0'

# Capture packets larger than 1000 bytes
sudo tcpdump -i eth0 -nn greater 1000

# Capture VLAN-tagged traffic
sudo tcpdump -i eth0 -nn vlan

# Write capture to file for Wireshark analysis
sudo tcpdump -i eth0 -nn -w /tmp/capture.pcap -c 10000

# Read back a capture file with verbose output
sudo tcpdump -nn -r /tmp/capture.pcap -v

# Capture with rotation: 100MB files, keep 10 files
sudo tcpdump -i eth0 -nn -w /tmp/capture-%Y%m%d%H%M%S.pcap -C 100 -W 10

# Capture ARP traffic
sudo tcpdump -i eth0 -nn arp

# Capture only HTTP GET requests
sudo tcpdump -i eth0 -nn -A 'tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)' | grep 'GET'
```

### Wireshark Display Filters (for pcap analysis)

Common display filters to apply after loading a pcap file:

- `tcp.analysis.retransmission` -- show retransmitted TCP segments
- `tcp.analysis.duplicate_ack` -- show duplicate ACKs
- `tcp.analysis.zero_window` -- show zero-window conditions
- `dns.time > 0.5` -- slow DNS responses
- `http.response.code >= 400` -- HTTP errors
- `tcp.flags.reset == 1` -- TCP reset packets
- `frame.time_delta > 1` -- gaps longer than 1 second between frames

### Capture Strategy

1. **Start narrow**: Filter by host and port to reduce noise.
2. **Capture to file**: Always use `-w` for later analysis; reading live terminal output misses details.
3. **Limit capture size**: Use `-c` (packet count) or `-C` (file size) to avoid filling disk.
4. **Timestamp precision**: Use `-tt` for Unix epoch timestamps or `--time-stamp-precision=nano` for nanosecond resolution.

---

## 7. iperf3 Bandwidth Testing

iperf3 measures maximum achievable bandwidth, jitter, and packet loss between two endpoints. It is the standard tool for validating network capacity.

### Server Setup

```bash
# Start iperf3 server on default port 5201
iperf3 -s

# Start on a specific port with daemon mode
iperf3 -s -p 5210 -D --logfile /var/log/iperf3.log

# Start with JSON output
iperf3 -s --json --logfile /var/log/iperf3.json
```

### Client Tests

```bash
# Basic TCP bandwidth test (10 seconds, default)
iperf3 -c server-01 -t 10

# TCP test with 4 parallel streams
iperf3 -c server-01 -P 4 -t 30

# UDP test with target bandwidth of 100 Mbps (measures jitter and loss)
iperf3 -c server-01 -u -b 100M -t 10

# Reverse mode: server sends to client (useful for asymmetric links)
iperf3 -c server-01 -R -t 10

# Bidirectional test
iperf3 -c server-01 --bidir -t 10

# Test with specific MSS (to simulate different MTU)
iperf3 -c server-01 -M 1400 -t 10

# Test with specific window size
iperf3 -c server-01 -w 256K -t 10

# JSON output for programmatic processing
iperf3 -c server-01 -t 10 --json > /tmp/iperf3-result.json

# Test specific port
iperf3 -c server-01 -p 5210 -t 10
```

### Interpreting Results

- **Bandwidth**: Reported in Mbits/sec or Gbits/sec. Compare against expected link speed.
- **Retransmits** (TCP): Non-zero retransmits indicate congestion or packet loss on the path.
- **Jitter** (UDP): Variation in packet arrival time. Should be under 1ms for VoIP, under 5ms for video.
- **Lost/Total** (UDP): Packet loss percentage. Should be 0% on a healthy LAN, under 0.1% on WAN.

---

## 8. MTR and Traceroute Path Analysis

MTR (My Traceroute) combines traceroute and ping to provide continuous path analysis. It reveals per-hop latency and packet loss.

### MTR Usage

```bash
# Basic MTR report (10 cycles, then exit)
mtr -r -c 10 target-host

# MTR with both DNS names and IP addresses
mtr -r -b -c 20 target-host

# MTR in wide report mode (shows both directions)
mtr -r -w -c 10 target-host

# TCP MTR on port 443 (bypasses ICMP-blocking firewalls)
mtr -r -T -P 443 -c 10 target-host

# UDP MTR
mtr -r -u -c 10 target-host

# JSON output for automation
mtr -r -j -c 10 target-host
```

### Reading MTR Output

```
HOST: client                     Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- gateway.local              0.0%    10    0.5   0.6   0.4   1.2   0.3
  2.|-- isp-router-01              0.0%    10    3.2   3.5   2.8   5.1   0.7
  3.|-- core-router.isp.net        0.0%    10   12.1  12.4  11.8  14.2   0.8
  4.|-- peer-exchange              0.0%    10   15.3  15.1  14.5  16.8   0.6
  5.|-- target-dc-router           0.0%    10   18.7  18.9  18.1  20.3   0.7
  6.|-- target-host                0.0%    10   19.2  19.4  18.8  21.1   0.8
```

**Interpretation rules:**

- **Loss% at intermediate hops only**: Some routers rate-limit ICMP replies. Loss at a mid-hop but not at the final destination is typically harmless.
- **Loss% at final hop**: This indicates real packet loss on the path.
- **StDev**: High standard deviation indicates jitter or intermittent congestion.
- **Large latency jump between hops**: Normal if it crosses a geographic boundary. Investigate if it is unexpected (e.g., a local LAN hop with 50ms).

### Traceroute Variants

```bash
# Standard ICMP traceroute
traceroute target-host

# TCP traceroute on port 80 (bypasses firewalls)
traceroute -T -p 80 target-host

# Traceroute with AS number lookup
traceroute -A target-host

# Paris traceroute (consistent per-flow path)
paris-traceroute target-host
```

---

## 9. SNMP Monitoring

SNMP (Simple Network Management Protocol) is used to collect metrics from network devices (switches, routers, firewalls, access points) that do not have native Prometheus exporters.

### SNMP v2c Community Configuration

```
# /etc/snmp/snmpd.conf on the monitored device
# Read-only community string (treat as a password)
rocommunity mySecretCommunity 10.0.0.0/24

# System information
syslocation "Datacenter Rack A3"
syscontact "netops@example.com"

# Restrict to specific OIDs
view systemonly included .1.3.6.1.2.1.1
view systemonly included .1.3.6.1.2.1.2
view systemonly included .1.3.6.1.2.1.31
rouser noAuthUser noauth -V systemonly
```

### SNMP v3 Configuration (Recommended)

SNMPv3 provides authentication and encryption, which v2c community strings do not.

```
# Create SNMPv3 user on the device
# Auth: SHA, Privacy: AES
createUser monitorUser SHA "authPassword123" AES "privPassword456"
rouser monitorUser priv

# Querying with SNMPv3
snmpwalk -v3 -l authPriv \
  -u monitorUser \
  -a SHA -A "authPassword123" \
  -x AES -X "privPassword456" \
  switch-core-01 IF-MIB::ifTable
```

### Prometheus SNMP Exporter

The snmp_exporter translates SNMP OIDs into Prometheus metrics. Configuration is generated from MIB files using the `generator` tool.

```yaml
# snmp.yml (generated by snmp_exporter generator)
if_mib:
  walk:
    - 1.3.6.1.2.1.2      # IF-MIB::interfaces
    - 1.3.6.1.2.1.31.1    # IF-MIB::ifXTable (64-bit counters)
  metrics:
    - name: ifHCInOctets
      oid: 1.3.6.1.2.1.31.1.1.1.6
      type: counter
      help: Total octets received on interface (64-bit)
      indexes:
        - labelname: ifIndex
          type: Integer
      lookups:
        - labels: [ifIndex]
          labelname: ifDescr
          oid: 1.3.6.1.2.1.2.2.1.2
          type: DisplayString
    - name: ifHCOutOctets
      oid: 1.3.6.1.2.1.31.1.1.1.10
      type: counter
      help: Total octets transmitted on interface (64-bit)
      indexes:
        - labelname: ifIndex
          type: Integer
      lookups:
        - labels: [ifIndex]
          labelname: ifDescr
          oid: 1.3.6.1.2.1.2.2.1.2
          type: DisplayString
    - name: ifOperStatus
      oid: 1.3.6.1.2.1.2.2.1.8
      type: gauge
      help: Interface operational status (1=up, 2=down)
  auth:
    community: mySecretCommunity
```

### Key SNMP OIDs for Network Monitoring

| OID | Name | Description |
|-----|------|-------------|
| 1.3.6.1.2.1.2.2.1.8 | ifOperStatus | Interface up/down status |
| 1.3.6.1.2.1.31.1.1.1.6 | ifHCInOctets | 64-bit incoming byte counter |
| 1.3.6.1.2.1.31.1.1.1.10 | ifHCOutOctets | 64-bit outgoing byte counter |
| 1.3.6.1.2.1.2.2.1.14 | ifInErrors | Incoming error counter |
| 1.3.6.1.2.1.2.2.1.20 | ifOutErrors | Outgoing error counter |
| 1.3.6.1.2.1.2.2.1.13 | ifInDiscards | Incoming discard counter |
| 1.3.6.1.2.1.1.3.0 | sysUpTime | Device uptime in timeticks |

---

## 10. Syslog Aggregation with rsyslog and syslog-ng

Network devices (routers, switches, firewalls) generate syslog messages for events such as interface state changes, authentication failures, and configuration changes. Aggregating these logs into a central collector is essential for troubleshooting and security auditing.

### rsyslog Remote Forwarding (Client)

```bash
# /etc/rsyslog.d/50-remote.conf on the sending device/server

# Forward all logs to central collector via TCP (reliable)
*.* @@syslog-collector.internal:514

# Forward only network-related facility logs
local0.* @@syslog-collector.internal:514
local7.* @@syslog-collector.internal:514

# Forward with structured data (RFC 5424 format)
template(name="RFC5424Format" type="string"
  string="<%PRI%>1 %TIMESTAMP:::date-rfc3339% %HOSTNAME% %APP-NAME% %PROCID% %MSGID% %STRUCTURED-DATA% %msg%\n"
)
*.* @@syslog-collector.internal:514;RFC5424Format

# Queue configuration for reliability (disk-assisted queue)
$ActionQueueType LinkedList
$ActionQueueFileName fwdRule1
$ActionResumeRetryCount -1
$ActionQueueSaveOnShutdown on
$ActionQueueMaxDiskSpace 1g
```

### rsyslog Central Collector

```bash
# /etc/rsyslog.d/00-receiver.conf on the central collector

# Enable TCP syslog reception
module(load="imtcp")
input(type="imtcp" port="514")

# Enable UDP syslog reception (for legacy devices)
module(load="imudp")
input(type="imudp" port="514")

# Template for log file naming by source host and date
template(name="RemoteLogs" type="string"
  string="/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log"
)

# Write remote logs to per-host directories
if $fromhost-ip != "127.0.0.1" then {
  action(type="omfile" dynaFile="RemoteLogs")
  stop
}
```

### syslog-ng Central Collector

```
# /etc/syslog-ng/syslog-ng.conf

source s_network {
    tcp(ip("0.0.0.0") port(514));
    udp(ip("0.0.0.0") port(514));
};

destination d_remote_hosts {
    file("/var/log/remote/${HOST}/${PROGRAM}.log"
        create-dirs(yes)
        dir-perm(0755)
        perm(0644)
    );
};

filter f_network_devices {
    facility(local0) or facility(local7);
};

log {
    source(s_network);
    filter(f_network_devices);
    destination(d_remote_hosts);
};
```

### Log Rotation for Syslog

```bash
# /etc/logrotate.d/remote-syslog
/var/log/remote/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 syslog adm
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
```

---

## 11. Alertmanager Routing and Receivers

Alertmanager handles alert deduplication, grouping, inhibition, silencing, and routing to notification channels. Network alerts require specific routing to the network operations team.

### alertmanager.yml

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m
  smtp_smarthost: "smtp.example.com:587"
  smtp_from: "alertmanager@example.com"
  smtp_auth_username: "alertmanager@example.com"
  smtp_auth_password: "smtp-password"
  smtp_require_tls: true

route:
  receiver: "default-slack"
  group_by: ["alertname", "instance"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    # Network critical alerts: page on-call network engineer
    - match:
        severity: critical
        team: network
      receiver: "network-pagerduty"
      group_wait: 10s
      repeat_interval: 1h

    # Network warnings: Slack channel
    - match:
        severity: warning
        team: network
      receiver: "network-slack"
      group_wait: 1m
      repeat_interval: 4h

    # TLS certificate expiry: email
    - match:
        alertname: TLSCertExpiringSoon
      receiver: "cert-email"
      repeat_interval: 24h

    # Probe failures: immediate Slack notification
    - match_re:
        alertname: "Probe.*Failed"
      receiver: "network-slack"
      group_wait: 10s

receivers:
  - name: "default-slack"
    slack_configs:
      - api_url: "https://hooks.slack.com/services/T00/B00/XXXXX"
        channel: "#alerts-general"
        title: '{{ .GroupLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *{{ .Annotations.summary }}*
          Instance: {{ .Labels.instance }}
          {{ end }}

  - name: "network-slack"
    slack_configs:
      - api_url: "https://hooks.slack.com/services/T00/B00/YYYYY"
        channel: "#alerts-network"
        title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
        text: >-
          {{ range .Alerts }}
          *{{ .Annotations.summary }}*
          Instance: {{ .Labels.instance }}
          Severity: {{ .Labels.severity }}
          Runbook: {{ .Annotations.runbook_url }}
          {{ end }}
        send_resolved: true

  - name: "network-pagerduty"
    pagerduty_configs:
      - service_key: "pagerduty-service-key-here"
        severity: '{{ .CommonLabels.severity }}'
        description: '{{ .CommonAnnotations.summary }}'

  - name: "cert-email"
    email_configs:
      - to: "security-team@example.com"
        headers:
          Subject: "TLS Certificate Expiring: {{ .GroupLabels.instance }}"

inhibit_rules:
  # If a host is completely down, suppress individual probe alerts for it
  - source_match:
      alertname: HostDown
    target_match_re:
      alertname: "Probe.*"
    equal: ["instance"]

  # If a critical alert fires, suppress warning-level alerts for the same target
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ["alertname", "instance"]
```

### Network Alerting Rules

```yaml
# network_alerting_rules.yml
groups:
  - name: network-probes
    rules:
      - alert: ProbeTargetDown
        expr: probe_success == 0
        for: 3m
        labels:
          severity: critical
          team: network
        annotations:
          summary: "Probe failed for {{ $labels.instance }}"
          runbook_url: "https://wiki.example.com/runbooks/probe-failure"

      - alert: ProbeHighLatency
        expr: probe_duration_seconds > 2
        for: 5m
        labels:
          severity: warning
          team: network
        annotations:
          summary: "Probe latency above 2s for {{ $labels.instance }}"

      - alert: TLSCertExpiringSoon
        expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 14
        for: 1h
        labels:
          severity: warning
          team: network
        annotations:
          summary: "TLS cert for {{ $labels.instance }} expires in {{ $value | humanize }} days"

  - name: network-interfaces
    rules:
      - alert: InterfaceDown
        expr: node_network_up{device!~"lo|veth.*|docker.*"} == 0
        for: 2m
        labels:
          severity: critical
          team: network
        annotations:
          summary: "Interface {{ $labels.device }} is down on {{ $labels.instance }}"

      - alert: HighInterfaceErrorRate
        expr: rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m]) > 10
        for: 5m
        labels:
          severity: warning
          team: network
        annotations:
          summary: "High error rate on {{ $labels.device }} at {{ $labels.instance }}"

      - alert: InterfaceSaturation
        expr: >
          rate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m])
          / node_network_speed_bytes > 0.85
        for: 10m
        labels:
          severity: warning
          team: network
        annotations:
          summary: "Interface {{ $labels.device }} on {{ $labels.instance }} is above 85% utilization"

      - alert: HighPacketLoss
        expr: >
          rate(node_network_receive_drop_total[5m])
          / rate(node_network_receive_packets_total[5m]) > 0.01
        for: 5m
        labels:
          severity: warning
          team: network
        annotations:
          summary: "Packet drop rate above 1% on {{ $labels.device }} at {{ $labels.instance }}"

  - name: snmp-devices
    rules:
      - alert: SNMPTargetUnreachable
        expr: up{job="snmp-switches"} == 0
        for: 3m
        labels:
          severity: critical
          team: network
        annotations:
          summary: "Cannot reach SNMP target {{ $labels.instance }}"

      - alert: SNMPInterfaceDown
        expr: ifOperStatus == 2
        for: 2m
        labels:
          severity: warning
          team: network
        annotations:
          summary: "SNMP interface {{ $labels.ifDescr }} is down on {{ $labels.instance }}"
```

---

## 12. Network Flow Analysis (NetFlow/sFlow)

Network flow data provides visibility into traffic patterns, top talkers, application usage, and anomalies that per-interface byte counters cannot reveal.

### Flow Protocols Comparison

| Protocol | Sampling | Typical Use | Exporter |
|----------|----------|-------------|----------|
| NetFlow v5 | 1:N | Legacy routers | Router/switch |
| NetFlow v9 | 1:N | Modern routers, flexible templates | Router/switch |
| IPFIX | 1:N | Standards-based (NetFlow v10) | Router/switch |
| sFlow | 1:N + counters | High-speed switches, multi-vendor | Switch agent |

### Flow Collection with nfdump/nfcapd

```bash
# Start NetFlow collector on port 2055
nfcapd -w -D -l /var/log/netflow -p 2055

# Query top 10 talkers by bytes in last hour
nfdump -R /var/log/netflow -s srcip/bytes -n 10 -o extended

# Query traffic for a specific subnet
nfdump -R /var/log/netflow 'src net 10.0.1.0/24' -s dstip/bytes

# Query traffic by port (top destination ports)
nfdump -R /var/log/netflow -s dstport/bytes -n 20

# Filter by time range
nfdump -R /var/log/netflow -t 2025/01/15.10:00-2025/01/15.11:00 -s srcip/flows
```

### sFlow Collection with sflowtool

```bash
# Receive sFlow data and print to stdout
sflowtool -p 6343

# Convert sFlow to NetFlow v5 and forward to nfcapd
sflowtool -p 6343 -c 127.0.0.1 -d 2055

# Output sFlow as line-format for processing
sflowtool -p 6343 -l
```

### Flow-Based Anomaly Detection

Use flow data to detect:

- **DDoS attacks**: Sudden spike in flows from many sources to one destination.
- **Port scans**: Single source hitting many destination ports across multiple hosts.
- **Data exfiltration**: Unusually large outbound transfers during off-hours.
- **Lateral movement**: Internal host communicating with many internal hosts on unusual ports.

---

## 13. Latency Percentile Tracking and Bandwidth Monitoring

Tracking latency at various percentiles (p50, p90, p95, p99) reveals the experience of different user segments. Mean latency hides tail latency problems.

### Recording Rules for Latency Percentiles

```yaml
# network_recording_rules.yml
groups:
  - name: network_latency
    interval: 30s
    rules:
      # ICMP probe latency percentiles
      - record: probe:icmp_duration_seconds:p50
        expr: quantile(0.5, probe_icmp_duration_seconds{job="blackbox-icmp"})

      - record: probe:icmp_duration_seconds:p90
        expr: quantile(0.9, probe_icmp_duration_seconds{job="blackbox-icmp"})

      - record: probe:icmp_duration_seconds:p99
        expr: quantile(0.99, probe_icmp_duration_seconds{job="blackbox-icmp"})

      # HTTP probe latency percentiles
      - record: probe:http_duration_seconds:p50
        expr: quantile(0.5, probe_duration_seconds{job="blackbox-http"})

      - record: probe:http_duration_seconds:p95
        expr: quantile(0.95, probe_duration_seconds{job="blackbox-http"})

  - name: bandwidth_utilization
    interval: 30s
    rules:
      # Total cluster receive bandwidth in Gbps
      - record: network:receive_bandwidth_gbps:total
        expr: >
          sum(rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m]))
          * 8 / 1e9

      # Total cluster transmit bandwidth in Gbps
      - record: network:transmit_bandwidth_gbps:total
        expr: >
          sum(rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m]))
          * 8 / 1e9

      # Per-host receive bandwidth in Mbps
      - record: network:receive_bandwidth_mbps:by_host
        expr: >
          sum by (instance) (
            rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*"}[5m])
          ) * 8 / 1e6
```

### PromQL for Bandwidth Monitoring

```
# Current total bandwidth utilization across all hosts
network:receive_bandwidth_gbps:total + network:transmit_bandwidth_gbps:total

# Top 5 hosts by bandwidth consumption
topk(5, network:receive_bandwidth_mbps:by_host)

# Bandwidth change rate (is traffic growing or shrinking?)
deriv(network:receive_bandwidth_gbps:total[1h])

# Predict bandwidth 4 hours from now (linear regression)
predict_linear(network:receive_bandwidth_gbps:total[6h], 4 * 3600)
```

---

## 14. Best Practices

1. **Layer your monitoring**: Use Prometheus for trend analysis (15s-60s intervals), Netdata for real-time debugging (1s intervals), and packet capture for deep-dive diagnostics.
2. **Use blackbox probes from multiple vantage points**: Run blackbox_exporter instances in different network segments to distinguish between local and remote failures.
3. **Always use 64-bit SNMP counters** (ifHCInOctets/ifHCOutOctets): 32-bit counters wrap around in seconds on 10Gbps+ links, producing incorrect rate calculations.
4. **Encrypt SNMP with v3**: Never use SNMPv1/v2c community strings on networks where traffic can be intercepted. Community strings are sent in plaintext.
5. **Set meaningful `for` durations on alerts**: Network blips are common. A 2-5 minute `for` duration prevents false alerts from transient issues like route convergence.
6. **Store dashboards as code**: Keep Grafana JSON models in version control alongside the Prometheus rules they depend on.
7. **Use consistent labeling**: Apply `team`, `environment`, `datacenter`, and `service` labels uniformly across all scrape jobs so Alertmanager routing and Grafana filtering work correctly.
8. **Capture baseline measurements**: Run iperf3 and MTR tests during known-good periods and store results for comparison during incidents.
9. **Aggregate syslogs centrally with reliable transport**: Use TCP (not UDP) for syslog forwarding to prevent message loss during network congestion, and configure disk-assisted queues for buffering.
10. **Monitor the monitors**: Alert on `up == 0` for Prometheus scrape targets, and ensure blackbox_exporter, snmp_exporter, and syslog collectors are themselves monitored.

---

## 15. Anti-Patterns

- **Relying solely on ICMP ping for reachability**: Many networks deprioritize or block ICMP. Use TCP and HTTP probes alongside ICMP for accurate reachability testing.
- **Using 32-bit SNMP counters on high-speed interfaces**: 32-bit counters (ifInOctets) wrap at 4GB, which happens in ~3 seconds on a 10Gbps link. Always use 64-bit HC counters.
- **Alerting on every interface flap**: Brief interface bounces during maintenance or spanning-tree reconvergence trigger excessive alerts. Use `for` durations and inhibition rules.
- **Running tcpdump without filters in production**: Unfiltered captures on busy interfaces generate massive files, consume CPU, and may cause packet drops on the monitored host.
- **Using SNMPv2c community strings as "security"**: Community strings are plaintext. Treat them as no authentication at all on untrusted networks.
- **Polling SNMP too frequently**: Polling hundreds of OIDs every 10 seconds from dozens of devices can overwhelm the SNMP agent. Use 30-60 second intervals for interface counters.
- **Ignoring syslog message loss**: UDP syslog drops messages silently during congestion. Not using TCP with disk-assisted queues means losing critical event logs.
- **Building dashboards without template variables**: Hardcoding hostnames and interface names into Grafana panels creates maintenance burden when infrastructure changes.
- **Setting bandwidth alerts on absolute thresholds only**: A 100Mbps alert threshold is meaningless without knowing whether the interface is 1Gbps or 10Gbps. Alert on utilization percentage instead.
- **Not testing alerting pipelines end-to-end**: An alert rule that fires but routes to a misconfigured Slack webhook is worse than no alert, because it creates false confidence in the monitoring system.

---

## 16. Sources & References

- Prometheus Documentation: https://prometheus.io/docs/introduction/overview/
- Blackbox Exporter GitHub Repository: https://github.com/prometheus/blackbox_exporter
- SNMP Exporter GitHub Repository: https://github.com/prometheus/snmp_exporter
- Grafana Dashboard Provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- Alertmanager Configuration: https://prometheus.io/docs/alerting/latest/configuration/
- Netdata Documentation: https://learn.netdata.cloud/docs/
- tcpdump Manual Page: https://www.tcpdump.org/manpages/tcpdump.1.html
- iperf3 Documentation: https://iperf.fr/iperf-doc.php
- rsyslog Documentation: https://www.rsyslog.com/doc/v8-stable/
- Wireshark Display Filter Reference: https://www.wireshark.org/docs/dfref/
