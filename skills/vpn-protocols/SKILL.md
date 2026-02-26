---
name: vpn-protocols
description: VPN protocols and configuration -- WireGuard, OpenVPN, IPsec/IKEv2 setup, site-to-site tunnels, road warrior clients, and mesh VPN with Tailscale/Nebula/ZeroTier
---

# VPN Protocols & Configuration -- Network Engineer Patterns

Production-ready patterns for deploying, configuring, and managing VPN infrastructure. Covers WireGuard as the primary protocol alongside OpenVPN and IPsec/IKEv2, with guidance on protocol selection, site-to-site tunnels, roaming client setups, mesh VPN overlays, and operational hardening.

## Table of Contents
1. [Protocol Comparison Matrix](#1-protocol-comparison-matrix)
2. [WireGuard Setup & Key Management](#2-wireguard-setup--key-management)
3. [WireGuard Peer Configuration & AllowedIPs Routing](#3-wireguard-peer-configuration--allowedips-routing)
4. [WireGuard PostUp/PostDown & Advanced Scripting](#4-wireguard-postuppostdown--advanced-scripting)
5. [OpenVPN Server & Client with TLS](#5-openvpn-server--client-with-tls)
6. [Certificate Management with easy-rsa](#6-certificate-management-with-easy-rsa)
7. [IPsec/IKEv2 with strongSwan](#7-ipsecikev2-with-strongswan)
8. [Site-to-Site Tunnels](#8-site-to-site-tunnels)
9. [Road Warrior (Roaming Client) Setups](#9-road-warrior-roaming-client-setups)
10. [Mesh VPN -- Tailscale, Nebula, ZeroTier](#10-mesh-vpn----tailscale-nebula-zerotier)
11. [Split Tunneling & DNS Leak Prevention](#11-split-tunneling--dns-leak-prevention)
12. [Kill Switches & Fail-Closed Design](#12-kill-switches--fail-closed-design)
13. [MTU Optimization & Performance Tuning](#13-mtu-optimization--performance-tuning)
14. [Multi-Hop VPN](#14-multi-hop-vpn)
15. [Best Practices](#15-best-practices)
16. [Anti-Patterns](#16-anti-patterns)
17. [Sources & References](#17-sources--references)

---

## 1. Protocol Comparison Matrix

Use this matrix when selecting a VPN protocol for a given deployment scenario.

| Criteria | WireGuard | OpenVPN | IPsec/IKEv2 |
|---|---|---|---|
| **Codebase size** | ~4,000 lines | ~100,000+ lines | ~400,000+ lines (strongSwan) |
| **Encryption** | ChaCha20-Poly1305, Curve25519, BLAKE2s | OpenSSL/mbed TLS (configurable) | Configurable (AES-GCM, ChaCha20) |
| **Key exchange** | Noise protocol (1-RTT) | TLS 1.2/1.3 handshake | IKE_SA_INIT + IKE_AUTH (2-RTT) |
| **Transport** | UDP only | UDP or TCP | UDP (ports 500, 4500) or TCP encap |
| **NAT traversal** | Built-in (UDP, stateless) | Built-in (UDP) or TCP fallback | NAT-T (UDP 4500 encapsulation) |
| **Audit surface** | Small -- formally verified (Tamarin) | Large -- many cipher suites | Large -- complex state machine |
| **Performance** | Kernel-space, ~900 Mbps+ on modern HW | User-space, ~300-600 Mbps typical | Kernel-space (XFRM), ~700 Mbps+ |
| **Roaming** | Excellent (endpoint updates on handshake) | Poor (reconnect required) | Good (MOBIKE extension) |
| **OS support** | Linux (kernel), macOS, Windows, iOS, Android | All major platforms | All major platforms (native on iOS/macOS/Windows) |
| **Stealth/censorship** | Low (fixed UDP, detectable) | High (TCP 443 + obfs4) | Medium (IKEv2 over TCP) |
| **PKI required** | No (static public keys) | Yes (X.509 certificates) | Yes (X.509 or PSK) |

### Protocol Selection Decision Tree

- **Default choice for new deployments**: WireGuard -- smallest attack surface, best performance, simplest config.
- **Need TCP fallback or censorship resistance**: OpenVPN with TCP 443 + obfsproxy/obfs4.
- **Corporate environment with native OS clients**: IPsec/IKEv2 -- built into Windows, macOS, iOS without extra software.
- **Mesh topology among many nodes**: Tailscale (WireGuard-based), Nebula, or ZeroTier.
- **Legacy systems or strict compliance**: OpenVPN with FIPS-validated OpenSSL or IPsec with FIPS-certified modules.

---

## 2. WireGuard Setup & Key Management

### Key Generation

WireGuard uses Curve25519 keypairs. Keys are 32-byte base64-encoded strings.

```bash
# Generate a private key (restrict permissions immediately)
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key

# Generate a preshared key for additional symmetric encryption layer (quantum resistance)
wg genpsk > /etc/wireguard/psk_peer1.key
chmod 600 /etc/wireguard/psk_peer1.key

# Batch key generation for multiple peers
for i in $(seq 1 10); do
  mkdir -p /etc/wireguard/peers/peer${i}
  wg genkey | tee /etc/wireguard/peers/peer${i}/private.key | wg pubkey > /etc/wireguard/peers/peer${i}/public.key
  wg genpsk > /etc/wireguard/peers/peer${i}/psk.key
  chmod 600 /etc/wireguard/peers/peer${i}/private.key /etc/wireguard/peers/peer${i}/psk.key
done
```

### Key Rotation Strategy

WireGuard does not have built-in key rotation. Implement rotation externally:

- Schedule key rotation every 90 days (or per your policy).
- Generate new keypair, update the peer configuration on both sides, then restart the interface.
- Use configuration management (Ansible, Puppet) to push updated keys atomically.
- The preshared key (PSK) adds a symmetric layer on top of Curve25519 -- rotate it alongside the keypair.

### Kernel Module vs Userspace

- **Linux 5.6+**: WireGuard is in-tree as a kernel module. Use it.
- **Older Linux kernels**: Install via DKMS (`wireguard-dkms`) or use `wireguard-go` (userspace, slower).
- **macOS/Windows**: Always userspace via the official apps.
- **Containers**: The host kernel must have the module loaded; containers share it.

---

## 3. WireGuard Peer Configuration & AllowedIPs Routing

### Server Interface Configuration

```ini
# /etc/wireguard/wg0.conf -- Server
[Interface]
Address = 10.0.0.1/24, fd00:vpn::1/64
ListenPort = 51820
PrivateKey = <server_private_key>
DNS = 10.0.0.1
# Save config state on shutdown so dynamically added peers persist
SaveConfig = false

# Peer: Laptop (road warrior)
[Peer]
PublicKey = <peer1_public_key>
PresharedKey = <preshared_key>
AllowedIPs = 10.0.0.2/32, fd00:vpn::2/128
# Optional: persistent keepalive for NAT traversal (every 25 seconds)
PersistentKeepalive = 25

# Peer: Office gateway (site-to-site -- route the remote subnet)
[Peer]
PublicKey = <peer2_public_key>
PresharedKey = <preshared_key2>
AllowedIPs = 10.0.0.3/32, 192.168.10.0/24
Endpoint = office.example.com:51820
PersistentKeepalive = 25
```

### AllowedIPs Explained

`AllowedIPs` serves a dual purpose in WireGuard:

1. **Outbound routing**: Packets destined for these CIDRs are sent to this peer (acts as a routing table).
2. **Inbound filtering**: Packets arriving from this peer are only accepted if their source IP is in `AllowedIPs` (acts as an ACL).

Key rules:
- Each IP address can only appear in ONE peer's `AllowedIPs` (most-specific match wins).
- `0.0.0.0/0, ::/0` = full tunnel -- all traffic routes through this peer.
- `10.0.0.2/32` = only that single host address -- typical for a road warrior.
- `192.168.10.0/24` = route an entire subnet through this peer -- typical for site-to-site.

### Dynamic Peer Management

```bash
# Add a peer at runtime (no restart needed)
wg set wg0 peer <public_key> \
  preshared-key /etc/wireguard/peers/peer1/psk.key \
  allowed-ips 10.0.0.5/32 \
  persistent-keepalive 25

# Remove a peer at runtime
wg set wg0 peer <public_key> remove

# Show current interface status
wg show wg0

# Show transfer stats for all peers
wg show wg0 transfer

# Show endpoints (useful for debugging NAT)
wg show wg0 endpoints
```

---

## 4. WireGuard PostUp/PostDown & Advanced Scripting

### NAT Masquerade for Internet Gateway

```ini
# /etc/wireguard/wg0.conf -- Server acting as internet gateway
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <server_private_key>

# Enable IP forwarding and set up NAT on interface up
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = sysctl -w net.ipv6.conf.all.forwarding=1
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
PostUp = ip6tables -t nat -A POSTROUTING -s fd00:vpn::/64 -o eth0 -j MASQUERADE
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostUp = iptables -A FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Tear down NAT rules on interface down
PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
PostDown = ip6tables -t nat -D POSTROUTING -s fd00:vpn::/64 -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

### DNS Resolution on the Server

When the server also provides DNS to VPN clients, use PostUp to start an isolated resolver:

```ini
PostUp = systemctl start unbound
PostDown = systemctl stop unbound
```

### External Script Pattern

For complex logic, call an external script instead of inlining:

```ini
PostUp = /etc/wireguard/scripts/postup.sh %i
PostDown = /etc/wireguard/scripts/postdown.sh %i
```

Where `%i` expands to the interface name (e.g., `wg0`). The script can handle logging, dynamic firewall rules, notifications, or API calls.

---

## 5. OpenVPN Server & Client with TLS

### Server Configuration

```ini
# /etc/openvpn/server/server.conf
port 1194
proto udp
dev tun

ca /etc/openvpn/server/pki/ca.crt
cert /etc/openvpn/server/pki/issued/server.crt
key /etc/openvpn/server/pki/private/server.key
dh /etc/openvpn/server/pki/dh.pem
tls-crypt /etc/openvpn/server/pki/tc.key

# Network
server 10.8.0.0 255.255.255.0
topology subnet
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 9.9.9.9"

# Security hardening
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
tls-version-min 1.2
tls-cipher TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384:TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
auth SHA256

# Performance
sndbuf 524288
rcvbuf 524288
push "sndbuf 524288"
push "rcvbuf 524288"
txqueuelen 1000

# Keepalive and session
keepalive 10 60
persist-key
persist-tun
reneg-sec 3600

# Logging
status /var/log/openvpn/status.log 30
log-append /var/log/openvpn/server.log
verb 3
mute 20

# Process
user nobody
group nogroup
```

### Client Configuration

```ini
# client.ovpn
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun

# Embedded certificates (single-file profile)
<ca>
-----BEGIN CERTIFICATE-----
... CA certificate ...
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
... Client certificate ...
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
... Client private key ...
-----END PRIVATE KEY-----
</key>

<tls-crypt>
-----BEGIN OpenVPN Static key V1-----
... tls-crypt key ...
-----END OpenVPN Static key V1-----
</tls-crypt>

cipher AES-256-GCM
auth SHA256
tls-version-min 1.2
verb 3
```

### tls-crypt vs tls-auth

- **tls-auth**: HMAC signature on TLS control channel packets. Prevents unauthorized handshake attempts.
- **tls-crypt**: Encrypts AND authenticates the entire TLS control channel. Hides the OpenVPN handshake from DPI. Preferred for all new deployments.

---

## 6. Certificate Management with easy-rsa

### Initializing the PKI

```bash
# Install easy-rsa
apt install easy-rsa  # Debian/Ubuntu
# or
dnf install easy-rsa  # RHEL/Fedora

# Initialize PKI directory
cd /etc/openvpn/server
make-cadir pki-management
cd pki-management

# Edit vars for your organization
cat > vars << 'VARS'
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "San Francisco"
set_var EASYRSA_REQ_ORG        "Example Corp"
set_var EASYRSA_REQ_EMAIL      "vpn-admin@example.com"
set_var EASYRSA_REQ_OU         "Network Engineering"
set_var EASYRSA_KEY_SIZE       4096
set_var EASYRSA_ALGO           ec
set_var EASYRSA_CURVE          secp384r1
set_var EASYRSA_CA_EXPIRE      3650
set_var EASYRSA_CERT_EXPIRE    825
set_var EASYRSA_CRL_DAYS       180
set_var EASYRSA_DIGEST         sha384
VARS

# Build CA (offline CA host recommended)
./easyrsa init-pki
./easyrsa build-ca nopass  # Use a passphrase in production

# Generate server certificate
./easyrsa gen-req server nopass
./easyrsa sign-req server server

# Generate DH parameters
./easyrsa gen-dh

# Generate tls-crypt key
openvpn --genkey secret /etc/openvpn/server/pki/tc.key

# Generate client certificate
./easyrsa gen-req client1 nopass
./easyrsa sign-req client client1
```

### Certificate Revocation

```bash
# Revoke a client certificate
./easyrsa revoke client1

# Generate updated CRL
./easyrsa gen-crl

# Copy CRL to OpenVPN server directory
cp pki/crl.pem /etc/openvpn/server/

# Add CRL checking to server config
# crl-verify /etc/openvpn/server/crl.pem
```

### Automated Certificate Renewal

Set up a cron job or systemd timer to monitor expiring certificates:

```bash
#!/usr/bin/env bash
# /etc/openvpn/scripts/check-cert-expiry.sh
WARN_DAYS=30
CERT_DIR="/etc/openvpn/server/pki-management/pki/issued"

for cert in "${CERT_DIR}"/*.crt; do
  expiry=$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)
  expiry_epoch=$(date -d "$expiry" +%s)
  now_epoch=$(date +%s)
  days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

  if [ "$days_left" -lt "$WARN_DAYS" ]; then
    echo "WARNING: $(basename "$cert") expires in ${days_left} days"
    # Send alert via your notification system
  fi
done
```

---

## 7. IPsec/IKEv2 with strongSwan

### Installation

```bash
# Debian/Ubuntu
apt install strongswan strongswan-pki libcharon-extra-plugins

# RHEL/Fedora
dnf install strongswan
```

### Certificate-Based Configuration

```ini
# /etc/ipsec.conf
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2"
    uniqueids=yes

conn %default
    keyexchange=ikev2
    ike=aes256gcm16-sha384-ecp384!
    esp=aes256gcm16-ecp384!
    dpdaction=restart
    dpddelay=30s
    dpdtimeout=120s
    rekey=yes
    reauth=no
    fragmentation=yes

conn roadwarrior
    left=%defaultroute
    leftid=@vpn.example.com
    leftcert=server.crt
    leftsubnet=0.0.0.0/0
    leftsendcert=always
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=1.1.1.1,9.9.9.9
    eap_identity=%identity
    auto=add
```

### Secrets File

```ini
# /etc/ipsec.secrets
: RSA server.key

user1 : EAP "strongpassword123"
user2 : EAP "anotherpassword456"
```

### strongSwan Certificate Generation

```bash
# Generate CA key and certificate
ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/ca.key.pem
ipsec pki --self --ca --lifetime 3650 \
  --in /etc/ipsec.d/private/ca.key.pem \
  --type rsa --dn "CN=VPN Root CA" \
  --outform pem > /etc/ipsec.d/cacerts/ca.cert.pem

# Generate server key and certificate
ipsec pki --gen --type rsa --size 4096 --outform pem > /etc/ipsec.d/private/server.key.pem
ipsec pki --pub --in /etc/ipsec.d/private/server.key.pem --type rsa |
  ipsec pki --issue --lifetime 825 \
    --cacert /etc/ipsec.d/cacerts/ca.cert.pem \
    --cakey /etc/ipsec.d/private/ca.key.pem \
    --dn "CN=vpn.example.com" \
    --san "vpn.example.com" \
    --san "203.0.113.10" \
    --flag serverAuth --flag ikeIntermediate \
    --outform pem > /etc/ipsec.d/certs/server.cert.pem

# Set permissions
chmod 600 /etc/ipsec.d/private/*.pem
```

### MOBIKE for Roaming

IKEv2 supports MOBIKE (RFC 4555), allowing clients to change IP addresses without re-establishing the SA. Ensure both sides support it:

```ini
# In the conn section
mobike=yes
```

This is particularly important for mobile clients switching between Wi-Fi and cellular.

---

## 8. Site-to-Site Tunnels

### WireGuard Site-to-Site

Two offices connecting their LANs through WireGuard:

**Office A (10.1.0.0/24) -- Gateway: 203.0.113.10**

```ini
# /etc/wireguard/wg0.conf on Office A gateway
[Interface]
Address = 10.255.0.1/30
ListenPort = 51820
PrivateKey = <officeA_private_key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT

[Peer]
PublicKey = <officeB_public_key>
PresharedKey = <psk>
Endpoint = 198.51.100.20:51820
AllowedIPs = 10.255.0.2/32, 10.2.0.0/24
PersistentKeepalive = 25
```

**Office B (10.2.0.0/24) -- Gateway: 198.51.100.20**

```ini
# /etc/wireguard/wg0.conf on Office B gateway
[Interface]
Address = 10.255.0.2/30
ListenPort = 51820
PrivateKey = <officeB_private_key>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT

[Peer]
PublicKey = <officeA_public_key>
PresharedKey = <psk>
Endpoint = 203.0.113.10:51820
AllowedIPs = 10.255.0.1/32, 10.1.0.0/24
PersistentKeepalive = 25
```

Both gateways need IP forwarding enabled and LAN hosts need routes pointing to the gateway for the remote subnet:

```bash
# On LAN hosts in Office A (or set on the default gateway/router)
ip route add 10.2.0.0/24 via 10.1.0.1

# On LAN hosts in Office B
ip route add 10.1.0.0/24 via 10.2.0.1
```

### IPsec Site-to-Site

```ini
# /etc/ipsec.conf -- Office A
conn site-to-site
    keyexchange=ikev2
    left=203.0.113.10
    leftsubnet=10.1.0.0/24
    leftcert=officeA.crt
    leftid=@officeA.example.com
    right=198.51.100.20
    rightsubnet=10.2.0.0/24
    rightid=@officeB.example.com
    auto=start
```

---

## 9. Road Warrior (Roaming Client) Setups

### Design Considerations

Road warrior setups serve individual devices (laptops, phones) that connect from untrusted networks. Key concerns:

- **NAT traversal**: The client is almost always behind NAT. WireGuard handles this natively. IPsec needs NAT-T. OpenVPN works well over UDP with NAT.
- **Roaming**: Client IP changes when switching networks. WireGuard and IKEv2 (MOBIKE) handle this gracefully.
- **DNS**: Push DNS servers to prevent leaks. Consider running a local resolver on the VPN server.
- **Full tunnel vs split tunnel**: Full tunnel (`0.0.0.0/0`) for security-focused setups; split tunnel for performance.
- **Automatic reconnection**: Use PersistentKeepalive (WireGuard), keepalive (OpenVPN), or DPD (IPsec).

### WireGuard Road Warrior Client Config

```ini
# /etc/wireguard/wg0.conf -- Client (full tunnel)
[Interface]
Address = 10.0.0.2/32, fd00:vpn::2/128
PrivateKey = <client_private_key>
DNS = 10.0.0.1

[Peer]
PublicKey = <server_public_key>
PresharedKey = <psk>
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### IKEv2 Road Warrior for Native OS Clients

IKEv2 is built into Windows 10/11, macOS, and iOS. Deploy using:

1. Distribute the CA certificate to clients (MDM for managed devices, manual install otherwise).
2. Configure the VPN connection using the native OS settings or a configuration profile.
3. Use EAP-MSCHAPv2 or certificate-based authentication.

For macOS/iOS, deploy a `.mobileconfig` profile:

```xml
<!-- Simplified mobileconfig snippet for IKEv2 -->
<dict>
  <key>VPNType</key>
  <string>IKEv2</string>
  <key>RemoteAddress</key>
  <string>vpn.example.com</string>
  <key>LocalIdentifier</key>
  <string>client@example.com</string>
  <key>RemoteIdentifier</key>
  <string>vpn.example.com</string>
  <key>AuthenticationMethod</key>
  <string>Certificate</string>
  <key>IKESecurityAssociationParameters</key>
  <dict>
    <key>EncryptionAlgorithm</key>
    <string>AES-256-GCM</string>
    <key>IntegrityAlgorithm</key>
    <string>SHA2-384</string>
    <key>DiffieHellmanGroup</key>
    <integer>20</integer>
  </dict>
</dict>
```

---

## 10. Mesh VPN -- Tailscale, Nebula, ZeroTier

### Tailscale

Tailscale is a managed WireGuard mesh that uses a coordination server for key exchange and NAT traversal (DERP relay servers).

**Strengths**: Zero-config mesh, SSO integration, ACL policies, MagicDNS, exit nodes.
**Weakness**: Depends on Tailscale coordination server (or self-host Headscale).

```bash
# Install and authenticate
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey=tskey-auth-xxxxx --advertise-routes=10.1.0.0/24 --accept-dns=true

# Advertise as an exit node (internet gateway for other nodes)
tailscale up --advertise-exit-node

# Use a specific exit node
tailscale up --exit-node=<exit-node-ip>

# Check status
tailscale status
tailscale netcheck  # NAT type, DERP latency
```

### Headscale (Self-Hosted Tailscale Control Plane)

For organizations that require full control over the coordination server:

```bash
# Deploy Headscale
docker compose up -d headscale

# Create a user/namespace
headscale users create engineering

# Create a pre-auth key
headscale preauthkeys create --user engineering --reusable --expiration 24h

# Register a node
tailscale up --login-server=https://headscale.example.com --authkey=<key>
```

### Nebula

Nebula (by Slack/Defined Networking) creates an encrypted overlay mesh using a lighthouse model for peer discovery.

**Strengths**: No central data plane, certificate-based identity, firewall rules in config, works well at scale.
**Weakness**: Requires managing your own CA and lighthouse infrastructure.

Key concepts:
- **Lighthouse**: A well-known node that helps peers find each other (similar to STUN/TURN). Not a relay.
- **Certificate authority**: Nebula has its own CA that signs host certificates with embedded IP and group information.
- **Groups**: Defined in the certificate, used for firewall rules.

```bash
# Generate Nebula CA
nebula-cert ca -name "Example Corp" -duration 8760h

# Sign a host certificate
nebula-cert sign -name "web-server" -ip "10.42.0.1/24" -groups "servers,web"
nebula-cert sign -name "lighthouse" -ip "10.42.0.100/24" -groups "lighthouse"
```

### ZeroTier

ZeroTier creates a virtual L2 Ethernet network across the internet.

**Strengths**: True L2 networking (broadcast, multicast), self-hosted controller available, simple setup.
**Weakness**: L2 overhead, less granular routing control than L3 solutions.

```bash
# Install and join a network
curl -s https://install.zerotier.com | bash
zerotier-cli join <network-id>

# Authorize the node (via web UI or API)
curl -X POST "https://api.zerotier.com/api/v1/network/<network-id>/member/<node-id>" \
  -H "Authorization: token <api-token>" \
  -d '{"config": {"authorized": true}}'

# Check peers
zerotier-cli peers
zerotier-cli listnetworks
```

### Mesh VPN Comparison

| Feature | Tailscale | Nebula | ZeroTier |
|---|---|---|---|
| **Underlying protocol** | WireGuard | Custom (Noise) | Custom (ChaCha20) |
| **Network layer** | L3 | L3 | L2 |
| **NAT traversal** | DERP relays + direct | Lighthouse + UDP hole punch | Root servers + relay |
| **Self-hosted** | Headscale | Always | Controller API |
| **Identity** | SSO/OIDC | Certificate groups | Network + node ID |
| **Scale** | 100+ nodes | 10,000+ nodes | 10,000+ nodes |

---

## 11. Split Tunneling & DNS Leak Prevention

### Split Tunnel with WireGuard

Route only specific subnets through the tunnel by narrowing `AllowedIPs`:

```ini
# Client config -- only route corporate traffic through VPN
[Peer]
PublicKey = <server_public_key>
AllowedIPs = 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
```

### Split Tunnel with OpenVPN

```ini
# Server-side push (instead of redirect-gateway)
push "route 10.0.0.0 255.0.0.0"
push "route 172.16.0.0 255.240.0.0"
# Do NOT push redirect-gateway
```

### DNS Leak Prevention

DNS leaks occur when DNS queries bypass the VPN tunnel, revealing browsing activity to the ISP. Prevention strategies:

1. **Push DNS via VPN**: Force all DNS through the tunnel.
2. **Block non-VPN DNS**: Firewall rules to drop DNS packets on non-tunnel interfaces.
3. **Use DNS-over-HTTPS/TLS on the VPN server**: Run a resolver (Unbound, dnscrypt-proxy) on the VPN gateway.
4. **Disable OS smart multi-homed resolution**: On Windows, disable Smart Multi-Homed Name Resolution.

```bash
# Block DNS leaks with iptables (on the client)
# Allow DNS only to the VPN DNS server
iptables -A OUTPUT -p udp --dport 53 -d 10.0.0.1 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 10.0.0.1 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j DROP
iptables -A OUTPUT -p tcp --dport 53 -j DROP

# On systemd-resolved systems, set DNS for the tunnel interface
resolvectl dns wg0 10.0.0.1
resolvectl domain wg0 "~."
resolvectl default-route wg0 true
```

### Testing for DNS Leaks

```bash
# Check which DNS server is being used
dig +short whoami.akamai.net @ns1-1.akamaitech.net
nslookup -type=txt o-o.myaddr.l.google.com ns1.google.com

# Use an online checker after connecting
# https://www.dnsleaktest.com
# https://ipleak.net
```

---

## 12. Kill Switches & Fail-Closed Design

A kill switch ensures no traffic can leave the device outside the VPN tunnel, even if the VPN connection drops.

### WireGuard Kill Switch with iptables

```bash
#!/usr/bin/env bash
# /etc/wireguard/scripts/killswitch-up.sh
# Called from PostUp in wg0.conf

VPN_IFACE="wg0"
VPN_SERVER="203.0.113.10"
VPN_PORT="51820"
LAN_SUBNET="192.168.1.0/24"

# Flush existing rules
iptables -F OUTPUT
iptables -F INPUT

# Allow loopback
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT

# Allow LAN access (optional -- remove for strict isolation)
iptables -A OUTPUT -d ${LAN_SUBNET} -j ACCEPT
iptables -A INPUT -s ${LAN_SUBNET} -j ACCEPT

# Allow traffic to VPN server endpoint (the encrypted UDP packets)
iptables -A OUTPUT -d ${VPN_SERVER} -p udp --dport ${VPN_PORT} -j ACCEPT

# Allow all traffic through the VPN tunnel interface
iptables -A OUTPUT -o ${VPN_IFACE} -j ACCEPT
iptables -A INPUT -i ${VPN_IFACE} -j ACCEPT

# Allow DHCP
iptables -A OUTPUT -p udp --dport 67:68 -j ACCEPT
iptables -A INPUT -p udp --sport 67:68 -j ACCEPT

# Drop everything else
iptables -A OUTPUT -j DROP
iptables -A INPUT -j DROP
```

### WireGuard Kill Switch with nftables

```bash
#!/usr/bin/env nft -f
# /etc/wireguard/scripts/killswitch.nft

flush ruleset

table inet killswitch {
    chain output {
        type filter hook output priority 0; policy drop;

        oif lo accept
        oif wg0 accept
        ip daddr 203.0.113.10 udp dport 51820 accept
        ip daddr 192.168.1.0/24 accept
        udp dport 67-68 accept
    }

    chain input {
        type filter hook input priority 0; policy drop;

        iif lo accept
        iif wg0 accept
        ip saddr 203.0.113.10 udp sport 51820 accept
        ip saddr 192.168.1.0/24 accept
        udp sport 67-68 accept
    }
}
```

### OpenVPN Kill Switch

OpenVPN has a built-in `persist-tun` directive that keeps the tunnel interface open on restart. Combine with route rules:

```ini
# In client.ovpn
persist-tun
# Pull routes from server, block outside traffic when disconnected
# Use the management interface + script to apply firewall rules
up /etc/openvpn/scripts/killswitch-up.sh
down /etc/openvpn/scripts/killswitch-down.sh
```

---

## 13. MTU Optimization & Performance Tuning

### Understanding VPN MTU Overhead

Each VPN protocol adds headers that reduce the effective MTU:

| Protocol | Overhead (bytes) | Effective MTU (from 1500) |
|---|---|---|
| WireGuard (IPv4) | 60 (20 IP + 8 UDP + 32 WG) | 1440 |
| WireGuard (IPv6) | 80 (40 IP + 8 UDP + 32 WG) | 1420 |
| OpenVPN (UDP, no comp) | ~48-70 | ~1430-1452 |
| IPsec ESP (AES-GCM) | ~50-73 | ~1427-1450 |
| IPsec + NAT-T | ~76-100 | ~1400-1424 |

### Finding the Optimal MTU

```bash
# Find the largest packet that passes without fragmentation
# Start at 1500 and decrease until ping succeeds
# -M do = don't fragment (Linux)
# -D = don't fragment (macOS)

# Linux
ping -c 5 -M do -s 1412 vpn.example.com

# macOS
ping -c 5 -D -s 1412 vpn.example.com

# Binary search script
#!/usr/bin/env bash
TARGET="10.0.0.1"
LOW=1200
HIGH=1500

while [ $((HIGH - LOW)) -gt 1 ]; do
  MID=$(( (LOW + HIGH) / 2 ))
  if ping -c 1 -M do -s $MID -W 2 "$TARGET" > /dev/null 2>&1; then
    LOW=$MID
  else
    HIGH=$MID
  fi
done

echo "Maximum payload size: ${LOW}"
echo "Optimal MTU: $((LOW + 28))"  # Add IP (20) + ICMP (8) headers
```

### Setting MTU in WireGuard

```ini
[Interface]
MTU = 1420
```

If not set, WireGuard auto-detects based on the underlying route's MTU minus overhead. Explicit values are recommended when you know the path MTU or when traversing PPPoE (1492 base MTU) or other non-standard links.

### MSS Clamping

When you cannot control the MTU of all endpoints, clamp the TCP MSS to avoid fragmentation:

```bash
# Clamp MSS to match VPN MTU (MTU - 40 for IPv4 TCP)
iptables -t mangle -A FORWARD -o wg0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

### WireGuard Performance Tips

- Use kernel module (not wireguard-go) -- 3-5x throughput difference.
- Enable hardware crypto offload if supported (`ethtool -k eth0 | grep esp`).
- Increase socket buffer sizes: `sysctl -w net.core.rmem_max=26214400` and `sysctl -w net.core.wmem_max=26214400`.
- Pin WireGuard softirq to dedicated CPU cores on high-throughput gateways.
- Disable GRO/GSO if you see performance issues with certain NIC drivers.

---

## 14. Multi-Hop VPN

Multi-hop VPN routes traffic through two or more VPN servers before reaching the destination, adding defense in depth.

### WireGuard Chained Tunnels

**Architecture**: Client -> Hop1 (wg0) -> Hop2 (wg1) -> Internet

On the client:

```ini
# /etc/wireguard/wg0.conf -- Tunnel to Hop1
[Interface]
Address = 10.0.1.2/32
PrivateKey = <client_key>
DNS = 10.0.2.1
# Route table to avoid conflicts
Table = 51820
PostUp = ip rule add from 10.0.1.2 table 51820
PostDown = ip rule del from 10.0.1.2 table 51820

[Peer]
PublicKey = <hop1_public_key>
Endpoint = hop1.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

On Hop1 (forwarding to Hop2):

```ini
# /etc/wireguard/wg0.conf -- Accepts client connections
[Interface]
Address = 10.0.1.1/24
ListenPort = 51820
PrivateKey = <hop1_key>
PostUp = iptables -A FORWARD -i wg0 -o wg1 -j ACCEPT; iptables -A FORWARD -i wg1 -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -o wg1 -j ACCEPT; iptables -D FORWARD -i wg1 -o wg0 -j ACCEPT

[Peer]
PublicKey = <client_public_key>
AllowedIPs = 10.0.1.2/32

# /etc/wireguard/wg1.conf -- Tunnel to Hop2
[Interface]
Address = 10.0.2.2/32
PrivateKey = <hop1_outbound_key>

[Peer]
PublicKey = <hop2_public_key>
Endpoint = hop2.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

On Hop2 (exit node):

```ini
# /etc/wireguard/wg0.conf -- Exit node
[Interface]
Address = 10.0.2.1/24
ListenPort = 51820
PrivateKey = <hop2_key>
PostUp = iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -s 10.0.2.0/24 -o eth0 -j MASQUERADE

[Peer]
PublicKey = <hop1_outbound_public_key>
AllowedIPs = 10.0.2.2/32, 10.0.1.0/24
```

### When to Use Multi-Hop

- **Threat model requires distrust of any single VPN provider**: No single hop sees both your identity and your destination.
- **Jurisdiction diversification**: Hops in different legal jurisdictions.
- **Defense against compromised exit nodes**: Inner tunnel encryption protects against a compromised outer hop.

### When NOT to Use Multi-Hop

- **Latency-sensitive applications**: Each hop adds RTT.
- **Throughput-critical workloads**: Throughput is limited to the slowest link.
- **Simple privacy needs**: A single well-configured hop is usually sufficient.

---

## 15. Best Practices

### Key Management
- Generate keys on the device that will use them. Never transmit private keys over the network.
- Use preshared keys (PSK) in WireGuard for post-quantum resistance.
- Rotate keys on a fixed schedule (90 days recommended) and on any suspected compromise.
- Store private keys with `chmod 600` and owned by root.

### Protocol Selection
- Default to WireGuard for new deployments unless a specific requirement dictates otherwise.
- Use IPsec/IKEv2 when native OS client support is required (no app installation).
- Use OpenVPN when TCP transport or censorship circumvention is needed.

### Network Architecture
- Assign each VPN tunnel its own /30 or /31 point-to-point subnet for site-to-site.
- Use unique private address ranges for VPN subnets to avoid conflicts with common LANs (avoid 192.168.0.0/24 and 192.168.1.0/24).
- Document AllowedIPs routing tables -- they are your routing policy.
- Enable IPv6 on the tunnel or explicitly block it to prevent leaks.

### Security Hardening
- Always use a kill switch for road warrior clients.
- Implement DNS leak prevention on all client configurations.
- Run the VPN server with minimal privileges (drop capabilities, use namespaces).
- Monitor peer handshake timestamps to detect stale or compromised connections.
- Log connection metadata (timestamps, source IPs) but never tunnel contents.

### Operational
- Use configuration management (Ansible, Terraform) to deploy and update VPN configs.
- Monitor tunnel uptime and latency with synthetic probes (e.g., ping through the tunnel every 30s).
- Set up alerting for handshake failures, unusual traffic patterns, or certificate expiration.
- Test failover scenarios regularly -- kill the primary tunnel and verify the backup activates.
- Keep WireGuard kernel module and OpenVPN/strongSwan updated for security patches.

### MTU & Performance
- Always set MTU explicitly rather than relying on auto-detection.
- Use MSS clamping on forwarding gateways.
- Benchmark throughput after deployment with iperf3 through the tunnel.
- Use kernel-space implementations (WireGuard kernel module, IPsec XFRM) over userspace when possible.

---

## 16. Anti-Patterns

### Insecure Defaults
- **Using PSK-only IPsec without certificates**: Pre-shared key IKE with aggressive mode leaks the identity hash. Always use IKEv2 with certificates or EAP.
- **OpenVPN with static keys instead of TLS**: Static key mode has no forward secrecy and no key rotation. Always use TLS mode.
- **Disabling tls-crypt/tls-auth in OpenVPN**: Leaves the control channel vulnerable to unauthenticated probing and DDoS.

### Configuration Mistakes
- **AllowedIPs = 0.0.0.0/0 on multiple peers**: Only one peer can be the default route. Conflicting entries cause unpredictable routing.
- **SaveConfig = true with manual edits**: SaveConfig overwrites the config file on shutdown with runtime state, clobbering any manual edits made while the interface is up.
- **Hardcoding endpoints for both sides of a site-to-site**: If both sides have static IPs, it works. But if either side is dynamic, only the dynamic side should specify `Endpoint`.
- **Running OpenVPN as root without dropping privileges**: Always use `user nobody` and `group nogroup` after initialization.

### Operational Failures
- **No certificate revocation process**: Issuing certificates without a CRL distribution plan means you cannot revoke compromised client certificates.
- **No monitoring of tunnel state**: Discovering VPN outages from user complaints instead of proactive monitoring.
- **Ignoring IPv6**: If IPv6 is not explicitly handled (either tunneled or blocked), it leaks around the VPN tunnel.
- **Using TCP for WireGuard or wrapping UDP VPNs in TCP**: TCP-over-TCP causes catastrophic performance degradation under packet loss (retransmission amplification). If you need TCP transport, use OpenVPN's native TCP mode which avoids the double-retransmission issue.
- **Sharing private keys across multiple devices**: Each device should have its own keypair. Shared keys make revocation impossible and breach investigation difficult.

### Architecture Mistakes
- **Using VPN as a substitute for application-level encryption**: VPN protects the transport layer. Applications must still use TLS/mTLS for end-to-end security.
- **Flat VPN network with no segmentation**: All VPN clients on one /24 with no firewall rules. Segment by role, apply per-peer or per-group ACLs.
- **Relying on VPN for zero-trust**: VPN authenticates the tunnel, not the user's intent. Combine with identity-aware proxies, service mesh mTLS, and least-privilege access.

---

## 17. Sources & References

- WireGuard official documentation and whitepaper: [https://www.wireguard.com/papers/wireguard.pdf](https://www.wireguard.com/papers/wireguard.pdf)
- OpenVPN community documentation and hardening guide: [https://community.openvpn.net/openvpn/wiki/Hardening](https://community.openvpn.net/openvpn/wiki/Hardening)
- strongSwan IKEv2 configuration reference: [https://docs.strongswan.org/docs/5.9/config/IKEv2.html](https://docs.strongswan.org/docs/5.9/config/IKEv2.html)
- Tailscale architecture and how NAT traversal works: [https://tailscale.com/blog/how-nat-traversal-works](https://tailscale.com/blog/how-nat-traversal-works)
- Nebula overlay networking documentation: [https://nebula.defined.net/docs/](https://nebula.defined.net/docs/)
- ZeroTier manual and protocol design: [https://docs.zerotier.com/protocol](https://docs.zerotier.com/protocol)
- easy-rsa documentation: [https://easy-rsa.readthedocs.io/en/latest/](https://easy-rsa.readthedocs.io/en/latest/)
- NIST SP 800-77 Rev. 1 -- Guide to IPsec VPNs: [https://csrc.nist.gov/publications/detail/sp/800-77/rev-1/final](https://csrc.nist.gov/publications/detail/sp/800-77/rev-1/final)
- Headscale self-hosted Tailscale control server: [https://github.com/juanfont/headscale](https://github.com/juanfont/headscale)
- DNS leak test methodology and prevention: [https://www.dnsleaktest.com/what-is-a-dns-leak.html](https://www.dnsleaktest.com/what-is-a-dns-leak.html)
