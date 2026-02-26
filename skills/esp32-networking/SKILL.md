---
name: esp32-networking
description: ESP32 Networking — Wi-Fi station/AP/AP+STA modes, provisioning (SoftAP, BLE), ESP-NETIF, HTTP client/server, HTTPS with cert bundles, mDNS, OTA updates, BLE NimBLE stack, ESP-NOW, TCP/UDP sockets, DNS, SNTP time sync
---

# ESP32 Networking

Comprehensive networking reference for ESP32 firmware development with ESP-IDF (v5.x). Covers Wi-Fi in station, access point, and concurrent AP+STA modes, Wi-Fi provisioning via SoftAP and BLE, the ESP-NETIF abstraction layer, HTTP client and server APIs, HTTPS with certificate bundles, mDNS service discovery, OTA firmware updates with rollback support, Bluetooth Low Energy using the NimBLE stack, ESP-NOW peer-to-peer communication, raw TCP/UDP sockets, DNS resolution, and NTP time synchronization via SNTP.

## Table of Contents

1. [Wi-Fi Modes and Event Handling](#1-wi-fi-modes-and-event-handling)
2. [Wi-Fi Scan, Connect, and IP Configuration](#2-wi-fi-scan-connect-and-ip-configuration)
3. [Wi-Fi Provisioning (SoftAP and BLE)](#3-wi-fi-provisioning-softap-and-ble)
4. [ESP-NETIF Abstraction Layer](#4-esp-netif-abstraction-layer)
5. [HTTP Client (esp_http_client)](#5-http-client-esp_http_client)
6. [HTTP Server (httpd) and Captive Portal](#6-http-server-httpd-and-captive-portal)
7. [HTTPS and Certificate Bundles](#7-https-and-certificate-bundles)
8. [mDNS Service Discovery](#8-mdns-service-discovery)
9. [OTA Firmware Updates with Rollback](#9-ota-firmware-updates-with-rollback)
10. [Bluetooth Low Energy (NimBLE Stack)](#10-bluetooth-low-energy-nimble-stack)
11. [ESP-NOW Peer-to-Peer Communication](#11-esp-now-peer-to-peer-communication)
12. [TCP/UDP Sockets and DNS Resolution](#12-tcpudp-sockets-and-dns-resolution)
13. [SNTP Time Synchronization](#13-sntp-time-synchronization)
14. [Connection Recovery Strategies](#14-connection-recovery-strategies)
15. [Best Practices](#15-best-practices)
16. [Anti-Patterns](#16-anti-patterns)
17. [Sources & References](#17-sources--references)

---

## 1. Wi-Fi Modes and Event Handling

ESP32 supports three Wi-Fi operating modes: station (STA), access point (AP), and concurrent AP+STA. The Wi-Fi subsystem communicates through the ESP event loop, which dispatches `WIFI_EVENT` and `IP_EVENT` types.

### Mode Configuration

- **STA mode** (`WIFI_MODE_STA`): Connects to an existing access point. Used for internet-connected devices.
- **AP mode** (`WIFI_MODE_AP`): Creates an access point that other devices connect to. Used for provisioning or local control.
- **AP+STA mode** (`WIFI_MODE_APSTA`): Simultaneous AP and STA. The device connects to a router while also serving as an AP for local clients.

### Event Loop Architecture

The ESP-IDF event loop dispatches events to registered handlers. Wi-Fi events include `WIFI_EVENT_STA_START`, `WIFI_EVENT_STA_CONNECTED`, `WIFI_EVENT_STA_DISCONNECTED`, `WIFI_EVENT_AP_STACONNECTED`, and `WIFI_EVENT_AP_STADISCONNECTED`. IP events include `IP_EVENT_STA_GOT_IP` and `IP_EVENT_STA_LOST_IP`.

```c
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_netif.h"

static const char *TAG = "wifi";
static int s_retry_num = 0;
#define MAX_RETRY 10

static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT) {
        switch (event_id) {
        case WIFI_EVENT_STA_START:
            ESP_LOGI(TAG, "STA started, connecting...");
            esp_wifi_connect();
            break;
        case WIFI_EVENT_STA_CONNECTED:
            ESP_LOGI(TAG, "Connected to AP");
            s_retry_num = 0;
            break;
        case WIFI_EVENT_STA_DISCONNECTED: {
            wifi_event_sta_disconnected_t *disconn =
                (wifi_event_sta_disconnected_t *)event_data;
            ESP_LOGW(TAG, "Disconnected, reason: %d", disconn->reason);
            if (s_retry_num < MAX_RETRY) {
                int delay_ms = (1 << s_retry_num) * 1000;  // exponential backoff
                if (delay_ms > 30000) delay_ms = 30000;
                vTaskDelay(pdMS_TO_TICKS(delay_ms));
                esp_wifi_connect();
                s_retry_num++;
                ESP_LOGI(TAG, "Retry %d/%d (delay %dms)", s_retry_num, MAX_RETRY, delay_ms);
            } else {
                ESP_LOGE(TAG, "Max retries reached, giving up");
            }
            break;
        }
        case WIFI_EVENT_AP_STACONNECTED: {
            wifi_event_ap_staconnected_t *event =
                (wifi_event_ap_staconnected_t *)event_data;
            ESP_LOGI(TAG, "Station " MACSTR " joined, AID=%d",
                     MAC2STR(event->mac), event->aid);
            break;
        }
        case WIFI_EVENT_AP_STADISCONNECTED: {
            wifi_event_ap_stadisconnected_t *event =
                (wifi_event_ap_stadisconnected_t *)event_data;
            ESP_LOGI(TAG, "Station " MACSTR " left, AID=%d",
                     MAC2STR(event->mac), event->aid);
            break;
        }
        default:
            break;
        }
    } else if (event_base == IP_EVENT) {
        if (event_id == IP_EVENT_STA_GOT_IP) {
            ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
            ESP_LOGI(TAG, "Got IP: " IPSTR, IP2STR(&event->ip_info.ip));
        } else if (event_id == IP_EVENT_STA_LOST_IP) {
            ESP_LOGW(TAG, "Lost IP address");
        }
    }
}

void wifi_init_sta(const char *ssid, const char *password)
{
    // Initialize NVS (required for Wi-Fi)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
        ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    }

    // Initialize networking and event loop
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    // Initialize Wi-Fi with default config
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    // Register event handlers
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL));

    // Configure and start
    wifi_config_t wifi_config = {
        .sta = {
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
            .sae_pwe_h2e = WPA3_SAE_PWE_BOTH,
        },
    };
    strlcpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
    strlcpy((char *)wifi_config.sta.password, password,
            sizeof(wifi_config.sta.password));

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());
}
```

### Key Disconnect Reason Codes

| Reason Code | Constant | Meaning |
|-------------|----------|---------|
| 2 | `WIFI_REASON_AUTH_EXPIRE` | Authentication expired |
| 15 | `WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT` | WPA handshake failed |
| 201 | `WIFI_REASON_NO_AP_FOUND` | SSID not found in scan |
| 202 | `WIFI_REASON_AUTH_FAIL` | Wrong password |
| 203 | `WIFI_REASON_ASSOC_FAIL` | Association failed |

---

## 2. Wi-Fi Scan, Connect, and IP Configuration

### Active Scan

Use `esp_wifi_scan_start()` to discover nearby access points. The scan is blocking when `block` is set to `true`, or non-blocking with results delivered via `WIFI_EVENT_SCAN_DONE`.

```c
#include "esp_wifi.h"
#include "esp_log.h"

#define MAX_SCAN_RESULTS 20

void wifi_scan_and_connect(void)
{
    wifi_scan_config_t scan_config = {
        .ssid = NULL,           // scan all SSIDs
        .bssid = NULL,          // scan all BSSIDs
        .channel = 0,           // scan all channels
        .show_hidden = true,    // include hidden networks
        .scan_type = WIFI_SCAN_TYPE_ACTIVE,
        .scan_time.active.min = 100,
        .scan_time.active.max = 300,
    };

    ESP_ERROR_CHECK(esp_wifi_scan_start(&scan_config, true));  // blocking

    uint16_t ap_count = 0;
    ESP_ERROR_CHECK(esp_wifi_scan_get_ap_num(&ap_count));
    ESP_LOGI("scan", "Found %d access points", ap_count);

    if (ap_count > MAX_SCAN_RESULTS) ap_count = MAX_SCAN_RESULTS;

    wifi_ap_record_t ap_records[MAX_SCAN_RESULTS];
    ESP_ERROR_CHECK(esp_wifi_scan_get_ap_records(&ap_count, ap_records));

    for (int i = 0; i < ap_count; i++) {
        ESP_LOGI("scan", "  [%d] SSID: %-32s  RSSI: %d  Channel: %d  Auth: %d",
                 i, ap_records[i].ssid, ap_records[i].rssi,
                 ap_records[i].primary, ap_records[i].authmode);
    }

    // Clean up scan results from internal memory
    esp_wifi_clear_ap_list();
}
```

### Static IP Configuration

By default ESP-NETIF uses DHCP. To assign a static IP, stop the DHCP client first, then set the IP info manually.

```c
#include "esp_netif.h"

void set_static_ip(esp_netif_t *netif)
{
    // Stop DHCP client before setting static IP
    ESP_ERROR_CHECK(esp_netif_dhcpc_stop(netif));

    esp_netif_ip_info_t ip_info = {0};
    ip_info.ip.addr      = ESP_IP4TOADDR(192, 168, 1, 100);
    ip_info.gw.addr      = ESP_IP4TOADDR(192, 168, 1, 1);
    ip_info.netmask.addr = ESP_IP4TOADDR(255, 255, 255, 0);

    ESP_ERROR_CHECK(esp_netif_set_ip_info(netif, &ip_info));

    // Set DNS server
    esp_netif_dns_info_t dns_info;
    dns_info.ip.u_addr.ip4.addr = ESP_IP4TOADDR(8, 8, 8, 8);
    dns_info.ip.type = ESP_IPADDR_TYPE_V4;
    ESP_ERROR_CHECK(esp_netif_set_dns_info(netif, ESP_NETIF_DNS_MAIN, &dns_info));

    ESP_LOGI("net", "Static IP set: 192.168.1.100");
}
```

### DHCP vs Static Decision

- **DHCP**: Default, simplest, works with any network. Preferred for consumer devices.
- **Static IP**: Use for industrial devices, gateways, or when IP must be known at compile time. Requires `esp_netif_dhcpc_stop()` before calling `esp_netif_set_ip_info()`.

---

## 3. Wi-Fi Provisioning (SoftAP and BLE)

ESP-IDF provides a unified provisioning framework (`wifi_provisioning`) that supports SoftAP and BLE transport layers. The user sends Wi-Fi credentials to the ESP32 through a phone app or web interface.

### SoftAP Provisioning

The device starts a temporary access point. A phone connects to it and sends credentials over HTTP or a custom protocol.

### BLE Provisioning

The device advertises a BLE GATT service. The phone pairs and writes credentials via BLE characteristics. This is more user-friendly since the phone does not need to switch Wi-Fi networks.

### Provisioning Manager Setup

```c
#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_softap.h"
#include "wifi_provisioning/scheme_ble.h"
#include "esp_wifi.h"

// Custom provisioning data handler (e.g., for device name, cloud token)
static esp_err_t custom_prov_data_handler(uint32_t session_id,
                                          const uint8_t *inbuf, ssize_t inlen,
                                          uint8_t **outbuf, ssize_t *outlen,
                                          void *priv_data)
{
    ESP_LOGI("prov", "Received custom data: %.*s", (int)inlen, (char *)inbuf);
    // Echo back acknowledgment
    const char *resp = "{\"status\":\"ok\"}";
    *outbuf = (uint8_t *)strdup(resp);
    *outlen = strlen(resp);
    return ESP_OK;
}

void start_provisioning(bool use_ble)
{
    wifi_prov_mgr_config_t config = {0};

    if (use_ble) {
        config.scheme = wifi_prov_scheme_ble;
        config.scheme_event_handler = WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM;
    } else {
        config.scheme = wifi_prov_scheme_softap;
        config.scheme_event_handler = WIFI_PROV_EVENT_HANDLER_NONE;
    }

    ESP_ERROR_CHECK(wifi_prov_mgr_init(config));

    // Check if device is already provisioned
    bool provisioned = false;
    ESP_ERROR_CHECK(wifi_prov_mgr_is_provisioned(&provisioned));

    if (provisioned) {
        ESP_LOGI("prov", "Already provisioned, starting Wi-Fi STA");
        wifi_prov_mgr_deinit();
        // Start Wi-Fi with stored credentials
        wifi_init_sta(NULL, NULL);  // reads from NVS
        return;
    }

    // Register custom endpoint for extra data
    wifi_prov_mgr_endpoint_create("custom-data");

    // Start provisioning with security
    // Security 1 = SRP6a + AES-CTR encryption (proof of possession)
    const char *pop = "mydevice123";  // proof of possession
    const char *service_name = "PROV_ESP32";

    ESP_ERROR_CHECK(wifi_prov_mgr_start_provisioning(
        WIFI_PROV_SECURITY_1, pop, service_name, NULL));

    wifi_prov_mgr_endpoint_register("custom-data",
                                     custom_prov_data_handler, NULL);
}
```

### Captive Portal for SoftAP Provisioning

When using SoftAP provisioning, redirect all DNS queries to the ESP32 IP to show a captive portal page. This guides the user to the configuration interface automatically.

Key points:
- Set up a DNS server that responds to all queries with the AP IP address (typically 192.168.4.1).
- Serve an HTML page on the HTTP server at `/` with a form for SSID and password.
- On form submission, call `wifi_prov_mgr_configure_sta()` or store credentials in NVS and restart.

---

## 4. ESP-NETIF Abstraction Layer

ESP-NETIF is the network interface abstraction that decouples protocol stacks (lwIP) from network drivers (Wi-Fi, Ethernet, PPP). It manages IP addresses, DHCP, DNS, and routing.

### Key Concepts

- **esp_netif_t**: Opaque handle representing a network interface. Created by `esp_netif_create_default_wifi_sta()`, `esp_netif_create_default_wifi_ap()`, or custom configurations.
- **DHCP client/server**: Runs automatically on STA/AP interfaces. Can be stopped for static IP.
- **DNS**: Configured per-interface. Supports main, backup, and fallback DNS servers.
- **Routing priority**: When multiple interfaces are active (AP+STA), the route table determines outbound traffic path.

### Custom ESP-NETIF Configuration

For advanced use cases such as Ethernet, PPP over serial, or custom drivers:

```c
// Custom netif for Ethernet
esp_netif_inherent_config_t base_cfg = ESP_NETIF_INHERENT_DEFAULT_ETH();
esp_netif_config_t netif_cfg = {
    .base = &base_cfg,
    .stack = ESP_NETIF_NETSTACK_DEFAULT_ETH,
};
esp_netif_t *eth_netif = esp_netif_new(&netif_cfg);
```

### Multiple Interfaces

In AP+STA mode, two netif instances exist simultaneously. The STA interface has a default route for internet-bound traffic, while the AP interface serves connected clients on a separate subnet (default 192.168.4.0/24).

---

## 5. HTTP Client (esp_http_client)

The `esp_http_client` component provides a full-featured HTTP/1.1 client with support for GET, POST, PUT, DELETE, chunked transfer, redirects, basic/digest authentication, and TLS.

### REST Client Patterns

```c
#include "esp_http_client.h"
#include "esp_log.h"
#include "cJSON.h"

static const char *TAG = "http";

// Event handler for streaming responses
static esp_err_t http_event_handler(esp_http_client_event_t *evt)
{
    switch (evt->event_id) {
    case HTTP_EVENT_ON_DATA:
        if (!esp_http_client_is_chunked_response(evt->client)) {
            ESP_LOGI(TAG, "Received %d bytes", evt->data_len);
        }
        break;
    case HTTP_EVENT_ON_FINISH:
        ESP_LOGI(TAG, "HTTP request finished");
        break;
    case HTTP_EVENT_ERROR:
        ESP_LOGE(TAG, "HTTP error");
        break;
    default:
        break;
    }
    return ESP_OK;
}

// GET request with response buffer
esp_err_t http_get_json(const char *url, cJSON **out_json)
{
    char response_buffer[2048] = {0};

    esp_http_client_config_t config = {
        .url = url,
        .event_handler = http_event_handler,
        .user_data = response_buffer,
        .timeout_ms = 10000,
        .buffer_size = 1024,
        .buffer_size_tx = 1024,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);

    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        int status = esp_http_client_get_status_code(client);
        int content_len = esp_http_client_get_content_length(client);
        ESP_LOGI(TAG, "GET %s - Status: %d, Length: %d", url, status, content_len);

        if (status == 200 && out_json != NULL) {
            // Read response body
            int read_len = esp_http_client_read(client, response_buffer,
                                                 sizeof(response_buffer) - 1);
            if (read_len > 0) {
                response_buffer[read_len] = '\0';
                *out_json = cJSON_Parse(response_buffer);
            }
        }
    } else {
        ESP_LOGE(TAG, "GET failed: %s", esp_err_to_name(err));
    }

    esp_http_client_cleanup(client);
    return err;
}

// POST JSON payload
esp_err_t http_post_json(const char *url, const cJSON *payload)
{
    char *json_str = cJSON_PrintUnformatted(payload);
    if (json_str == NULL) return ESP_ERR_NO_MEM;

    esp_http_client_config_t config = {
        .url = url,
        .method = HTTP_METHOD_POST,
        .timeout_ms = 10000,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_post_field(client, json_str, strlen(json_str));

    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        int status = esp_http_client_get_status_code(client);
        ESP_LOGI(TAG, "POST %s - Status: %d", url, status);
    }

    esp_http_client_cleanup(client);
    free(json_str);
    return err;
}
```

### HTTP Client Best Practices

- Always call `esp_http_client_cleanup()` to free resources.
- Set `timeout_ms` to avoid indefinite blocking.
- Use `buffer_size` and `buffer_size_tx` to control memory usage.
- For large responses, use the event handler with `HTTP_EVENT_ON_DATA` to process chunks.
- Reuse the client handle for multiple requests to the same host (connection keep-alive).

---

## 6. HTTP Server (httpd) and Captive Portal

The ESP-IDF HTTP server (`esp_http_server`) is a lightweight, event-driven server suitable for REST APIs, web configuration interfaces, and captive portals.

### Basic HTTP Server

```c
#include "esp_http_server.h"
#include "esp_log.h"
#include "cJSON.h"

static const char *TAG = "httpd";

// GET handler
static esp_err_t status_get_handler(httpd_req_t *req)
{
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "status", "running");
    cJSON_AddNumberToObject(root, "uptime_s", esp_timer_get_time() / 1000000);
    cJSON_AddNumberToObject(root, "free_heap", esp_get_free_heap_size());

    char *json_str = cJSON_PrintUnformatted(root);
    httpd_resp_set_type(req, "application/json");
    httpd_resp_sendstr(req, json_str);

    free(json_str);
    cJSON_Delete(root);
    return ESP_OK;
}

// POST handler with JSON body parsing
static esp_err_t config_post_handler(httpd_req_t *req)
{
    char buf[512];
    int received = httpd_req_recv(req, buf, sizeof(buf) - 1);
    if (received <= 0) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Empty body");
        return ESP_FAIL;
    }
    buf[received] = '\0';

    cJSON *root = cJSON_Parse(buf);
    if (root == NULL) {
        httpd_resp_send_err(req, HTTPD_400_BAD_REQUEST, "Invalid JSON");
        return ESP_FAIL;
    }

    cJSON *ssid = cJSON_GetObjectItem(root, "ssid");
    cJSON *password = cJSON_GetObjectItem(root, "password");
    if (cJSON_IsString(ssid) && cJSON_IsString(password)) {
        ESP_LOGI(TAG, "Received SSID: %s", ssid->valuestring);
        // Store credentials and restart Wi-Fi
    }

    cJSON_Delete(root);
    httpd_resp_sendstr(req, "{\"status\":\"ok\"}");
    return ESP_OK;
}

httpd_handle_t start_webserver(void)
{
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.max_uri_handlers = 16;
    config.stack_size = 8192;
    config.lru_purge_enable = true;  // purge least-recently-used connections

    httpd_handle_t server = NULL;
    if (httpd_start(&server, &config) != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start HTTP server");
        return NULL;
    }

    httpd_uri_t status_uri = {
        .uri = "/api/status",
        .method = HTTP_GET,
        .handler = status_get_handler,
    };
    httpd_register_uri_handler(server, &status_uri);

    httpd_uri_t config_uri = {
        .uri = "/api/config",
        .method = HTTP_POST,
        .handler = config_post_handler,
    };
    httpd_register_uri_handler(server, &config_uri);

    ESP_LOGI(TAG, "HTTP server started");
    return server;
}
```

### Captive Portal DNS Redirect

For provisioning, redirect all DNS queries to the device IP so connecting clients automatically see the configuration page.

---

## 7. HTTPS and Certificate Bundles

For production devices connecting to public APIs, use the ESP x509 certificate bundle which includes a curated set of root CA certificates, similar to a browser trust store.

### Certificate Bundle Configuration

In `menuconfig`, enable `CONFIG_MBEDTLS_CERTIFICATE_BUNDLE` and select either the full Mozilla bundle or a smaller default set. The certificate bundle is embedded in the firmware binary.

### HTTPS Client with Certificate Bundle

```c
#include "esp_http_client.h"
#include "esp_tls.h"
#include "esp_crt_bundle.h"

esp_err_t https_get(const char *url)
{
    esp_http_client_config_t config = {
        .url = url,
        .timeout_ms = 10000,
        .crt_bundle_attach = esp_crt_bundle_attach,  // use certificate bundle
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    esp_err_t err = esp_http_client_perform(client);

    if (err == ESP_OK) {
        ESP_LOGI("https", "Status: %d, Content-Length: %d",
                 esp_http_client_get_status_code(client),
                 esp_http_client_get_content_length(client));
    }

    esp_http_client_cleanup(client);
    return err;
}
```

### Custom CA Certificate (Self-Signed or Private CA)

For connecting to private servers with custom certificates, embed the PEM-encoded CA certificate:

```c
extern const char server_cert_pem_start[] asm("_binary_server_cert_pem_start");
extern const char server_cert_pem_end[]   asm("_binary_server_cert_pem_end");

esp_http_client_config_t config = {
    .url = "https://my-private-server.local:8443/api",
    .cert_pem = server_cert_pem_start,
    .timeout_ms = 10000,
};
```

Place the certificate file in the `main` component directory and add it to `CMakeLists.txt`:

```cmake
idf_component_register(
    SRCS "main.c"
    EMBED_TXTFILES "server_cert.pem"
)
```

### TLS Memory Considerations

- Full certificate bundle adds approximately 64 KB to flash.
- Each TLS connection uses 40-60 KB of heap at peak.
- For memory-constrained devices, use `CONFIG_MBEDTLS_CERTIFICATE_BUNDLE_DEFAULT_CMN` for a smaller bundle.
- Consider using `CONFIG_MBEDTLS_DYNAMIC_BUFFER` to reduce per-connection memory.

---

## 8. mDNS Service Discovery

mDNS (Multicast DNS) allows devices to discover each other on the local network without a central DNS server. ESP-IDF provides a full mDNS responder and querier.

### mDNS Setup

```c
#include "mdns.h"
#include "esp_log.h"

void mdns_setup(const char *hostname, const char *instance_name)
{
    ESP_ERROR_CHECK(mdns_init());
    ESP_ERROR_CHECK(mdns_hostname_set(hostname));
    ESP_ERROR_CHECK(mdns_instance_name_set(instance_name));

    // Advertise an HTTP service
    mdns_txt_item_t service_txt[] = {
        {"board", "esp32"},
        {"firmware", "1.0.0"},
        {"path", "/api"},
    };
    ESP_ERROR_CHECK(mdns_service_add(
        instance_name,    // instance name
        "_http",          // service type
        "_tcp",           // protocol
        80,               // port
        service_txt,      // TXT records
        sizeof(service_txt) / sizeof(service_txt[0])
    ));

    ESP_LOGI("mdns", "mDNS started: %s.local", hostname);
}

// Query for other devices
void mdns_query_http_services(void)
{
    mdns_result_t *results = NULL;
    esp_err_t err = mdns_query_ptr("_http", "_tcp", 3000, 10, &results);
    if (err != ESP_OK || results == NULL) {
        ESP_LOGW("mdns", "No HTTP services found");
        return;
    }

    mdns_result_t *r = results;
    while (r) {
        ESP_LOGI("mdns", "Found: %s (%s:%d)",
                 r->instance_name ? r->instance_name : "(none)",
                 r->hostname ? r->hostname : "(none)",
                 r->port);
        r = r->next;
    }

    mdns_query_results_free(results);
}
```

### mDNS Use Cases

- Device discovery for mobile apps (scan for `_http._tcp` or custom service types).
- Firmware OTA server discovery.
- Peer device communication on the same LAN.
- Hostname resolution without DNS infrastructure (`mydevice.local`).

---

## 9. OTA Firmware Updates with Rollback

ESP-IDF supports over-the-air updates via `esp_https_ota`. The OTA partition table typically has two app partitions (`ota_0`, `ota_1`). On boot, the bootloader selects the active partition. If a new firmware fails validation, it rolls back to the previous working version.

### OTA Partition Table

```
# Name,   Type, SubType,  Offset,   Size
nvs,      data, nvs,      0x9000,   0x4000
otadata,  data, ota,      0xd000,   0x2000
phy_init, data, phy,      0xf000,   0x1000
ota_0,    app,  ota_0,    0x10000,  0x1E0000
ota_1,    app,  ota_1,    0x1F0000, 0x1E0000
```

### HTTPS OTA with Rollback

```c
#include "esp_https_ota.h"
#include "esp_ota_ops.h"
#include "esp_log.h"
#include "esp_crt_bundle.h"

static const char *TAG = "ota";

esp_err_t perform_ota_update(const char *firmware_url)
{
    ESP_LOGI(TAG, "Starting OTA from: %s", firmware_url);

    esp_http_client_config_t http_config = {
        .url = firmware_url,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 30000,
        .keep_alive_enable = true,
    };

    esp_https_ota_config_t ota_config = {
        .http_config = &http_config,
    };

    esp_https_ota_handle_t ota_handle = NULL;
    esp_err_t err = esp_https_ota_begin(&ota_config, &ota_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "OTA begin failed: %s", esp_err_to_name(err));
        return err;
    }

    // Validate firmware image header before downloading full image
    esp_app_desc_t new_app_info;
    err = esp_https_ota_get_img_desc(ota_handle, &new_app_info);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "New firmware: %s v%s",
                 new_app_info.project_name, new_app_info.version);

        // Optional: compare versions to avoid downgrade
        const esp_app_desc_t *current = esp_app_get_description();
        if (strcmp(new_app_info.version, current->version) == 0) {
            ESP_LOGW(TAG, "Same version, skipping update");
            esp_https_ota_abort(ota_handle);
            return ESP_ERR_INVALID_VERSION;
        }
    }

    // Download and flash in chunks
    while (1) {
        err = esp_https_ota_perform(ota_handle);
        if (err != ESP_ERR_HTTPS_OTA_IN_PROGRESS) break;

        int image_size = esp_https_ota_get_image_size(ota_handle);
        int read_size = esp_https_ota_get_image_len_read(ota_handle);
        if (image_size > 0) {
            ESP_LOGI(TAG, "Progress: %d%%", (read_size * 100) / image_size);
        }
    }

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "OTA perform failed: %s", esp_err_to_name(err));
        esp_https_ota_abort(ota_handle);
        return err;
    }

    err = esp_https_ota_finish(ota_handle);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "OTA succeeded, rebooting...");
        esp_restart();
    } else {
        ESP_LOGE(TAG, "OTA finish failed: %s", esp_err_to_name(err));
    }

    return err;
}

// Call on first boot after OTA to validate the new firmware
void ota_validate_and_commit(void)
{
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t ota_state;

    if (esp_ota_get_state_partition(running, &ota_state) == ESP_OK) {
        if (ota_state == ESP_OTA_IMG_PENDING_VERIFY) {
            ESP_LOGI(TAG, "New firmware running, performing self-test...");

            // Run application-level self-test here
            bool self_test_ok = true;  // replace with actual checks

            if (self_test_ok) {
                ESP_LOGI(TAG, "Self-test passed, marking firmware as valid");
                esp_ota_mark_app_valid_cancel_rollback();
            } else {
                ESP_LOGE(TAG, "Self-test failed, rolling back");
                esp_ota_mark_app_invalid_rollback_and_reboot();
            }
        }
    }
}
```

### Rollback Strategy

1. After OTA flash, the new partition is marked `ESP_OTA_IMG_PENDING_VERIFY`.
2. On first boot of the new firmware, run application-level self-tests (Wi-Fi connectivity, sensor reads, cloud ping).
3. If tests pass, call `esp_ota_mark_app_valid_cancel_rollback()`.
4. If tests fail or the device crashes before marking valid, the bootloader automatically rolls back to the previous partition on the next boot.
5. Configure rollback timeout with `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE` in menuconfig.

---

## 10. Bluetooth Low Energy (NimBLE Stack)

ESP-IDF supports BLE via the Apache NimBLE stack, which uses significantly less memory than the Bluedroid stack. NimBLE supports BLE 5.0 features including extended advertising, 2M PHY, and coded PHY.

### NimBLE GATT Server

```c
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/ble_uuid.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

// Custom service UUID: 12345678-1234-1234-1234-123456789abc
static const ble_uuid128_t svc_uuid =
    BLE_UUID128_INIT(0xbc, 0x9a, 0x78, 0x56, 0x34, 0x12, 0x34, 0x12,
                     0x34, 0x12, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12);

// Characteristic UUID for sensor data
static const ble_uuid128_t chr_sensor_uuid =
    BLE_UUID128_INIT(0xcd, 0x9a, 0x78, 0x56, 0x34, 0x12, 0x34, 0x12,
                     0x34, 0x12, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12);

static uint16_t sensor_chr_handle;
static float sensor_value = 25.0f;

// GATT characteristic access callback
static int gatt_chr_access(uint16_t conn_handle, uint16_t attr_handle,
                           struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    switch (ctxt->op) {
    case BLE_GATT_ACCESS_OP_READ_CHR: {
        int rc = os_mbuf_append(ctxt->om, &sensor_value, sizeof(sensor_value));
        return rc == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    case BLE_GATT_ACCESS_OP_WRITE_CHR: {
        uint16_t om_len = OS_MBUF_PKTLEN(ctxt->om);
        if (om_len != sizeof(float)) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        ble_hs_mbuf_to_flat(ctxt->om, &sensor_value, sizeof(sensor_value), NULL);
        ESP_LOGI("ble", "Sensor value written: %.2f", sensor_value);
        return 0;
    }
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

// GATT service definition
static const struct ble_gatt_svc_def gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &svc_uuid.u,
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = &chr_sensor_uuid.u,
                .access_cb = gatt_chr_access,
                .val_handle = &sensor_chr_handle,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE |
                         BLE_GATT_CHR_F_NOTIFY,
            },
            { 0 },  // terminator
        },
    },
    { 0 },  // terminator
};

// Send notification to connected client
void ble_notify_sensor(uint16_t conn_handle)
{
    struct os_mbuf *om = ble_hs_mbuf_from_flat(&sensor_value, sizeof(sensor_value));
    ble_gatts_notify_custom(conn_handle, sensor_chr_handle, om);
}

// GAP event handler
static int ble_gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        ESP_LOGI("ble", "Connection %s, handle=%d",
                 event->connect.status == 0 ? "established" : "failed",
                 event->connect.conn_handle);
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI("ble", "Disconnected, reason=%d", event->disconnect.reason);
        // Restart advertising
        ble_start_advertising();
        break;
    case BLE_GAP_EVENT_SUBSCRIBE:
        ESP_LOGI("ble", "Subscribe event: cur_notify=%d",
                 event->subscribe.cur_notify);
        break;
    default:
        break;
    }
    return 0;
}

void ble_start_advertising(void)
{
    struct ble_gap_adv_params adv_params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
        .itvl_min = BLE_GAP_ADV_ITVL_MS(100),
        .itvl_max = BLE_GAP_ADV_ITVL_MS(150),
    };

    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)"ESP32-Sensor";
    fields.name_len = strlen("ESP32-Sensor");
    fields.name_is_complete = 1;
    fields.tx_pwr_lvl = BLE_HS_ADV_TX_PWR_LVL_AUTO;
    fields.tx_pwr_lvl_is_present = 1;

    ble_gap_adv_set_fields(&fields);
    ble_gap_adv_start(BLE_OWN_ADDR_PUBLIC, NULL, BLE_HS_FOREVER,
                      &adv_params, ble_gap_event, NULL);
}

void ble_init(void)
{
    nimble_port_init();
    ble_svc_gap_init();
    ble_svc_gatt_init();

    int rc = ble_gatts_count_cfg(gatt_svcs);
    assert(rc == 0);
    rc = ble_gatts_add_svcs(gatt_svcs);
    assert(rc == 0);

    ble_svc_gap_device_name_set("ESP32-Sensor");
    nimble_port_freertos_init(nimble_host_task);
}
```

### BLE vs Classic Bluetooth

- **NimBLE (BLE)**: Low power, small packets (up to 251 bytes with DLE), ideal for sensors and IoT. Uses 50-100 KB less RAM than Bluedroid.
- **Bluedroid (Classic + BLE)**: Required for A2DP audio, SPP serial profile, or HID. Uses significantly more RAM.
- **Choose NimBLE** unless you need Classic Bluetooth profiles.

---

## 11. ESP-NOW Peer-to-Peer Communication

ESP-NOW is a connectionless protocol from Espressif that allows direct device-to-device communication without Wi-Fi infrastructure. It uses vendor-specific action frames on top of the Wi-Fi data link layer. Maximum payload is 250 bytes per frame, with low latency (typically under 5 ms).

### ESP-NOW Setup and Broadcast

```c
#include "esp_now.h"
#include "esp_wifi.h"
#include "esp_log.h"
#include <string.h>

static const char *TAG = "espnow";

// Broadcast address (sends to all ESP-NOW peers)
static const uint8_t broadcast_addr[ESP_NOW_ETH_ALEN] = {
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
};

typedef struct {
    uint8_t type;         // message type
    uint16_t sequence;    // sequence number
    float temperature;
    float humidity;
} __attribute__((packed)) sensor_data_t;

// Send callback
static void espnow_send_cb(const uint8_t *mac_addr, esp_now_send_status_t status)
{
    ESP_LOGD(TAG, "Send to " MACSTR " %s",
             MAC2STR(mac_addr),
             status == ESP_NOW_SEND_SUCCESS ? "OK" : "FAIL");
}

// Receive callback
static void espnow_recv_cb(const esp_now_recv_info_t *recv_info,
                            const uint8_t *data, int data_len)
{
    if (data_len < sizeof(sensor_data_t)) return;

    sensor_data_t *sensor = (sensor_data_t *)data;
    ESP_LOGI(TAG, "From " MACSTR ": temp=%.1f, hum=%.1f, seq=%d",
             MAC2STR(recv_info->src_addr),
             sensor->temperature, sensor->humidity, sensor->sequence);
}

void espnow_init(void)
{
    // Wi-Fi must be initialized first (STA or AP mode)
    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_register_send_cb(espnow_send_cb));
    ESP_ERROR_CHECK(esp_now_register_recv_cb(espnow_recv_cb));

    // Add broadcast peer
    esp_now_peer_info_t peer = {0};
    memcpy(peer.peer_addr, broadcast_addr, ESP_NOW_ETH_ALEN);
    peer.channel = 0;  // use current Wi-Fi channel
    peer.encrypt = false;
    ESP_ERROR_CHECK(esp_now_add_peer(&peer));
}

// Add a specific peer with encryption
void espnow_add_encrypted_peer(const uint8_t *mac, const uint8_t *lmk)
{
    esp_now_peer_info_t peer = {0};
    memcpy(peer.peer_addr, mac, ESP_NOW_ETH_ALEN);
    peer.encrypt = true;
    memcpy(peer.lmk, lmk, ESP_NOW_KEY_LEN);  // 16-byte local master key
    ESP_ERROR_CHECK(esp_now_add_peer(&peer));
}

void espnow_send_sensor_data(float temp, float humidity)
{
    static uint16_t seq = 0;
    sensor_data_t data = {
        .type = 0x01,
        .sequence = seq++,
        .temperature = temp,
        .humidity = humidity,
    };

    esp_err_t err = esp_now_send(broadcast_addr, (uint8_t *)&data, sizeof(data));
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Send failed: %s", esp_err_to_name(err));
    }
}
```

### ESP-NOW Characteristics

| Feature | Value |
|---------|-------|
| Max payload | 250 bytes |
| Max peers (encrypted) | 10 (ESP32), 6 (ESP32-S2) |
| Max peers (unencrypted) | 20 |
| Latency | < 5 ms typical |
| Range | Similar to Wi-Fi (~100m line of sight) |
| Encryption | CCMP (same as WPA2) |
| Coexistence | Works alongside Wi-Fi STA/AP |

### ESP-NOW Use Cases

- Sensor mesh networks (star or tree topology).
- Remote controls and actuators.
- Real-time data streaming between ESP32 devices.
- Low-power button triggers (one-shot wake, send, sleep).

---

## 12. TCP/UDP Sockets and DNS Resolution

ESP-IDF includes the lwIP TCP/IP stack with a BSD-compatible sockets API. Use sockets for custom protocols, real-time streaming, or when HTTP overhead is not desired.

### TCP Client

```c
#include "lwip/sockets.h"
#include "lwip/netdb.h"
#include "esp_log.h"

esp_err_t tcp_client_send(const char *host, int port,
                          const uint8_t *data, size_t len)
{
    // DNS resolution
    struct addrinfo hints = {
        .ai_family = AF_INET,
        .ai_socktype = SOCK_STREAM,
    };
    struct addrinfo *res = NULL;
    char port_str[6];
    snprintf(port_str, sizeof(port_str), "%d", port);

    int err = getaddrinfo(host, port_str, &hints, &res);
    if (err != 0 || res == NULL) {
        ESP_LOGE("tcp", "DNS resolution failed for %s: %d", host, err);
        return ESP_FAIL;
    }

    int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (sock < 0) {
        ESP_LOGE("tcp", "Socket creation failed: errno %d", errno);
        freeaddrinfo(res);
        return ESP_FAIL;
    }

    // Set socket timeout
    struct timeval timeout = { .tv_sec = 10, .tv_usec = 0 };
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

    if (connect(sock, res->ai_addr, res->ai_addrlen) != 0) {
        ESP_LOGE("tcp", "Connect failed: errno %d", errno);
        close(sock);
        freeaddrinfo(res);
        return ESP_FAIL;
    }
    freeaddrinfo(res);

    int sent = send(sock, data, len, 0);
    if (sent < 0) {
        ESP_LOGE("tcp", "Send failed: errno %d", errno);
    } else {
        ESP_LOGI("tcp", "Sent %d bytes to %s:%d", sent, host, port);
    }

    // Receive response
    uint8_t rx_buf[512];
    int received = recv(sock, rx_buf, sizeof(rx_buf) - 1, 0);
    if (received > 0) {
        rx_buf[received] = '\0';
        ESP_LOGI("tcp", "Received %d bytes: %s", received, rx_buf);
    }

    close(sock);
    return (sent > 0) ? ESP_OK : ESP_FAIL;
}
```

### UDP Multicast

```c
esp_err_t udp_multicast_send(const char *group_ip, int port,
                              const uint8_t *data, size_t len)
{
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (sock < 0) return ESP_FAIL;

    // Allow multicast loopback for testing
    uint8_t loopback = 1;
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_LOOP, &loopback, sizeof(loopback));

    // Set TTL for multicast
    uint8_t ttl = 1;
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));

    struct sockaddr_in dest = {
        .sin_family = AF_INET,
        .sin_port = htons(port),
    };
    inet_aton(group_ip, &dest.sin_addr);

    int sent = sendto(sock, data, len, 0,
                      (struct sockaddr *)&dest, sizeof(dest));
    close(sock);
    return (sent > 0) ? ESP_OK : ESP_FAIL;
}
```

### Socket Best Practices

- Always set `SO_RCVTIMEO` and `SO_SNDTIMEO` to prevent indefinite blocking.
- Close sockets in error paths to avoid file descriptor leaks (lwIP has a limited pool, default 10).
- Use `select()` or `poll()` for multiplexing multiple sockets on a single task.
- Prefer `getaddrinfo()` over `gethostbyname()` for thread-safe DNS resolution.
- Increase `CONFIG_LWIP_MAX_SOCKETS` if the application needs more concurrent connections.

---

## 13. SNTP Time Synchronization

Accurate time is essential for TLS certificate validation, timestamped logging, and scheduled operations. ESP-IDF provides an SNTP client that synchronizes the system clock with remote NTP servers.

### SNTP Setup

```c
#include "esp_sntp.h"
#include "esp_log.h"
#include <time.h>
#include <sys/time.h>

static const char *TAG = "sntp";

void time_sync_notification_cb(struct timeval *tv)
{
    ESP_LOGI(TAG, "Time synchronized: %lld.%06ld",
             (long long)tv->tv_sec, (long)tv->tv_usec);
}

void sntp_init_time(void)
{
    esp_sntp_setoperatingmode(ESP_SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "pool.ntp.org");
    esp_sntp_setservername(1, "time.google.com");
    esp_sntp_setservername(2, "time.cloudflare.com");
    esp_sntp_set_time_sync_notification_cb(time_sync_notification_cb);
    esp_sntp_set_sync_interval(3600000);  // sync every hour (in ms)
    esp_sntp_init();

    // Set timezone (e.g., US Eastern)
    setenv("TZ", "EST5EDT,M3.2.0/2,M11.1.0", 1);
    tzset();
}

// Wait for time to be set
bool wait_for_time_sync(int timeout_s)
{
    int elapsed = 0;
    while (esp_sntp_get_sync_status() != SNTP_SYNC_STATUS_COMPLETED) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        elapsed++;
        if (elapsed >= timeout_s) {
            ESP_LOGW(TAG, "Time sync timeout after %ds", timeout_s);
            return false;
        }
    }

    time_t now;
    struct tm timeinfo;
    time(&now);
    localtime_r(&now, &timeinfo);
    char strftime_buf[64];
    strftime(strftime_buf, sizeof(strftime_buf), "%Y-%m-%d %H:%M:%S %Z", &timeinfo);
    ESP_LOGI(TAG, "Current time: %s", strftime_buf);
    return true;
}
```

### Time Sync Ordering

Always synchronize time before making HTTPS requests. TLS certificate validation checks the `notBefore` and `notAfter` fields against the system clock. Without valid time, all HTTPS connections will fail certificate verification.

Recommended initialization order:
1. Wi-Fi connect and obtain IP.
2. SNTP synchronize.
3. HTTPS / OTA / cloud API calls.

---

## 14. Connection Recovery Strategies

Robust firmware must handle network interruptions gracefully. Wi-Fi can drop due to AP reboots, interference, range limits, or power-saving conflicts.

### Reconnection State Machine

Design the reconnection logic as a state machine rather than ad-hoc retry loops:

| State | Behavior |
|-------|----------|
| `CONNECTED` | Normal operation. Monitor `WIFI_EVENT_STA_DISCONNECTED`. |
| `RECONNECTING` | Exponential backoff retries. Start at 1s, cap at 60s. |
| `SCANNING` | After max retries, scan for alternative APs or fallback SSID. |
| `FALLBACK` | Switch to AP mode for local access or use cached data. |
| `RECOVERY` | Periodic scan attempts (every 5 min) to restore connectivity. |

### Exponential Backoff with Jitter

Add random jitter to prevent thundering herd when multiple devices reconnect simultaneously after an AP reboot:

```c
#include "esp_random.h"

int calculate_backoff_ms(int retry_count)
{
    int base_delay = 1000;  // 1 second
    int max_delay = 60000;  // 60 seconds
    int delay = base_delay * (1 << retry_count);
    if (delay > max_delay) delay = max_delay;

    // Add 0-25% random jitter
    int jitter = (esp_random() % (delay / 4));
    return delay + jitter;
}
```

### Network Watchdog

Run a background task that periodically verifies connectivity by pinging a known endpoint. If the connection is silently broken (TCP keepalive not triggered), the watchdog forces a reconnect.

### Offline Data Buffering

When the connection drops:
1. Buffer sensor data to NVS or SPIFFS/LittleFS.
2. Timestamp each record using the last known good time.
3. On reconnection, upload buffered data in batches.
4. Implement a circular buffer to avoid filling storage during extended outages.

---

## 15. Best Practices

1. **Always register handlers for both WIFI_EVENT and IP_EVENT.** The connection is not usable until `IP_EVENT_STA_GOT_IP` fires, not just `WIFI_EVENT_STA_CONNECTED`.
2. **Use ESP-NETIF instead of raw lwIP.** The abstraction handles interface lifecycle, DHCP, and future stack changes.
3. **Synchronize time via SNTP before any TLS operation.** Certificate validation depends on correct system time.
4. **Use certificate bundles for public HTTPS endpoints.** Embedding individual CA certs is fragile when servers rotate certificates.
5. **Implement OTA rollback with self-test.** Never mark new firmware valid without verifying core functionality.
6. **Use NimBLE over Bluedroid for BLE-only applications.** NimBLE saves 50-100 KB RAM.
7. **Set socket timeouts on every socket.** Default infinite timeouts cause tasks to hang indefinitely on network failures.
8. **Use exponential backoff with jitter for reconnections.** Prevents network storms when many devices reconnect simultaneously.
9. **Store Wi-Fi credentials in NVS with encryption enabled.** Use `nvs_flash_init_partition()` with encrypted partitions for production.
10. **Free all allocated resources in error paths.** HTTP client handles, socket file descriptors, mDNS results, and cJSON objects all require explicit cleanup.
11. **Use `CONFIG_ESP_WIFI_SOFTAP_SUPPORT` only when needed.** Disabling unused Wi-Fi modes saves flash and RAM.
12. **Buffer data during outages.** Design for intermittent connectivity, not always-on assumptions.

---

## 16. Anti-Patterns

- **Starting HTTPS requests before SNTP sync.** TLS handshake fails because the system clock is at epoch (1970), causing certificate date validation to reject all certificates.
- **Blocking the main event loop task.** Long-running HTTP requests or socket operations in event handlers starve the Wi-Fi driver. Use dedicated tasks.
- **Ignoring `esp_http_client_cleanup()`.** Each leaked handle consumes TLS memory (40-60 KB) and eventually causes heap exhaustion.
- **Using `WIFI_AUTH_OPEN` in production AP mode.** Any device can connect and potentially access internal APIs. Always require WPA2 minimum.
- **Hardcoding Wi-Fi credentials in source code.** Use NVS storage with provisioning flow. Credentials in source end up in version control.
- **Not handling `WIFI_REASON_NO_AP_FOUND` differently from auth failures.** An AP being unreachable versus wrong credentials requires different recovery strategies.
- **Using Bluedroid when only BLE is needed.** Wastes 50-100 KB of RAM for unused Classic Bluetooth support.
- **Polling for connection state instead of using events.** The event loop exists precisely to avoid busy-wait patterns. Register handlers and react.
- **Sending ESP-NOW frames without checking channel alignment.** ESP-NOW frames are sent on the current Wi-Fi channel. If the STA interface switches channels during roaming, ESP-NOW peers on the old channel stop receiving.
- **Not validating OTA image headers before full download.** Always check `esp_app_desc_t` fields (version, project name, secure boot digest) before committing to a full firmware download.
- **Using `gethostbyname()` from multiple tasks.** It is not thread-safe in lwIP. Use `getaddrinfo()` which is reentrant.
- **Skipping `esp_wifi_clear_ap_list()` after scan.** Scan results consume heap memory until explicitly freed.

---

## 17. Sources & References

- [ESP-IDF Wi-Fi Driver Programming Guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-guides/wifi.html)
- [ESP-IDF Wi-Fi Provisioning Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/provisioning/wifi_provisioning.html)
- [ESP-IDF ESP-NETIF API Reference](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_netif.html)
- [ESP-IDF HTTP Client (esp_http_client)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/esp_http_client.html)
- [ESP-IDF HTTPS OTA Updates](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/esp_https_ota.html)
- [ESP-IDF ESP-NOW Programming Guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_now.html)
- [Apache NimBLE Host API Reference](https://mynewt.apache.org/latest/network/index.html)
- [ESP-IDF mDNS Service Discovery](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/mdns.html)
- [ESP-IDF SNTP Time Synchronization](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/system_time.html)
- [ESP-IDF Bluetooth Low Energy (NimBLE)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/bluetooth/nimble/index.html)
- [ESP-IDF HTTP Server Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/esp_http_server.html)
- [ESP-IDF TLS and Certificate Bundles](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/esp_tls.html)
