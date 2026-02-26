---
name: dns-dhcp
description: DNS and DHCP services — BIND9, dnsmasq, CoreDNS, Pi-hole, ISC Kea DHCP, DNSSEC, DoT/DoH, zone management, DHCP reservations, and PXE boot
---

# DNS and DHCP Services

## Purpose

Guide agents in deploying, configuring, and troubleshooting DNS and DHCP infrastructure across enterprise and home-lab environments. Covers authoritative and recursive DNS with BIND9, lightweight combined DNS+DHCP with dnsmasq, container-native DNS with CoreDNS, ad-blocking DNS with Pi-hole, modern DHCP with ISC Kea, encrypted DNS transports (DoT/DoH), DNSSEC zone signing, split-horizon DNS, reverse DNS, DHCP reservations, lease management, and PXE boot via DHCP options.

## Table of Contents

1. [BIND9 Authoritative and Recursive DNS](#1-bind9-authoritative-and-recursive-dns)
2. [Zone File Syntax and Management](#2-zone-file-syntax-and-management)
3. [DNSSEC Key Generation and Zone Signing](#3-dnssec-key-generation-and-zone-signing)
4. [dnsmasq Combined DNS and DHCP](#4-dnsmasq-combined-dns-and-dhcp)
5. [CoreDNS for Container-Native Environments](#5-coredns-for-container-native-environments)
6. [Pi-hole Ad-Blocking DNS](#6-pi-hole-ad-blocking-dns)
7. [ISC Kea DHCP Server](#7-isc-kea-dhcp-server)
8. [DNS-over-TLS and DNS-over-HTTPS](#8-dns-over-tls-and-dns-over-https)
9. [Split-Horizon DNS and Conditional Forwarding](#9-split-horizon-dns-and-conditional-forwarding)
10. [Reverse DNS and PTR Records](#10-reverse-dns-and-ptr-records)
11. [DHCP Reservations, Leases, and PXE Boot](#11-dhcp-reservations-leases-and-pxe-boot)
12. [DNS Caching, TTL Tuning, and systemd-resolved](#12-dns-caching-ttl-tuning-and-systemd-resolved)
13. [Best Practices](#13-best-practices)
14. [Anti-Patterns](#14-anti-patterns)
15. [Sources & References](#15-sources--references)

---

## 1. BIND9 Authoritative and Recursive DNS

BIND9 (Berkeley Internet Name Domain) is the most widely deployed DNS server software. It can operate as an authoritative name server, a recursive resolver, or both.

### Installing BIND9

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y bind9 bind9utils bind9-dnsutils

# RHEL/Rocky/Alma
sudo dnf install -y bind bind-utils

# Enable and start
sudo systemctl enable --now named    # RHEL family
sudo systemctl enable --now bind9    # Debian family
```

### Main Configuration — named.conf

BIND9 configuration is split across multiple files. The primary file is `/etc/bind/named.conf` (Debian) or `/etc/named.conf` (RHEL).

```
// /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";

    // Restrict recursive queries to trusted networks
    allow-recursion { 10.0.0.0/8; 172.16.0.0/12; 192.168.0.0/16; localhost; };

    // Forward unresolved queries to upstream resolvers
    forwarders {
        1.1.1.1;
        8.8.8.8;
    };

    // Disable zone transfers by default
    allow-transfer { none; };

    // DNSSEC validation
    dnssec-validation auto;

    // Listen on specific interfaces
    listen-on { 127.0.0.1; 10.0.1.1; };
    listen-on-v6 { ::1; };

    // Rate limiting to mitigate amplification attacks
    rate-limit {
        responses-per-second 10;
        window 5;
    };

    // Query logging (disable in production for performance)
    querylog no;
};
```

### Defining Zones

```
// /etc/bind/named.conf.local
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com";
    allow-transfer { 10.0.1.2; };       // Secondary NS IP
    also-notify { 10.0.1.2; };
    allow-update { none; };
};

zone "1.0.10.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.10.0.1";
    allow-transfer { 10.0.1.2; };
};

// Secondary zone
zone "partner.net" {
    type slave;
    file "/var/cache/bind/db.partner.net";
    masters { 203.0.113.10; };
};
```

### Verifying Configuration

```bash
# Check named.conf syntax
sudo named-checkconf

# Check a zone file
sudo named-checkzone example.com /etc/bind/zones/db.example.com

# Reload after changes
sudo rndc reload
sudo rndc reload example.com   # reload a single zone
```

---

## 2. Zone File Syntax and Management

Zone files define the DNS records for a domain. Correct SOA serial management is critical for zone transfer propagation to secondary servers.

### Forward Zone File

```
; /etc/bind/zones/db.example.com
$TTL    86400       ; Default TTL: 24 hours
@       IN  SOA     ns1.example.com. admin.example.com. (
                    2026022601  ; Serial (YYYYMMDDNN format)
                    3600        ; Refresh: 1 hour
                    900         ; Retry: 15 minutes
                    1209600     ; Expire: 2 weeks
                    86400       ; Negative cache TTL: 1 day
        )

; Name servers
@       IN  NS      ns1.example.com.
@       IN  NS      ns2.example.com.

; A records
@       IN  A       10.0.1.10
ns1     IN  A       10.0.1.1
ns2     IN  A       10.0.1.2
www     IN  A       10.0.1.10
mail    IN  A       10.0.1.20
db      IN  A       10.0.1.30

; AAAA records
@       IN  AAAA    2001:db8::10
www     IN  AAAA    2001:db8::10

; CNAME records
ftp     IN  CNAME   www.example.com.
blog    IN  CNAME   www.example.com.

; MX records
@       IN  MX  10  mail.example.com.
@       IN  MX  20  mail-backup.example.com.

; TXT records (SPF, DKIM, DMARC)
@       IN  TXT     "v=spf1 mx ip4:10.0.1.20 -all"
_dmarc  IN  TXT     "v=DMARC1; p=reject; rua=mailto:dmarc@example.com"

; SRV records
_ldap._tcp  IN  SRV 0 100 389 ldap.example.com.
_sip._tcp   IN  SRV 10 60 5060 sip.example.com.

; CAA records
@       IN  CAA 0 issue "letsencrypt.org"
@       IN  CAA 0 iodef "mailto:security@example.com"
```

### SOA Serial Number Convention

Always use the `YYYYMMDDNN` format where `NN` is a two-digit revision counter starting at `01`. Increment the serial every time you modify the zone. Secondary servers compare serials to decide whether to initiate a zone transfer (AXFR/IXFR).

### Wildcard Records

```
; Catch-all: any subdomain not explicitly defined resolves here
*       IN  A       10.0.1.10
```

Use wildcards carefully -- they can mask misconfigurations and make debugging harder.

---

## 3. DNSSEC Key Generation and Zone Signing

DNSSEC adds cryptographic signatures to DNS records, allowing resolvers to verify authenticity and integrity.

### Generating Keys

```bash
# Create the zone directory for keys
sudo mkdir -p /etc/bind/keys

# Generate the Zone Signing Key (ZSK) -- signs individual records
sudo dnssec-keygen -a ECDSAP256SHA256 -n ZONE example.com
# Produces: Kexample.com.+013+XXXXX.key and .private

# Generate the Key Signing Key (KSK) -- signs the DNSKEY RRset
sudo dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK example.com
# Produces: Kexample.com.+013+YYYYY.key and .private

# Move keys into place
sudo mv Kexample.com.+013+* /etc/bind/keys/
```

### Signing the Zone

```bash
# Sign the zone file (produces db.example.com.signed)
sudo dnssec-signzone -A -3 $(head -c 1000 /dev/urandom | sha1sum | cut -b 1-16) \
    -N INCREMENT -o example.com -t \
    -K /etc/bind/keys \
    /etc/bind/zones/db.example.com

# Update named.conf to use the signed zone
# file "/etc/bind/zones/db.example.com.signed";
```

### Automated DNSSEC with BIND9 Inline Signing

Modern BIND9 supports inline signing, which removes the need for manual re-signing.

```
// named.conf.local
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com";
    key-directory "/etc/bind/keys";
    inline-signing yes;
    auto-dnssec maintain;
    allow-transfer { 10.0.1.2; };
};
```

With `auto-dnssec maintain` and `inline-signing yes`, BIND9 automatically signs new or updated records and handles key rollovers when new keys appear in the key directory.

### Publishing the DS Record

After signing, extract the DS record and publish it with your domain registrar or parent zone operator:

```bash
sudo dnssec-dsfromkey /etc/bind/keys/Kexample.com.+013+YYYYY.key
# Output: example.com. IN DS 12345 13 2 ABCDEF0123456789...
```

### Verifying DNSSEC

```bash
# Query with DNSSEC validation
dig +dnssec example.com A

# Check the chain of trust
delv @127.0.0.1 example.com A +rtrace
```

---

## 4. dnsmasq Combined DNS and DHCP

dnsmasq is a lightweight daemon that provides DNS forwarding, DHCP, TFTP, and router advertisement services. It is ideal for small networks, development environments, and embedded systems.

### Installation

```bash
# Debian/Ubuntu
sudo apt-get install -y dnsmasq

# RHEL/Rocky
sudo dnf install -y dnsmasq

# Disable systemd-resolved to avoid port 53 conflict
sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
```

### Combined DNS + DHCP Configuration

```
# /etc/dnsmasq.conf

# --- General ---
domain-needed           # Never forward plain names (without a dot)
bogus-priv              # Never forward reverse lookups for private ranges
no-resolv               # Do not read /etc/resolv.conf
no-poll                 # Do not poll /etc/resolv.conf for changes

# --- Upstream DNS ---
server=1.1.1.1
server=1.0.0.1
server=8.8.8.8

# --- Local domain ---
local=/home.lab/
domain=home.lab

# --- DNS cache ---
cache-size=10000

# --- Interface binding ---
interface=eth0
bind-interfaces

# --- DHCP range ---
dhcp-range=192.168.1.100,192.168.1.200,255.255.255.0,24h

# --- Default gateway ---
dhcp-option=option:router,192.168.1.1

# --- DNS server pushed to clients ---
dhcp-option=option:dns-server,192.168.1.1

# --- NTP server ---
dhcp-option=option:ntp-server,192.168.1.1

# --- Static DHCP leases (MAC -> IP -> hostname) ---
dhcp-host=aa:bb:cc:dd:ee:01,192.168.1.10,nas,infinite
dhcp-host=aa:bb:cc:dd:ee:02,192.168.1.11,printer,infinite
dhcp-host=aa:bb:cc:dd:ee:03,192.168.1.12,ap-living-room,infinite

# --- PXE boot ---
dhcp-boot=pxelinux.0,pxeserver,192.168.1.5
enable-tftp
tftp-root=/srv/tftp

# --- Local DNS overrides ---
address=/myapp.home.lab/192.168.1.10
address=/pihole.home.lab/192.168.1.2

# --- Logging ---
log-queries
log-facility=/var/log/dnsmasq.log
```

### Verifying dnsmasq

```bash
# Test configuration syntax
dnsmasq --test

# View current DHCP leases
cat /var/lib/misc/dnsmasq.leases

# Query local DNS
dig @127.0.0.1 myapp.home.lab A +short
```

---

## 5. CoreDNS for Container-Native Environments

CoreDNS is the default DNS server in Kubernetes. It uses a plugin-based architecture configured through a Corefile.

### Corefile Plugin Chain

```
# /etc/coredns/Corefile

# Kubernetes cluster DNS
cluster.local:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
        max_concurrent 1000
    }
    cache 30
    loop
    reload
    loadbalance
}

# Internal corporate domain -- forward to on-prem DNS
corp.internal:53 {
    errors
    cache 60
    forward . 10.0.1.1 10.0.1.2 {
        policy sequential
        health_check 5s
    }
}

# Default: forward everything else to public resolvers
.:53 {
    errors
    health
    ready
    forward . tls://1.1.1.1 tls://1.0.0.1 {
        tls_servername cloudflare-dns.com
        health_check 10s
    }
    cache 300 {
        success 9984 300
        denial 9984 5
    }
    prometheus :9153
    loop
    reload 10s
    loadbalance
}
```

### Plugin Execution Order

Plugins in a server block execute in a fixed order defined at compile time, not the order in the Corefile. Key plugins and their roles:

| Plugin | Purpose |
|--------|---------|
| `errors` | Log errors to stdout |
| `health` | Healthcheck endpoint on :8080/health |
| `ready` | Readiness endpoint on :8181/ready |
| `kubernetes` | Resolve Kubernetes service/pod DNS |
| `forward` | Proxy queries to upstream resolvers |
| `cache` | Cache responses with configurable TTL |
| `loop` | Detect and halt forwarding loops |
| `reload` | Automatically reload Corefile on change |
| `loadbalance` | Round-robin A/AAAA record ordering |
| `prometheus` | Export metrics on :9153/metrics |

### Deploying CoreDNS in Kubernetes

CoreDNS is deployed as a Deployment with a ConfigMap for the Corefile.

```bash
# Edit the CoreDNS ConfigMap
kubectl -n kube-system edit configmap coredns

# Restart CoreDNS pods to pick up changes
kubectl -n kube-system rollout restart deployment coredns

# Verify CoreDNS is responding
kubectl run dnstest --image=busybox:1.36 --rm -it --restart=Never -- \
    nslookup kubernetes.default.svc.cluster.local
```

---

## 6. Pi-hole Ad-Blocking DNS

Pi-hole acts as a DNS sinkhole, blocking advertisements and trackers at the network level by intercepting DNS queries and returning NXDOMAIN for blocked domains.

### Docker Deployment

```yaml
# docker-compose.yml
services:
  pihole:
    image: pihole/pihole:2025.03.0
    container_name: pihole
    hostname: pihole
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "80:80/tcp"
    environment:
      TZ: "America/New_York"
      WEBPASSWORD: "${PIHOLE_PASSWORD}"
      PIHOLE_DNS_: "1.1.1.1;1.0.0.1"
      DNSSEC: "true"
      QUERY_LOGGING: "true"
      DNSMASQ_LISTENING: "all"
    volumes:
      - pihole_etc:/etc/pihole
      - pihole_dnsmasq:/etc/dnsmasq.d
    restart: unless-stopped
    dns:
      - 127.0.0.1
      - 1.1.1.1
    cap_add:
      - NET_ADMIN

volumes:
  pihole_etc:
  pihole_dnsmasq:
```

### Custom Local DNS in Pi-hole

```
# /etc/pihole/custom.list (local DNS records)
192.168.1.10    nas.home.lab
192.168.1.11    printer.home.lab
192.168.1.1     router.home.lab
```

### Custom Block and Allow Lists

```bash
# Add a blocklist via CLI
pihole -b ads.badsite.com tracking.example.net

# Add to allowlist
pihole -w required-cdn.example.com

# Update gravity (blocklist database)
pihole -g

# View query log
pihole -t

# Check status
pihole status
```

---

## 7. ISC Kea DHCP Server

ISC Kea is the modern replacement for ISC DHCP (dhcpd). It uses a JSON configuration format, supports a REST API, and can store leases in a database backend (MySQL, PostgreSQL, Cassandra).

### Installation

```bash
# Debian/Ubuntu
sudo apt-get install -y kea-dhcp4-server kea-dhcp6-server kea-ctrl-agent

# RHEL/Rocky
sudo dnf install -y kea
```

### Kea DHCPv4 Configuration

```json
{
    "Dhcp4": {
        "interfaces-config": {
            "interfaces": ["eth0"]
        },
        "lease-database": {
            "type": "memfile",
            "persist": true,
            "lfc-interval": 3600,
            "name": "/var/lib/kea/dhcp4.leases"
        },
        "valid-lifetime": 86400,
        "renew-timer": 43200,
        "rebind-timer": 75600,
        "subnet4": [
            {
                "id": 1,
                "subnet": "192.168.1.0/24",
                "pools": [
                    { "pool": "192.168.1.100 - 192.168.1.200" }
                ],
                "option-data": [
                    { "name": "routers", "data": "192.168.1.1" },
                    { "name": "domain-name-servers", "data": "192.168.1.1, 1.1.1.1" },
                    { "name": "domain-name", "data": "home.lab" },
                    { "name": "ntp-servers", "data": "192.168.1.1" }
                ],
                "reservations": [
                    {
                        "hw-address": "aa:bb:cc:dd:ee:01",
                        "ip-address": "192.168.1.10",
                        "hostname": "nas"
                    },
                    {
                        "hw-address": "aa:bb:cc:dd:ee:02",
                        "ip-address": "192.168.1.11",
                        "hostname": "printer"
                    },
                    {
                        "hw-address": "aa:bb:cc:dd:ee:03",
                        "ip-address": "192.168.1.12",
                        "hostname": "ap-living-room"
                    }
                ]
            }
        ],
        "loggers": [
            {
                "name": "kea-dhcp4",
                "output_options": [
                    { "output": "/var/log/kea/kea-dhcp4.log" }
                ],
                "severity": "INFO",
                "debuglevel": 0
            }
        ]
    }
}
```

### Kea Control Agent and REST API

```bash
# Start the control agent
sudo systemctl enable --now kea-ctrl-agent

# Query all leases via REST API
curl -s -X POST http://127.0.0.1:8000/ \
    -H "Content-Type: application/json" \
    -d '{"command": "lease4-get-all", "service": ["dhcp4"]}' | jq .

# Get a specific lease by IP
curl -s -X POST http://127.0.0.1:8000/ \
    -H "Content-Type: application/json" \
    -d '{
        "command": "lease4-get",
        "service": ["dhcp4"],
        "arguments": { "ip-address": "192.168.1.100" }
    }' | jq .

# Add a reservation at runtime
curl -s -X POST http://127.0.0.1:8000/ \
    -H "Content-Type: application/json" \
    -d '{
        "command": "reservation-add",
        "service": ["dhcp4"],
        "arguments": {
            "reservation": {
                "subnet-id": 1,
                "hw-address": "aa:bb:cc:dd:ee:04",
                "ip-address": "192.168.1.13",
                "hostname": "newhost"
            }
        }
    }' | jq .
```

### DHCP Relay

When the DHCP server is on a different subnet from the clients, a relay agent forwards DHCP broadcast packets as unicast.

```bash
# Install ISC DHCP relay (works with Kea too)
sudo apt-get install -y isc-dhcp-relay

# Configure relay -- /etc/default/isc-dhcp-relay
SERVERS="10.0.1.5"           # Kea DHCP server address
INTERFACES="eth0 eth1"      # Interfaces to listen on
OPTIONS=""
```

On network equipment (e.g., a router), configure `ip helper-address` (Cisco) or `dhcp-relay` (Linux/VyOS) to forward DHCP broadcasts to the server subnet.

---

## 8. DNS-over-TLS and DNS-over-HTTPS

Encrypted DNS prevents eavesdropping and manipulation of DNS queries between the client and the resolver.

### DNS-over-TLS (DoT) -- Port 853

DoT wraps standard DNS queries in TLS. Configure a stub resolver such as `stubby` on the client side.

```yaml
# /etc/stubby/stubby.yml
resolution_type: GETDNS_RESOLUTION_STUB
dns_transport_list:
  - GETDNS_TRANSPORT_TLS
tls_authentication: GETDNS_AUTHENTICATION_REQUIRED
tls_query_padding_blocksize: 128
round_robin_upstreams: 1
idle_timeout: 10000
listen_addresses:
  - 127.0.0.1@5353
  - 0::1@5353
upstream_recursive_servers:
  - address_data: 1.1.1.1
    tls_auth_name: "cloudflare-dns.com"
  - address_data: 1.0.0.1
    tls_auth_name: "cloudflare-dns.com"
  - address_data: 9.9.9.9
    tls_auth_name: "dns.quad9.net"
```

Then configure `/etc/resolv.conf` or systemd-resolved to send queries to `127.0.0.1:5353`.

### DNS-over-HTTPS (DoH) -- Port 443

DoH sends DNS queries as HTTPS requests, making them indistinguishable from regular web traffic.

### Configuring BIND9 as a DoT Forwarder

```
// named.conf.options -- forward to DoT upstream
options {
    forwarders {
        1.1.1.1 port 853;
        1.0.0.1 port 853;
    };
    forward only;
};

// TLS configuration for incoming DoT (BIND 9.18+)
tls local-tls {
    cert-file "/etc/letsencrypt/live/dns.example.com/fullchain.pem";
    key-file "/etc/letsencrypt/live/dns.example.com/privkey.pem";
};

// Listen for DoT on port 853
options {
    listen-on tls local-tls { any; };
};
```

### Testing Encrypted DNS

```bash
# Test DoT with kdig (knot-dnsutils)
kdig -d @1.1.1.1 +tls-ca +tls-hostname=cloudflare-dns.com example.com A

# Test DoH with curl
curl -s -H "accept: application/dns-json" \
    "https://cloudflare-dns.com/dns-query?name=example.com&type=A" | jq .

# Test DoH with dog (modern dig alternative)
dog example.com A --https @https://dns.google/dns-query
```

---

## 9. Split-Horizon DNS and Conditional Forwarding

Split-horizon DNS returns different answers depending on the source network of the query. This is common for serving internal IPs to LAN clients and public IPs to external clients.

### BIND9 Split-Horizon with Views

```
// /etc/bind/named.conf

acl "internal" {
    10.0.0.0/8;
    172.16.0.0/12;
    192.168.0.0/16;
    localhost;
};

acl "external" {
    !internal;
    any;
};

view "internal-view" {
    match-clients { internal; };
    recursion yes;

    zone "example.com" {
        type master;
        file "/etc/bind/zones/internal/db.example.com";
    };
};

view "external-view" {
    match-clients { external; };
    recursion no;

    zone "example.com" {
        type master;
        file "/etc/bind/zones/external/db.example.com";
    };
};
```

The internal zone file points `www.example.com` to `10.0.1.10`, while the external zone file points it to the public IP `203.0.113.10`.

### Conditional Forwarding in dnsmasq

```
# /etc/dnsmasq.conf

# Forward queries for corp.internal to the corporate DNS servers
server=/corp.internal/10.0.1.1
server=/corp.internal/10.0.1.2

# Forward reverse lookups for 10.x.x.x to corporate DNS
server=/10.in-addr.arpa/10.0.1.1

# Forward queries for partner.net to partner DNS
server=/partner.net/203.0.113.53
```

### Conditional Forwarding in CoreDNS

```
# Corefile snippet
corp.internal:53 {
    forward . 10.0.1.1 10.0.1.2
    cache 60
    errors
}

partner.net:53 {
    forward . 203.0.113.53
    cache 120
    errors
}
```

---

## 10. Reverse DNS and PTR Records

Reverse DNS maps IP addresses back to hostnames. PTR records live in special `in-addr.arpa` (IPv4) or `ip6.arpa` (IPv6) zones.

### Reverse Zone File

```
; /etc/bind/zones/db.10.0.1
$TTL    86400
@   IN  SOA     ns1.example.com. admin.example.com. (
                2026022601  ; Serial
                3600        ; Refresh
                900         ; Retry
                1209600     ; Expire
                86400       ; Negative cache TTL
    )

@   IN  NS      ns1.example.com.
@   IN  NS      ns2.example.com.

; PTR records (last octet of IP -> hostname)
1   IN  PTR     ns1.example.com.
2   IN  PTR     ns2.example.com.
10  IN  PTR     www.example.com.
20  IN  PTR     mail.example.com.
30  IN  PTR     db.example.com.
```

### Classless Reverse Delegation (RFC 2317)

For subnets smaller than /24, the parent zone delegates reverse DNS using CNAME records:

```
; Parent zone: 1.168.192.in-addr.arpa (maintained by ISP)
; Delegating 192.168.1.128/26 to customer
128/26  IN  NS  ns1.customer.example.
129     IN  CNAME   129.128/26.1.168.192.in-addr.arpa.
130     IN  CNAME   130.128/26.1.168.192.in-addr.arpa.
; ... and so on for each IP in the range
```

### Verifying Reverse DNS

```bash
# Forward lookup
dig +short www.example.com A
# 10.0.1.10

# Reverse lookup
dig +short -x 10.0.1.10
# www.example.com.

# Using host command
host 10.0.1.10
# 10.1.0.10.in-addr.arpa domain name pointer www.example.com.
```

---

## 11. DHCP Reservations, Leases, and PXE Boot

### Static DHCP Reservations

Static reservations guarantee that a device always receives the same IP address based on its MAC address.

**In dnsmasq:**

```
# /etc/dnsmasq.conf
dhcp-host=aa:bb:cc:dd:ee:01,192.168.1.10,nas,infinite
dhcp-host=aa:bb:cc:dd:ee:02,192.168.1.11,printer,12h
# By client-id instead of MAC
dhcp-host=id:01:aa:bb:cc:dd:ee:03,192.168.1.12,workstation
```

**In ISC Kea (JSON):** see the `reservations` array in Section 7 above.

### Lease Management

```bash
# dnsmasq leases file
cat /var/lib/misc/dnsmasq.leases
# Format: expiry_epoch MAC IP hostname client-id

# Kea leases file (CSV-like memfile)
cat /var/lib/kea/dhcp4.leases

# Kea: query leases via REST API
curl -s -X POST http://127.0.0.1:8000/ \
    -H "Content-Type: application/json" \
    -d '{"command": "lease4-get-all", "service": ["dhcp4"]}' | jq '.arguments.leases[]'

# Kea: delete a lease
curl -s -X POST http://127.0.0.1:8000/ \
    -H "Content-Type: application/json" \
    -d '{
        "command": "lease4-del",
        "service": ["dhcp4"],
        "arguments": { "ip-address": "192.168.1.150" }
    }' | jq .
```

### PXE Boot via DHCP Options

PXE (Preboot Execution Environment) allows network booting by providing a TFTP server and boot filename via DHCP options.

**dnsmasq PXE boot configuration:**

```
# /etc/dnsmasq.conf

# BIOS PXE boot
dhcp-boot=pxelinux.0,pxeserver,192.168.1.5

# UEFI PXE boot (architecture-aware)
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-match=set:bios,option:client-arch,0

dhcp-boot=tag:efi-x86_64,grubx64.efi,pxeserver,192.168.1.5
dhcp-boot=tag:bios,pxelinux.0,pxeserver,192.168.1.5

# Enable TFTP
enable-tftp
tftp-root=/srv/tftp
```

**ISC Kea PXE boot options:**

```json
{
    "Dhcp4": {
        "client-classes": [
            {
                "name": "UEFI-64",
                "test": "option[93].hex == 0x0007 or option[93].hex == 0x0009",
                "boot-file-name": "grubx64.efi",
                "next-server": "192.168.1.5"
            },
            {
                "name": "BIOS",
                "test": "option[93].hex == 0x0000",
                "boot-file-name": "pxelinux.0",
                "next-server": "192.168.1.5"
            }
        ]
    }
}
```

---

## 12. DNS Caching, TTL Tuning, and systemd-resolved

### TTL Tuning Guidelines

| Record Type | Recommended TTL | Rationale |
|-------------|----------------|-----------|
| SOA Minimum | 300 -- 3600 | Negative cache duration |
| NS | 86400 (24h) | Name servers change rarely |
| A/AAAA (stable) | 3600 -- 86400 | Typical production workloads |
| A/AAAA (failover) | 60 -- 300 | Rapid failover / blue-green |
| MX | 3600 -- 86400 | Mail servers change infrequently |
| CNAME | 300 -- 3600 | Match the target record TTL |
| TXT (SPF/DKIM) | 3600 | Allows timely updates for email auth |
| SRV | 300 -- 3600 | Service discovery |

Lower TTLs increase query volume to authoritative servers. Raise TTLs for stable records to reduce load and improve client performance.

### BIND9 Caching Configuration

```
// named.conf.options
options {
    // Maximum cache size (default is unlimited -- dangerous)
    max-cache-size 256m;

    // Maximum time to cache positive answers
    max-cache-ttl 86400;

    // Maximum time to cache negative answers (NXDOMAIN)
    max-ncache-ttl 3600;

    // Prefetch records nearing expiry (BIND 9.10+)
    prefetch 2 9;
};
```

### systemd-resolved Integration

On modern Linux distributions, `systemd-resolved` manages local DNS resolution. It can conflict with local DNS/DHCP servers.

```bash
# Check current DNS configuration
resolvectl status

# View DNS cache statistics
resolvectl statistics

# Flush the DNS cache
resolvectl flush-caches

# Configure systemd-resolved to use a local server
# /etc/systemd/resolved.conf
# [Resolve]
# DNS=127.0.0.1
# FallbackDNS=1.1.1.1 8.8.8.8
# Domains=~.
# DNSStubListener=no    # Disable stub listener on 127.0.0.53:53
```

When running a local DNS server (BIND9, dnsmasq, etc.), disable the stub listener to free port 53:

```bash
# Disable systemd-resolved stub listener
sudo sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
sudo systemctl restart systemd-resolved

# Point /etc/resolv.conf to the local server
sudo rm /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
```

### Monitoring DNS Performance

```bash
# Query timing with dig
dig example.com A +stats | grep "Query time"

# Bulk query testing with dnsperf
dnsperf -s 127.0.0.1 -d queryfile.txt -l 30 -c 10

# BIND9 statistics channel
# named.conf:
# statistics-channels {
#     inet 127.0.0.1 port 8053 allow { localhost; };
# };
curl -s http://127.0.0.1:8053/ | xmllint --format -
```

---

## 13. Best Practices

1. **Use separate authoritative and recursive servers** -- do not expose recursive resolvers to the internet to prevent DNS amplification attacks.
2. **Enable DNSSEC on all authoritative zones** -- sign zones and publish DS records with the parent to provide authenticity and integrity.
3. **Increment SOA serial on every zone change** -- use the YYYYMMDDNN convention and always verify with `named-checkzone` before reloading.
4. **Restrict zone transfers with `allow-transfer`** -- only permit secondary name servers to pull zone data via AXFR/IXFR.
5. **Use rate limiting** -- configure `rate-limit` in BIND9 or equivalent mechanisms to mitigate amplification and reflection attacks.
6. **Deploy encrypted DNS (DoT/DoH)** -- protect client queries from eavesdropping, especially on untrusted networks.
7. **Set appropriate TTLs** -- balance between caching efficiency and failover speed; lower TTLs before planned migrations.
8. **Use DHCP reservations for infrastructure devices** -- servers, network equipment, printers, and access points should have stable IPs.
9. **Monitor lease utilization** -- alert when DHCP pools approach exhaustion (above 80% utilization).
10. **Keep forward and reverse zones synchronized** -- every A/AAAA record with a public-facing service should have a corresponding PTR record.
11. **Disable open recursion** -- restrict `allow-recursion` to trusted networks only.
12. **Test configuration before reloading** -- always run `named-checkconf`, `named-checkzone`, or `dnsmasq --test` before applying changes.
13. **Log queries during troubleshooting only** -- DNS query logs are verbose and can impact performance; disable them in steady state.
14. **Use CAA records** -- specify which certificate authorities are permitted to issue certificates for your domains.
15. **Implement split-horizon DNS** for internal/external resolution -- avoid exposing internal network topology to external clients.

---

## 14. Anti-Patterns

- **Running an open recursive resolver on the internet** -- this enables DNS amplification DDoS attacks and will get your server abused.
- **Forgetting to increment the SOA serial** -- secondary servers will not pick up zone changes, leading to stale DNS records across your infrastructure.
- **Using wildcard records without understanding the consequences** -- wildcards match all undefined names and can silently mask typos or misconfigurations.
- **Hardcoding DNS server IPs in application configuration** -- use system resolver settings (`/etc/resolv.conf` or systemd-resolved) so changes propagate centrally.
- **Setting TTLs to zero** -- this forces every lookup to hit the authoritative server, dramatically increasing latency and load.
- **Storing DHCP leases only in memory without persistence** -- a server restart causes all clients to lose their leases and request new ones simultaneously (DHCP storm).
- **Running DHCP servers on multiple subnets without relay agents** -- DHCP broadcasts do not cross subnet boundaries; use relay agents or configure servers per-subnet.
- **Neglecting reverse DNS** -- missing PTR records cause email delivery failures (spam filters check rDNS), slow SSH logins (UseDNS), and broken monitoring tools.
- **Using BIND9 `allow-update { any; }` in production** -- this allows anyone to dynamically modify your zone records.
- **Ignoring DNSSEC key rollovers** -- expired DNSSEC signatures cause total resolution failure for the signed zone; automate key management.
- **Disabling systemd-resolved without updating /etc/resolv.conf** -- the system loses DNS resolution entirely.
- **Running PXE/TFTP without network segmentation** -- PXE boot infrastructure should be isolated to provisioning VLANs to prevent unauthorized network booting.

---

## 15. Sources & References

- BIND9 Administrator Reference Manual: https://bind9.readthedocs.io/en/latest/
- ISC Kea DHCP Documentation: https://kea.readthedocs.io/en/latest/
- CoreDNS Manual and Plugin Reference: https://coredns.io/manual/toc/
- Pi-hole Documentation: https://docs.pi-hole.net/
- dnsmasq Manual Page: https://thekelleys.org.uk/dnsmasq/doc.html
- DNSSEC Guide by ICANN: https://www.icann.org/resources/pages/dnssec-what-is-it-why-important-2019-03-05-en
- RFC 1035 -- Domain Names Implementation and Specification: https://datatracker.ietf.org/doc/html/rfc1035
- RFC 7858 -- DNS over TLS: https://datatracker.ietf.org/doc/html/rfc7858
- RFC 8484 -- DNS Queries over HTTPS (DoH): https://datatracker.ietf.org/doc/html/rfc8484
- Cloudflare DNS Learning Center: https://www.cloudflare.com/learning/dns/what-is-dns/
- RFC 2317 -- Classless IN-ADDR.ARPA Delegation: https://datatracker.ietf.org/doc/html/rfc2317
