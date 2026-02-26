---
name: firewall-routing
description: Linux firewall configuration with nftables/iptables, NAT, policy-based routing, VLAN tagging, bridge networking, traffic shaping, and fail2ban integration
---

# Linux Firewall and Routing

## Purpose

Guide network engineer agents in configuring Linux firewalls, routing policies, and traffic management. Covers nftables as the primary framework (replacing iptables in modern kernels), legacy iptables for existing deployments, UFW for simplified management, NAT variants (SNAT/DNAT/masquerade), policy-based routing, VLAN tagging with 802.1Q, bridge networking for containers, traffic shaping with tc, connection tracking, and fail2ban integration for automated threat response.

## Table of Contents

1. [nftables Fundamentals](#1-nftables-fundamentals)
2. [iptables Legacy Reference](#2-iptables-legacy-reference)
3. [UFW Simplified Firewall](#3-ufw-simplified-firewall)
4. [Network Address Translation (NAT)](#4-network-address-translation-nat)
5. [Port Forwarding and NAT Hairpinning](#5-port-forwarding-and-nat-hairpinning)
6. [Policy-Based Routing](#6-policy-based-routing)
7. [VLAN Tagging (802.1Q)](#7-vlan-tagging-8021q)
8. [Bridge Networking for Containers](#8-bridge-networking-for-containers)
9. [Traffic Shaping with tc](#9-traffic-shaping-with-tc)
10. [Connection Tracking and Stateful Rules](#10-connection-tracking-and-stateful-rules)
11. [Rate Limiting and Geo-Blocking](#11-rate-limiting-and-geo-blocking)
12. [Logging and Diagnostics](#12-logging-and-diagnostics)
13. [fail2ban Integration](#13-fail2ban-integration)
14. [Best Practices](#14-best-practices)
15. [Anti-Patterns](#15-anti-patterns)
16. [Sources & References](#16-sources--references)

---

## 1. nftables Fundamentals

nftables is the successor to iptables, ip6tables, arptables, and ebtables. It provides a unified framework for packet filtering and classification with a cleaner syntax, atomic rule replacement, and better performance through set-based matching.

### Architecture: Tables, Chains, and Rules

nftables organizes rules into a hierarchy: **tables** contain **chains**, and chains contain **rules**. Unlike iptables, table and chain names are arbitrary and there are no built-in chains.

- **Table**: A namespace that holds chains. Each table has a family (ip, ip6, inet, arp, bridge, netdev).
- **Chain**: A container for rules. Chains have a type (filter, route, nat), a hook (prerouting, input, forward, output, postrouting), and a priority.
- **Rule**: A match-action pair. Rules are evaluated sequentially within a chain.

### Family Types

| Family   | Description                              |
|----------|------------------------------------------|
| `ip`     | IPv4 only                                |
| `ip6`    | IPv6 only                                |
| `inet`   | Both IPv4 and IPv6 (recommended)         |
| `arp`    | ARP-level filtering                      |
| `bridge` | Bridge-level (L2) filtering              |
| `netdev` | Ingress/egress on a specific device      |

### Basic nftables Configuration

```nft
#!/usr/sbin/nft -f

# Flush existing ruleset
flush ruleset

# Create a table for inet (IPv4 + IPv6)
table inet firewall {

    # Define sets for trusted networks and blocked IPs
    set trusted_nets {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 }
    }

    set blocklist {
        type ipv4_addr
        flags timeout
        timeout 1h
    }

    # Input chain: traffic destined for the local machine
    chain input {
        type filter hook input priority 0; policy drop;

        # Allow established and related connections
        ct state established,related accept

        # Drop invalid packets early
        ct state invalid drop

        # Allow loopback
        iif "lo" accept

        # Drop blocked IPs
        ip saddr @blocklist drop

        # Allow ICMP (ping) with rate limit
        ip protocol icmp icmp type echo-request limit rate 5/second accept
        ip6 nexthdr icmpv6 icmpv6 type echo-request limit rate 5/second accept

        # Allow ICMPv6 neighbor discovery (required for IPv6)
        ip6 nexthdr icmpv6 icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, nd-router-advert } accept

        # Allow SSH from trusted networks only
        ip saddr @trusted_nets tcp dport 22 accept

        # Allow HTTP/HTTPS from anywhere
        tcp dport { 80, 443 } accept

        # Allow DNS (for local resolver)
        tcp dport 53 accept
        udp dport 53 accept

        # Log and drop everything else
        log prefix "nft-input-drop: " flags all counter drop
    }

    # Forward chain: traffic being routed through this machine
    chain forward {
        type filter hook forward priority 0; policy drop;

        ct state established,related accept
        ct state invalid drop

        # Allow forwarding from internal to external
        iifname "eth1" oifname "eth0" accept

        # Allow forwarding for specific container bridge
        iifname "br-containers" oifname "eth0" accept
        iifname "eth0" oifname "br-containers" ct state established,related accept

        log prefix "nft-forward-drop: " flags all counter drop
    }

    # Output chain: traffic originating from the local machine
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

### Managing nftables

```shell
# Load ruleset from file
sudo nft -f /etc/nftables.conf

# List full ruleset
sudo nft list ruleset

# List a specific table
sudo nft list table inet firewall

# Add a rule interactively
sudo nft add rule inet firewall input tcp dport 8080 accept

# Insert a rule at the beginning of a chain
sudo nft insert rule inet firewall input position 0 tcp dport 8443 accept

# Delete a rule by handle number
sudo nft -a list chain inet firewall input   # shows handles
sudo nft delete rule inet firewall input handle 15

# Add an element to a named set
sudo nft add element inet firewall blocklist { 203.0.113.50 timeout 30m }

# Flush a specific chain
sudo nft flush chain inet firewall input

# Enable nftables service persistence
sudo systemctl enable nftables
sudo systemctl start nftables
```

### nftables Sets and Maps

Sets enable efficient matching against large lists. Maps allow key-value lookups for verdict or data mapping.

```nft
# Named set with auto-merge for CIDR aggregation
set geo_block {
    type ipv4_addr
    flags interval
    auto-merge
    elements = { 198.51.100.0/24, 203.0.113.0/24 }
}

# Verdict map: route traffic to different chains based on port
map port_dispatch {
    type inet_service : verdict
    elements = {
        22 : jump ssh_chain,
        80 : jump http_chain,
        443 : jump http_chain
    }
}

chain input {
    type filter hook input priority 0; policy drop;
    ip saddr @geo_block drop
    tcp dport vmap @port_dispatch
}
```

---

## 2. iptables Legacy Reference

iptables remains relevant for older systems and for understanding existing configurations. It uses a fixed set of tables and built-in chains.

### Chain Flow (Packet Traversal)

```
                               INCOMING PACKET
                                     |
                                     v
                              [PREROUTING]
                           (raw, conntrack, mangle, nat)
                                     |
                             routing decision
                            /                \
                           v                  v
                      [INPUT]            [FORWARD]
                  (mangle, filter)    (mangle, filter)
                       |                     |
                       v                     v
                  local process       [POSTROUTING]
                       |              (mangle, nat)
                       v                     |
                   [OUTPUT]                  v
             (raw, conntrack,          OUTGOING PACKET
              mangle, nat, filter)
                       |
                       v
                  [POSTROUTING]
                  (mangle, nat)
                       |
                       v
                  OUTGOING PACKET
```

### Tables and Their Purpose

| Table    | Chains                                           | Purpose                         |
|----------|--------------------------------------------------|---------------------------------|
| `filter` | INPUT, FORWARD, OUTPUT                           | Packet filtering (accept/drop)  |
| `nat`    | PREROUTING, INPUT, OUTPUT, POSTROUTING           | Network address translation     |
| `mangle` | All five chains                                  | Packet header modification      |
| `raw`    | PREROUTING, OUTPUT                               | Bypass connection tracking       |

### Common iptables Commands

```shell
# List all rules with line numbers
sudo iptables -L -n -v --line-numbers

# Set default policy to DROP on INPUT
sudo iptables -P INPUT DROP

# Allow established and related connections
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow SSH from a specific subnet
sudo iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 22 -j ACCEPT

# Allow HTTP and HTTPS
sudo iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

# Drop and log packets from a specific IP
sudo iptables -A INPUT -s 198.51.100.5 -j LOG --log-prefix "iptables-blocked: "
sudo iptables -A INPUT -s 198.51.100.5 -j DROP

# Delete rule by line number
sudo iptables -D INPUT 3

# Save rules (Debian/Ubuntu)
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6

# Restore rules
sudo iptables-restore < /etc/iptables/rules.v4

# Install persistence package
sudo apt install iptables-persistent
```

### Migrating from iptables to nftables

Use `iptables-translate` to convert rules:

```shell
# Translate a single rule
iptables-translate -A INPUT -p tcp --dport 22 -j ACCEPT
# Output: nft add rule ip filter INPUT tcp dport 22 counter accept

# Translate entire ruleset
iptables-save | iptables-restore-translate > /etc/nftables-migrated.conf
```

---

## 3. UFW Simplified Firewall

UFW (Uncomplicated Firewall) is a frontend for iptables/nftables aimed at simplifying firewall management on Ubuntu and Debian systems. It is suitable for single-host configurations but not for complex routing scenarios.

### Basic UFW Commands

```shell
# Enable UFW with default deny incoming, allow outgoing
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow from a specific subnet
sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp

# Deny a specific IP
sudo ufw deny from 198.51.100.5

# Rate limit SSH (deny if >6 connections in 30 seconds)
sudo ufw limit 22/tcp

# Delete a rule by number
sudo ufw status numbered
sudo ufw delete 3

# Check status
sudo ufw status verbose

# Application profiles
sudo ufw app list
sudo ufw allow 'Nginx Full'
```

### UFW Application Profiles

UFW reads application profiles from `/etc/ufw/applications.d/`. Custom profiles:

```ini
# /etc/ufw/applications.d/myapp
[MyApp]
title=My Application Server
description=Custom application on ports 8080 and 8443
ports=8080,8443/tcp
```

---

## 4. Network Address Translation (NAT)

NAT translates IP addresses and ports in packet headers as traffic passes through a gateway. Linux supports three primary NAT modes.

### NAT Types

| Type          | Direction  | Use Case                                    | nftables Hook   |
|---------------|------------|---------------------------------------------|-----------------|
| **SNAT**      | Outbound   | Rewrite source IP for outgoing traffic       | postrouting     |
| **DNAT**      | Inbound    | Rewrite destination IP for incoming traffic  | prerouting      |
| **Masquerade**| Outbound   | Dynamic SNAT (for dynamic external IPs)      | postrouting     |

### nftables NAT Configuration

```nft
table ip nat {

    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        # DNAT: forward external port 8080 to internal server 10.0.1.10:80
        tcp dport 8080 dnat to 10.0.1.10:80

        # DNAT: forward port range
        tcp dport 3000-3010 dnat to 10.0.1.20
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;

        # Masquerade: for dynamic WAN IP (common with DHCP ISP connections)
        oifname "eth0" masquerade

        # SNAT: for static WAN IP (more efficient than masquerade)
        # oifname "eth0" snat to 203.0.113.1
    }
}

# Required: enable IP forwarding
# echo 1 > /proc/sys/net/ipv4/ip_forward
# Or persistently in /etc/sysctl.conf:
# net.ipv4.ip_forward = 1
```

### iptables NAT Equivalents

```shell
# DNAT (port forwarding)
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.0.1.10:80

# Masquerade outbound traffic
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# SNAT with static IP
sudo iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to-source 203.0.113.1

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/99-forwarding.conf
```

### SNAT vs Masquerade

- **SNAT** requires a fixed source IP; the kernel caches the translation, making it faster.
- **Masquerade** queries the outgoing interface's IP on every packet; use it only when the external IP is dynamic (DHCP).
- On high-throughput gateways with a static IP, always prefer SNAT over masquerade.

---

## 5. Port Forwarding and NAT Hairpinning

### Standard Port Forwarding

Port forwarding (DNAT) redirects traffic arriving on a public-facing port to an internal server. A matching FORWARD rule must allow the traffic.

```nft
# In the nat table (prerouting chain)
tcp dport 443 dnat to 10.0.1.10:443

# In the filter table (forward chain) - must explicitly allow
iifname "eth0" oifname "eth1" ip daddr 10.0.1.10 tcp dport 443 accept
```

### NAT Hairpinning (NAT Reflection)

NAT hairpinning allows internal clients to access an internal server via the external (public) IP. Without hairpin NAT, internal clients sending traffic to the public IP will have the destination rewritten but the source will remain the internal IP, causing the server to reply directly to the client, bypassing the NAT gateway. The client then drops the response because it does not match the expected source.

Solution: apply SNAT (masquerade) on hairpin traffic so the server sees the gateway as the source.

```nft
table ip nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;
        # Standard DNAT
        tcp dport 443 dnat to 10.0.1.10:443
    }

    chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        # Normal masquerade for outbound
        oifname "eth0" masquerade

        # Hairpin NAT: masquerade internal-to-internal traffic that was DNAT'd
        ip saddr 10.0.1.0/24 ip daddr 10.0.1.10 tcp dport 443 masquerade
    }
}
```

---

## 6. Policy-Based Routing

Policy-based routing (PBR) allows routing decisions based on criteria other than the destination address, such as source IP, incoming interface, packet mark, or TOS field. Linux implements PBR through multiple routing tables selected by `ip rule`.

### Routing Tables

Linux supports 255 routing tables (IDs 0-255). Tables 253 (default), 254 (main), and 255 (local) are predefined.

```shell
# View all routing rules (priority order)
ip rule show

# View the main routing table
ip route show table main

# Define custom table names in /etc/iproute2/rt_tables
echo "100 isp2" | sudo tee -a /etc/iproute2/rt_tables
```

### Dual-WAN with Policy Routing

Route traffic from different subnets through different ISP gateways:

```shell
# Add routes to custom tables
sudo ip route add default via 203.0.113.1 dev eth0 table 100   # ISP1
sudo ip route add default via 198.51.100.1 dev eth1 table 200  # ISP2

# Add local network routes to both tables
sudo ip route add 10.0.0.0/8 dev eth2 table 100
sudo ip route add 10.0.0.0/8 dev eth2 table 200

# Policy rules: source-based routing
sudo ip rule add from 10.0.1.0/24 lookup 100 priority 100   # subnet 1 -> ISP1
sudo ip rule add from 10.0.2.0/24 lookup 200 priority 200   # subnet 2 -> ISP2

# Mark-based routing with nftables
# First, mark packets in nftables mangle:
# table ip mangle {
#     chain prerouting {
#         type route hook output priority mangle; policy accept;
#         ip daddr 192.0.2.0/24 meta mark set 0x1
#     }
# }

# Then route based on mark
sudo ip rule add fwmark 0x1 lookup 100 priority 50
```

### Making PBR Persistent

Use `networkd` drop-ins or a startup script. For systemd-networkd:

```ini
# /etc/systemd/network/10-eth0.network
[Match]
Name=eth0

[Network]
Address=203.0.113.5/24
Gateway=203.0.113.1

[RoutingPolicyRule]
From=10.0.1.0/24
Table=100
Priority=100
```

---

## 7. VLAN Tagging (802.1Q)

VLANs segment a physical network into isolated broadcast domains. Linux supports 802.1Q VLAN tagging natively through virtual subinterfaces.

### Creating VLAN Subinterfaces

```shell
# Load 8021q kernel module
sudo modprobe 8021q
echo "8021q" | sudo tee -a /etc/modules-load.d/vlans.conf

# Create VLAN subinterface (VLAN ID 100 on eth0)
sudo ip link add link eth0 name eth0.100 type vlan id 100
sudo ip addr add 10.100.0.1/24 dev eth0.100
sudo ip link set eth0.100 up

# Create VLAN subinterface (VLAN ID 200 on eth0)
sudo ip link add link eth0 name eth0.200 type vlan id 200
sudo ip addr add 10.200.0.1/24 dev eth0.200
sudo ip link set eth0.200 up

# Verify VLAN configuration
ip -d link show eth0.100
cat /proc/net/vlan/eth0.100
```

### Persistent VLAN Configuration (Netplan)

```yaml
# /etc/netplan/01-vlans.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
  vlans:
    eth0.100:
      id: 100
      link: eth0
      addresses:
        - 10.100.0.1/24
    eth0.200:
      id: 200
      link: eth0
      addresses:
        - 10.200.0.1/24
```

### Inter-VLAN Routing

When VLANs are terminated on a Linux router, enable IP forwarding and add firewall rules to control inter-VLAN traffic:

```nft
chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept

    # Allow VLAN 100 -> VLAN 200 (specific services only)
    iifname "eth0.100" oifname "eth0.200" tcp dport { 80, 443 } accept

    # Block VLAN 200 -> VLAN 100 (except established)
    iifname "eth0.200" oifname "eth0.100" drop

    # Allow all VLANs to reach the internet
    iifname "eth0.100" oifname "eth0" accept
    iifname "eth0.200" oifname "eth0" accept
}
```

---

## 8. Bridge Networking for Containers

Linux bridges operate at Layer 2, connecting multiple network interfaces (physical or virtual) into a single broadcast domain. They are foundational for container and VM networking.

### Creating a Bridge

```shell
# Create a bridge device
sudo ip link add name br0 type bridge
sudo ip link set br0 up

# Add a physical interface to the bridge
sudo ip link set eth1 master br0

# Assign an IP to the bridge (the bridge becomes the gateway)
sudo ip addr add 10.0.10.1/24 dev br0

# Create veth pairs for containers
sudo ip link add veth-c1 type veth peer name veth-c1-br
sudo ip link set veth-c1-br master br0
sudo ip link set veth-c1-br up

# Move one end into a network namespace (simulating a container)
sudo ip netns add container1
sudo ip link set veth-c1 netns container1
sudo ip netns exec container1 ip addr add 10.0.10.2/24 dev veth-c1
sudo ip netns exec container1 ip link set veth-c1 up
sudo ip netns exec container1 ip route add default via 10.0.10.1
```

### Bridge with nftables Filtering

When using `nf_tables` for bridge-level filtering:

```nft
table bridge filter {
    chain forward {
        type filter hook forward priority filter; policy accept;

        # Block inter-container traffic on specific ports
        ether type ip ip daddr 10.0.10.0/24 tcp dport 22 drop

        # Rate limit ARP to prevent ARP storms
        ether type arp limit rate 10/second accept
        ether type arp drop
    }
}
```

### Bridge Firewall Considerations

By default, bridged traffic may bypass iptables/nftables. Ensure `br_netfilter` is loaded if you need L3 filtering on bridged traffic:

```shell
sudo modprobe br_netfilter
echo "br_netfilter" | sudo tee -a /etc/modules-load.d/bridge.conf

# Enable bridge-nf-call for iptables/nftables
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/99-bridge.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/99-bridge.conf
```

---

## 9. Traffic Shaping with tc

Linux Traffic Control (`tc`) manages queuing disciplines (qdiscs) on network interfaces to shape bandwidth, prioritize traffic, and enforce rate limits.

### Queuing Discipline Hierarchy

```
root qdisc
  └── class 1:1 (HTB root class, ceiling = link speed)
       ├── class 1:10 (high priority, rate 50mbit, ceil 100mbit)
       │     └── leaf qdisc: fq_codel
       ├── class 1:20 (normal priority, rate 30mbit, ceil 100mbit)
       │     └── leaf qdisc: fq_codel
       └── class 1:30 (bulk/low priority, rate 20mbit, ceil 100mbit)
             └── leaf qdisc: fq_codel
```

### HTB (Hierarchical Token Bucket) Example

```shell
# Remove existing qdiscs
sudo tc qdisc del dev eth0 root 2>/dev/null

# Add root HTB qdisc
sudo tc qdisc add dev eth0 root handle 1: htb default 20

# Root class (total bandwidth: 100mbit)
sudo tc class add dev eth0 parent 1: classid 1:1 htb rate 100mbit ceil 100mbit

# High priority class (guaranteed 50mbit, can burst to 100mbit)
sudo tc class add dev eth0 parent 1:1 classid 1:10 htb rate 50mbit ceil 100mbit prio 0
sudo tc qdisc add dev eth0 parent 1:10 handle 10: fq_codel

# Normal priority class (guaranteed 30mbit)
sudo tc class add dev eth0 parent 1:1 classid 1:20 htb rate 30mbit ceil 100mbit prio 1
sudo tc qdisc add dev eth0 parent 1:20 handle 20: fq_codel

# Low priority / bulk class (guaranteed 20mbit)
sudo tc class add dev eth0 parent 1:1 classid 1:30 htb rate 20mbit ceil 100mbit prio 2
sudo tc qdisc add dev eth0 parent 1:30 handle 30: fq_codel

# Classify traffic using filters
# SSH and DNS -> high priority
sudo tc filter add dev eth0 parent 1: protocol ip prio 1 u32 \
    match ip dport 22 0xffff flowid 1:10
sudo tc filter add dev eth0 parent 1: protocol ip prio 1 u32 \
    match ip dport 53 0xffff flowid 1:10

# HTTP/HTTPS -> normal priority
sudo tc filter add dev eth0 parent 1: protocol ip prio 2 u32 \
    match ip dport 80 0xffff flowid 1:20
sudo tc filter add dev eth0 parent 1: protocol ip prio 2 u32 \
    match ip dport 443 0xffff flowid 1:20

# Everything else -> default (1:20, set in root qdisc)

# Verify configuration
tc -s qdisc show dev eth0
tc -s class show dev eth0
tc filter show dev eth0
```

### Simple Rate Limiting with TBF

For basic rate limiting without complex classification:

```shell
# Limit eth0 to 10mbit with 32kbit burst, 50ms latency
sudo tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 50ms
```

### Ingress Policing

tc can only shape (delay) egress traffic. For ingress, use policing (drop excess):

```shell
# Add ingress qdisc
sudo tc qdisc add dev eth0 handle ffff: ingress

# Police incoming traffic to 50mbit, drop excess
sudo tc filter add dev eth0 parent ffff: protocol ip u32 \
    match u32 0 0 police rate 50mbit burst 128k drop flowid :1
```

---

## 10. Connection Tracking and Stateful Rules

Connection tracking (conntrack) is the kernel subsystem that tracks the state of network connections. It enables stateful firewalling where rules can match based on whether a packet belongs to a new, established, or related connection.

### Connection States

| State           | Description                                                    |
|-----------------|----------------------------------------------------------------|
| `new`           | First packet of a connection not yet seen by conntrack         |
| `established`   | Packet belongs to a connection that has seen packets in both directions |
| `related`       | Packet starts a new connection related to an existing one (e.g., FTP data) |
| `invalid`       | Packet cannot be identified or does not belong to any known connection |
| `untracked`     | Packet explicitly excluded from connection tracking            |

### Stateful vs Stateless Rules

**Stateful** (recommended): Accept established/related early, then only write rules for new connections.

```nft
chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    ct state invalid drop
    tcp dport 22 ct state new accept
}
```

**Stateless** (rare, for very high-throughput scenarios): No connection tracking. Every packet must be matched individually, including return traffic.

```nft
# Bypass conntrack for high-volume UDP traffic
table ip raw {
    chain prerouting {
        type filter hook prerouting priority raw; policy accept;
        udp dport 51820 notrack   # WireGuard
    }
    chain output {
        type filter hook output priority raw; policy accept;
        udp sport 51820 notrack
    }
}
```

### Conntrack Tuning

```shell
# View current connections
sudo conntrack -L
sudo conntrack -C   # count

# View conntrack table size and usage
cat /proc/sys/net/netfilter/nf_conntrack_max
cat /proc/sys/net/netfilter/nf_conntrack_count

# Increase conntrack table for busy gateways
echo 262144 | sudo tee /proc/sys/net/netfilter/nf_conntrack_max
echo "net.netfilter.nf_conntrack_max = 262144" | sudo tee -a /etc/sysctl.d/99-conntrack.conf

# Tune timeout values for high-connection servers
echo 300 | sudo tee /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
echo "net.netfilter.nf_conntrack_tcp_timeout_established = 300" | sudo tee -a /etc/sysctl.d/99-conntrack.conf

# Monitor conntrack events in real time
sudo conntrack -E
```

### Conntrack Helpers

For protocols that embed IP addresses in the payload (FTP, SIP, H.323), conntrack helpers parse the payload to create expectation entries for related connections.

```shell
# Load FTP helper
sudo modprobe nf_conntrack_ftp

# In nftables, explicitly assign helpers
table inet firewall {
    ct helper ftp-standard {
        type "ftp" protocol tcp
    }

    chain input {
        type filter hook input priority 0; policy drop;
        ct state established,related accept
        tcp dport 21 ct state new accept
        tcp dport 21 ct helper set "ftp-standard"
    }
}
```

---

## 11. Rate Limiting and Geo-Blocking

### Rate Limiting with nftables

```nft
chain input {
    type filter hook input priority 0; policy drop;

    ct state established,related accept

    # Rate limit new SSH connections: 3 per minute per source IP
    tcp dport 22 ct state new meter ssh_meter { ip saddr limit rate 3/minute } accept
    tcp dport 22 ct state new drop

    # Rate limit HTTP connections: 30 per second per source IP
    tcp dport { 80, 443 } ct state new meter http_meter { ip saddr limit rate 30/second } accept
    tcp dport { 80, 443 } ct state new drop

    # Global ICMP rate limit
    ip protocol icmp limit rate 10/second accept
    ip protocol icmp drop
}
```

### Rate Limiting with iptables

```shell
# Limit SSH to 3 new connections per minute per source
sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW \
    -m hashlimit --hashlimit-upto 3/min --hashlimit-burst 3 \
    --hashlimit-mode srcip --hashlimit-name ssh_limit -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j DROP
```

### Geo-Blocking

Geo-blocking restricts traffic based on the geographic origin of IP addresses. Use regularly updated IP-to-country databases.

**Using nftables sets with ipset-country lists:**

```shell
# Download country IP ranges (example: block traffic from specific countries)
# Use services like ipdeny.com or db-ip.com for aggregated CIDR lists
wget -O /tmp/cn.zone https://www.ipdeny.com/ipblocks/data/aggregated/cn-aggregated.zone

# Convert to nftables set elements
awk '{printf "        %s,\n", $0}' /tmp/cn.zone > /tmp/cn-nft-elements.txt

# Create an nftables set and load it
sudo nft add set inet firewall geo_cn '{ type ipv4_addr; flags interval; auto-merge; }'
# Load elements from file using a script or nft -f
```

**Using xt_geoip with iptables:**

```shell
# Install xtables-addons for GeoIP support
sudo apt install xtables-addons-common libtext-csv-xs-perl

# Download and build GeoIP database
sudo /usr/lib/xtables-addons/xt_geoip_dl
sudo /usr/lib/xtables-addons/xt_geoip_build -s -D /usr/share/xt_geoip

# Block traffic from specific countries
sudo iptables -A INPUT -m geoip --src-cc CN,RU -j DROP
```

---

## 12. Logging and Diagnostics

### nftables Logging

```nft
chain input {
    type filter hook input priority 0; policy drop;

    # Log dropped packets with a prefix, rate-limited to avoid log flooding
    log prefix "nft-drop: " flags all limit rate 5/minute counter drop
}

# Dedicated log chain for reuse
chain log_and_drop {
    log prefix "nft-blocked: " flags all counter
    drop
}

chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    tcp dport 22 accept
    jump log_and_drop
}
```

### iptables Logging

```shell
# Log dropped INPUT packets
sudo iptables -A INPUT -j LOG --log-prefix "iptables-drop: " --log-level 4 --log-tcp-options
sudo iptables -A INPUT -j DROP

# Rate-limit logs to prevent flooding
sudo iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables-drop: "
sudo iptables -A INPUT -j DROP
```

### Rsyslog Filtering

Direct firewall logs to a dedicated file:

```
# /etc/rsyslog.d/10-firewall.conf
:msg, contains, "nft-drop:" /var/log/firewall.log
:msg, contains, "iptables-drop:" /var/log/firewall.log
& stop
```

### Diagnostic Commands

```shell
# Watch conntrack events
sudo conntrack -E

# Packet counters per chain/rule
sudo nft list ruleset -a   # with handles and counters

# Trace packet path through nftables (powerful debugging)
sudo nft add rule inet firewall input meta nftrace set 1
sudo nft monitor trace

# tcpdump for packet capture
sudo tcpdump -i eth0 -nn port 22
sudo tcpdump -i any -nn -w /tmp/capture.pcap 'host 10.0.1.10 and port 443'

# ss for socket/connection inspection
ss -tulnp      # listening TCP/UDP sockets
ss -tn state established | wc -l   # count established connections
```

---

## 13. fail2ban Integration

fail2ban monitors log files for patterns indicating malicious activity (brute-force attacks, scanners) and dynamically adds firewall rules to block offending IPs.

### Installation and Configuration

```shell
# Install fail2ban
sudo apt install fail2ban

# Create local config (never edit jail.conf directly)
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
```

### Jail Configuration

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = nftables-multiport
banaction_allports = nftables-allports

# Use nftables backend (modern systems)
# Available actions: nftables-multiport, nftables-allports, iptables-multiport

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
backend  = systemd
maxretry = 3
bantime  = 24h

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
findtime = 1m
bantime  = 10m

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
```

### Custom fail2ban Filters

```ini
# /etc/fail2ban/filter.d/nginx-custom.conf
[Definition]
failregex = ^<HOST> .* "(GET|POST) .*(wp-login|xmlrpc|\.env|\.git).*" (404|403)
ignoreregex =
```

### fail2ban Management

```shell
# Check status of all jails
sudo fail2ban-client status

# Check a specific jail
sudo fail2ban-client status sshd

# Manually ban/unban an IP
sudo fail2ban-client set sshd banip 198.51.100.5
sudo fail2ban-client set sshd unbanip 198.51.100.5

# View the nftables set populated by fail2ban
sudo nft list set inet f2b-table addr-set-sshd

# Test a filter against a log file
sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
```

### fail2ban with nftables Backend

When using the `nftables-multiport` action, fail2ban creates its own table and set in nftables. The set is dynamically populated with banned IPs. Ensure your main nftables ruleset does not flush the fail2ban table:

```nft
# In your main nftables.conf, use specific flushes instead of "flush ruleset"
flush table inet firewall
# Do NOT use: flush ruleset (this would wipe fail2ban rules)
```

---

## 14. Best Practices

### General Firewall Design

1. **Default deny policy**: Always set the default chain policy to `drop` for input and forward chains. Explicitly allow only what is needed.
2. **Accept established/related first**: The `ct state established,related accept` rule should be the very first rule in every filter chain. This rule handles the vast majority of traffic and avoids unnecessary evaluation of subsequent rules.
3. **Drop invalid early**: Place `ct state invalid drop` immediately after the established/related rule to discard malformed or untrackable packets.
4. **Principle of least privilege**: Open only the ports that are required. Restrict source IPs where possible (e.g., SSH only from management subnets).
5. **Use nftables for new deployments**: nftables is the modern replacement with better performance, atomic ruleset updates, and a cleaner syntax. Avoid starting new projects with iptables.

### Rule Organization

6. **Use named sets for large IP lists**: Named sets with interval flags are far more efficient than long chains of individual IP rules. nftables sets use hash tables or interval trees internally.
7. **Group related rules**: Use jump chains to organize rules logically (e.g., a dedicated `ssh_chain`, `http_chain`). This improves readability and performance.
8. **Use counters for auditing**: Add `counter` to critical rules to track how often they match. This data is invaluable for troubleshooting and capacity planning.
9. **Comment your rules**: Use the `comment` keyword in nftables to annotate rules with their purpose.

### Operational

10. **Atomic ruleset loading**: Always use `nft -f` to load complete rulesets atomically. This avoids transient states where partial rulesets are active.
11. **Test before applying**: On remote systems, use a deadman switch (`at now + 5 minutes` to restore the old ruleset) before applying new firewall rules. A mistake could lock you out permanently.
12. **Version control firewall configs**: Store `/etc/nftables.conf` in version control. Review changes via pull requests.
13. **Separate NAT from filtering**: Keep NAT rules in a dedicated `nat` table and filtering rules in a `filter` table. Do not mix concerns.
14. **Tune conntrack for load**: On busy gateways, increase `nf_conntrack_max` and reduce timeouts for protocols you do not need long-lived tracking for.
15. **Log judiciously**: Log dropped packets for diagnostics but always rate-limit log rules to prevent log flooding from DoS attacks.

---

## 15. Anti-Patterns

1. **Using `flush ruleset` with fail2ban**: Running `flush ruleset` in your nftables configuration file removes all tables, including those managed by fail2ban. Use `flush table inet firewall` to flush only your own table.

2. **Default ACCEPT on INPUT/FORWARD**: Leaving the default policy as `accept` and relying solely on `drop` rules is a blocklist approach. Any new service that binds to a port is immediately exposed. Always default to `drop`.

3. **Masquerade on static-IP gateways**: Using `masquerade` instead of `snat` when the external IP is static wastes CPU on every packet by querying the interface IP. Use `snat to <IP>` for static addresses.

4. **Stateless rules for TCP services**: Writing individual rules for return traffic (`--sport` matching) instead of using connection tracking is fragile, error-prone, and provides weaker security. Always use `ct state established,related`.

5. **Overly broad FORWARD rules**: Rules like `iifname "eth0" accept` in the forward chain allow all traffic to be routed through the machine. Be explicit about source, destination, and protocol.

6. **Not enabling IP forwarding**: Adding NAT and FORWARD rules without setting `net.ipv4.ip_forward = 1` results in silently dropped routed traffic with no clear error.

7. **Ignoring IPv6**: Configuring firewall rules only for IPv4 while IPv6 is enabled on interfaces leaves an unfiltered attack surface. Use the `inet` family in nftables to handle both protocols simultaneously.

8. **Hardcoding IPs instead of using sets**: Scattering individual IP addresses across dozens of rules makes maintenance difficult. Use named sets and update sets programmatically.

9. **No rate limiting on public-facing services**: Allowing unlimited connection rates to SSH, HTTP, or DNS enables brute-force and DoS attacks. Always apply per-source rate limits on new connections.

10. **Mixing iptables and nftables**: Running both frameworks simultaneously causes unpredictable behavior because they share the same kernel hooks. Choose one and migrate fully.

11. **Editing `/etc/fail2ban/jail.conf` directly**: This file is overwritten on package updates. Always create `/etc/fail2ban/jail.local` for customizations.

12. **Traffic shaping without fq_codel leaf qdiscs**: Using HTB classes without a fair queuing leaf qdisc (like `fq_codel`) leads to buffer bloat within each class. Always attach `fq_codel` as the leaf qdisc.

---

## 16. Sources & References

- [nftables Wiki - Official Documentation](https://wiki.nftables.org/wiki-nftables/index.php/Main_Page) -- Comprehensive reference for nftables syntax, examples, and migration guides from iptables.
- [Netfilter Project - nftables](https://netfilter.org/projects/nftables/) -- Official project page with release notes, downloads, and architecture documentation.
- [ArchWiki - nftables](https://wiki.archlinux.org/title/Nftables) -- Practical configuration guide with examples for desktop and server deployments.
- [ArchWiki - iptables](https://wiki.archlinux.org/title/Iptables) -- Legacy iptables reference with chain flow diagrams and common recipes.
- [Linux Advanced Routing & Traffic Control HOWTO](https://lartc.org/howto/) -- Definitive guide for policy routing, traffic shaping with tc, and advanced networking.
- [fail2ban Official Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page) -- Configuration reference for jails, filters, actions, and backend integration.
- [Red Hat - Getting Started with nftables](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_firewalls_and_packet_filters/getting-started-with-nftables_firewall-packet-filters) -- Enterprise-focused nftables guide for RHEL 9.
- [Debian Wiki - nftables](https://wiki.debian.org/nftables) -- Debian-specific setup and migration instructions from iptables to nftables.
- [tc(8) man page - Linux Traffic Control](https://man7.org/linux/man-pages/man8/tc.8.html) -- Official man page for the tc command with qdisc, class, and filter documentation.
- [Cloudflare Blog - How We Built a DDoS Mitigation Pipeline](https://blog.cloudflare.com/how-we-built-spectrum/) -- Real-world nftables and XDP usage at scale for traffic management.
