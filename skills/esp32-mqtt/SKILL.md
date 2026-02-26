---
name: esp32-mqtt
description: ESP-MQTT client library for ESP32 -- MQTT 3.1.1/5.0 protocol, TLS/SSL, QoS levels, event-driven architecture, reconnection strategies, and cJSON payload serialization
---

# ESP32 MQTT -- Firmware Engineer Patterns

Production-ready patterns for the ESP-MQTT client library on ESP32 using ESP-IDF. Covers MQTT 3.1.1 and 5.0 protocol support, broker connection, TLS/SSL configuration, QoS levels (0/1/2), topic subscription and publishing, last will and testament, retained messages, persistent sessions, event-driven architecture, reconnection strategies, message buffering, and JSON payload serialization with cJSON.

## Table of Contents

1. [MQTT Client Initialization](#mqtt-client-initialization)
2. [Event Handler Patterns](#event-handler-patterns)
3. [TLS/SSL and Certificate-Based Security](#tlsssl-and-certificate-based-security)
4. [QoS Levels and Delivery Guarantees](#qos-levels-and-delivery-guarantees)
5. [Topic Hierarchy Design for IoT](#topic-hierarchy-design-for-iot)
6. [Last Will and Testament & Retained Messages](#last-will-and-testament--retained-messages)
7. [Persistent Sessions and Message Buffering](#persistent-sessions-and-message-buffering)
8. [MQTT over WebSocket](#mqtt-over-websocket)
9. [JSON Payload Serialization with cJSON](#json-payload-serialization-with-cjson)
10. [Keep-Alive Tuning and Connection Backoff](#keep-alive-tuning-and-connection-backoff)
11. [Payload Size Optimization](#payload-size-optimization)
12. [MQTT 5.0 Protocol Features](#mqtt-50-protocol-features)
13. [Best Practices](#best-practices)
14. [Anti-Patterns](#anti-patterns)
15. [Sources & References](#sources--references)

---

## MQTT Client Initialization

The ESP-MQTT library provides `esp_mqtt_client_init` to create a client handle. Configure the client through `esp_mqtt_client_config_t` before starting the connection.

```c
#include "mqtt_client.h"
#include "esp_log.h"
#include "esp_event.h"

static const char *TAG = "MQTT";

static esp_mqtt_client_handle_t mqtt_client = NULL;

static void mqtt_event_handler(void *handler_args, esp_event_base_t base,
                                int32_t event_id, void *event_data);

void mqtt_app_start(void)
{
    const esp_mqtt_client_config_t mqtt_cfg = {
        .broker = {
            .address = {
                .uri = "mqtt://broker.example.com:1883",
            },
        },
        .credentials = {
            .username = "device_01",
            .authentication = {
                .password = "secure_password",
            },
            .client_id = "esp32_device_01",
        },
        .session = {
            .keepalive = 30,
            .disable_clean_session = false,
            .last_will = {
                .topic = "devices/esp32_device_01/status",
                .msg = "{\"online\":false}",
                .msg_len = 0,
                .qos = 1,
                .retain = true,
            },
        },
        .network = {
            .reconnect_timeout_ms = 5000,
            .timeout_ms = 10000,
        },
        .buffer = {
            .size = 1024,
            .out_size = 512,
        },
        .task = {
            .priority = 5,
            .stack_size = 6144,
        },
    };

    mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    if (mqtt_client == NULL) {
        ESP_LOGE(TAG, "Failed to initialize MQTT client");
        return;
    }

    esp_mqtt_client_register_event(mqtt_client, ESP_EVENT_ANY_ID,
                                    mqtt_event_handler, NULL);

    esp_err_t err = esp_mqtt_client_start(mqtt_client);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to start MQTT client: %s", esp_err_to_name(err));
    }
}
```

### Configuration Field Groups

The `esp_mqtt_client_config_t` struct is organized into groups:

- **broker**: URI, hostname, port, certificate verification
- **credentials**: client_id, username, password, certificate auth
- **session**: keepalive, clean session, LWT, protocol version
- **network**: reconnect timeout, transport timeout, refresh connection
- **buffer**: inbound and outbound buffer sizes
- **task**: FreeRTOS task priority and stack size

### URI Scheme Reference

| Scheme | Transport | Default Port |
|--------|-----------|-------------|
| `mqtt://` | TCP | 1883 |
| `mqtts://` | TLS | 8883 |
| `ws://` | WebSocket | 80 |
| `wss://` | WebSocket + TLS | 443 |

---

## Event Handler Patterns

ESP-MQTT uses the ESP-IDF event loop. Register a handler to receive connection, subscription, publish, and error events.

```c
static void mqtt_event_handler(void *handler_args, esp_event_base_t base,
                                int32_t event_id, void *event_data)
{
    esp_mqtt_event_handle_t event = event_data;
    esp_mqtt_client_handle_t client = event->client;

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "Connected to broker, session_present=%d",
                 event->session_present);
        /* Subscribe to command topics after connection */
        esp_mqtt_client_subscribe(client, "devices/+/commands", 1);
        /* Publish birth message */
        esp_mqtt_client_publish(client,
            "devices/esp32_device_01/status",
            "{\"online\":true}", 0, 1, 1);
        break;

    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "Disconnected from broker");
        /* Library handles reconnection automatically */
        break;

    case MQTT_EVENT_SUBSCRIBED:
        ESP_LOGI(TAG, "Subscribed, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_UNSUBSCRIBED:
        ESP_LOGI(TAG, "Unsubscribed, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_PUBLISHED:
        ESP_LOGI(TAG, "Published, msg_id=%d", event->msg_id);
        break;

    case MQTT_EVENT_DATA:
        ESP_LOGI(TAG, "Received data on topic=%.*s",
                 event->topic_len, event->topic);
        /* Handle fragmented messages */
        if (event->data_len < event->total_data_len) {
            ESP_LOGI(TAG, "Fragment %d/%d",
                     event->current_data_offset + event->data_len,
                     event->total_data_len);
        }
        process_incoming_message(event->topic, event->topic_len,
                                 event->data, event->data_len,
                                 event->total_data_len,
                                 event->current_data_offset);
        break;

    case MQTT_EVENT_ERROR:
        ESP_LOGE(TAG, "MQTT error type=%d", event->error_handle->error_type);
        if (event->error_handle->error_type == MQTT_ERROR_TYPE_TCP_TRANSPORT) {
            ESP_LOGE(TAG, "TLS error=0x%04x, tls_stack=0x%04x",
                     event->error_handle->esp_tls_last_esp_err,
                     event->error_handle->esp_tls_stack_err);
        }
        break;

    case MQTT_EVENT_BEFORE_CONNECT:
        ESP_LOGI(TAG, "About to connect to broker");
        break;

    default:
        ESP_LOGD(TAG, "Unhandled event id=%d", event->event_id);
        break;
    }
}
```

### Handling Fragmented Messages

Messages larger than the receive buffer arrive in fragments. Track reassembly with `current_data_offset` and `total_data_len`:

```c
static char *reassembly_buffer = NULL;

static void process_incoming_message(const char *topic, int topic_len,
                                      const char *data, int data_len,
                                      int total_data_len,
                                      int current_data_offset)
{
    if (total_data_len > data_len) {
        /* Fragmented message */
        if (current_data_offset == 0) {
            free(reassembly_buffer);
            reassembly_buffer = malloc(total_data_len + 1);
            if (!reassembly_buffer) {
                ESP_LOGE(TAG, "Reassembly alloc failed");
                return;
            }
        }
        memcpy(reassembly_buffer + current_data_offset, data, data_len);
        if (current_data_offset + data_len >= total_data_len) {
            reassembly_buffer[total_data_len] = '\0';
            handle_complete_message(topic, topic_len,
                                    reassembly_buffer, total_data_len);
            free(reassembly_buffer);
            reassembly_buffer = NULL;
        }
    } else {
        /* Complete message in single event */
        handle_complete_message(topic, topic_len, data, data_len);
    }
}
```

---

## TLS/SSL and Certificate-Based Security

### Server Certificate Verification

Embed the broker CA certificate into firmware using `EMBED_TXTFILES` in CMakeLists.txt:

```cmake
# main/CMakeLists.txt
idf_component_register(
    SRCS "main.c" "mqtt_handler.c"
    INCLUDE_DIRS "."
    EMBED_TXTFILES "certs/ca_cert.pem"
)
```

Reference the embedded certificate in code:

```c
extern const uint8_t ca_cert_pem_start[] asm("_binary_ca_cert_pem_start");
extern const uint8_t ca_cert_pem_end[]   asm("_binary_ca_cert_pem_end");

const esp_mqtt_client_config_t mqtt_cfg = {
    .broker = {
        .address = {
            .uri = "mqtts://broker.example.com:8883",
        },
        .verification = {
            .certificate = (const char *)ca_cert_pem_start,
            .certificate_len = ca_cert_pem_end - ca_cert_pem_start,
            .skip_cert_common_name_check = false,
        },
    },
};
```

### Mutual TLS (Client Certificate Authentication)

```c
extern const uint8_t client_cert_pem_start[] asm("_binary_client_cert_pem_start");
extern const uint8_t client_cert_pem_end[]   asm("_binary_client_cert_pem_end");
extern const uint8_t client_key_pem_start[]  asm("_binary_client_key_pem_start");
extern const uint8_t client_key_pem_end[]    asm("_binary_client_key_pem_end");

const esp_mqtt_client_config_t mqtt_cfg = {
    .broker = {
        .address = {
            .uri = "mqtts://broker.example.com:8883",
        },
        .verification = {
            .certificate = (const char *)ca_cert_pem_start,
        },
    },
    .credentials = {
        .authentication = {
            .certificate = (const char *)client_cert_pem_start,
            .certificate_len = client_cert_pem_end - client_cert_pem_start,
            .key = (const char *)client_key_pem_start,
            .key_len = client_key_pem_end - client_key_pem_start,
        },
    },
};
```

### Pre-Shared Key (PSK) Authentication

```c
static const psk_hint_key_t psk_hint = {
    .key = (const uint8_t *)"\x01\x02\x03\x04\x05\x06\x07\x08",
    .key_size = 8,
    .hint = "esp32_device",
};

const esp_mqtt_client_config_t mqtt_cfg = {
    .broker = {
        .address = {
            .uri = "mqtts://broker.example.com:8883",
        },
        .verification = {
            .psk_hint_key = &psk_hint,
        },
    },
};
```

Enable PSK support in menuconfig: `Component config -> ESP-TLS -> Enable PSK verification`.

---

## QoS Levels and Delivery Guarantees

### QoS 0 -- At Most Once (Fire and Forget)

No acknowledgment. Best for high-frequency sensor data where occasional loss is acceptable.

```c
/* QoS 0 - no msg_id tracking needed, returns -1 for msg_id */
esp_mqtt_client_publish(client, "sensors/temp", "22.5", 0, 0, 0);
```

### QoS 1 -- At Least Once

Broker acknowledges with PUBACK. Message may be delivered more than once. Use for commands and alerts.

```c
/* QoS 1 - returns positive msg_id, confirmed via MQTT_EVENT_PUBLISHED */
int msg_id = esp_mqtt_client_publish(client, "alerts/fire", payload, 0, 1, 0);
ESP_LOGI(TAG, "QoS1 publish msg_id=%d", msg_id);
```

### QoS 2 -- Exactly Once

Four-step handshake (PUBLISH, PUBREC, PUBREL, PUBCOMP). Highest overhead. Use for billing or critical state changes.

```c
/* QoS 2 - guaranteed exactly once delivery */
int msg_id = esp_mqtt_client_publish(client, "billing/meter",
                                      meter_json, 0, 2, 0);
```

### QoS Selection Guidelines

| Use Case | QoS | Reason |
|----------|-----|--------|
| Telemetry (temp, humidity) | 0 | High frequency, loss tolerable |
| Device commands | 1 | Must deliver, idempotent operations |
| OTA trigger | 1 | Must deliver, device retries naturally |
| Billing / metering | 2 | Exactly once critical |
| Status heartbeat | 0 | Frequent, stale data replaced |
| Alarm / alert | 1 | Must reach, duplicates acceptable |

---

## Topic Hierarchy Design for IoT

### Recommended Topic Structure

```
{org}/{site}/{area}/{device_type}/{device_id}/{data_type}
```

Example hierarchy:

```
acme/factory-a/line-1/sensor/sens-001/telemetry
acme/factory-a/line-1/sensor/sens-001/status
acme/factory-a/line-1/sensor/sens-001/commands
acme/factory-a/line-1/actuator/act-001/commands
acme/factory-a/line-1/actuator/act-001/status
```

### Wildcard Subscription Patterns

- `+` matches a single level: `acme/factory-a/+/sensor/+/telemetry`
- `#` matches all remaining levels: `acme/factory-a/#`

### Topic Design Rules

1. **Never start with `/`** -- creates an empty first level, wastes bytes
2. **Use lowercase with hyphens** -- consistent, URL-safe
3. **Keep topics short** -- each byte counts on constrained devices
4. **Separate commands from telemetry** -- different QoS and access control
5. **Include device ID** -- enables per-device subscriptions and ACLs
6. **Use `$SYS/`** only for broker-internal topics -- reserved by convention

---

## Last Will and Testament & Retained Messages

### Last Will and Testament (LWT)

The broker publishes the LWT message if the client disconnects ungracefully (network loss, crash).

Configure LWT in the session config:

```c
.session = {
    .last_will = {
        .topic = "devices/esp32_001/status",
        .msg = "{\"online\":false,\"reason\":\"unexpected\"}",
        .msg_len = 0,   /* 0 = use strlen */
        .qos = 1,
        .retain = true,
    },
},
```

### Birth / Death Pattern

Combine LWT with a retained birth message for reliable online/offline tracking:

1. Configure LWT with `retain = true` and payload `{"online": false}`
2. On `MQTT_EVENT_CONNECTED`, publish retained message `{"online": true}` to the same topic
3. On graceful shutdown, publish `{"online": false}` before calling `esp_mqtt_client_disconnect`

```c
/* On connect: publish birth message */
esp_mqtt_client_publish(client,
    "devices/esp32_001/status",
    "{\"online\":true}", 0, 1, 1);

/* On graceful shutdown */
void mqtt_graceful_shutdown(void)
{
    esp_mqtt_client_publish(mqtt_client,
        "devices/esp32_001/status",
        "{\"online\":false,\"reason\":\"shutdown\"}", 0, 1, 1);
    vTaskDelay(pdMS_TO_TICKS(500));  /* Allow publish to complete */
    esp_mqtt_client_disconnect(mqtt_client);
    esp_mqtt_client_destroy(mqtt_client);
    mqtt_client = NULL;
}
```

---

## Persistent Sessions and Message Buffering

### Clean Session vs Persistent Session

- **Clean session (default)**: Broker discards subscriptions and queued messages on disconnect. Set `disable_clean_session = false`.
- **Persistent session**: Broker remembers subscriptions and queues QoS 1/2 messages. Set `disable_clean_session = true`.

```c
.session = {
    .disable_clean_session = true,  /* persistent session */
},
.credentials = {
    .client_id = "esp32_device_01",  /* must be stable for persistent sessions */
},
```

### Outbox and Message Buffering

ESP-MQTT maintains an internal outbox for QoS 1/2 messages. Messages are stored until acknowledged.

Configure outbox behavior in menuconfig:

- `CONFIG_MQTT_OUTBOX_EXPIRED_TIMEOUT_MS` -- expiry time for outbox messages
- `CONFIG_MQTT_OUTBOX_DATA_LEN` -- maximum total outbox data size

### Checking Outbox Status

```c
/* Check if there are pending outbox messages before deep sleep */
if (esp_mqtt_client_get_outbox_size(mqtt_client) > 0) {
    ESP_LOGW(TAG, "Outbox has pending messages, delaying sleep");
    vTaskDelay(pdMS_TO_TICKS(2000));
}
```

### Session Present Flag

Check `event->session_present` in `MQTT_EVENT_CONNECTED` to determine if the broker restored a previous session:

```c
case MQTT_EVENT_CONNECTED:
    if (event->session_present) {
        ESP_LOGI(TAG, "Session restored, subscriptions active");
    } else {
        ESP_LOGI(TAG, "New session, re-subscribing");
        esp_mqtt_client_subscribe(client, "devices/+/commands", 1);
    }
    break;
```

---

## MQTT over WebSocket

Use WebSocket transport when direct MQTT ports (1883/8883) are blocked by firewalls or proxies.

### Basic WebSocket Configuration

```c
const esp_mqtt_client_config_t mqtt_cfg = {
    .broker = {
        .address = {
            .uri = "ws://broker.example.com:8080/mqtt",
        },
    },
};
```

### Secure WebSocket (WSS) with TLS

```c
const esp_mqtt_client_config_t mqtt_cfg = {
    .broker = {
        .address = {
            .uri = "wss://broker.example.com:443/mqtt",
        },
        .verification = {
            .certificate = (const char *)ca_cert_pem_start,
        },
    },
};
```

### WebSocket with Custom Headers

Some cloud brokers (AWS IoT, Azure IoT Hub) require authentication headers on the WebSocket upgrade request. Use `esp_mqtt_client_config_t` transport settings or custom implementation.

Enable WebSocket in menuconfig: `Component config -> ESP-MQTT -> Enable MQTT over Websocket`.

---

## JSON Payload Serialization with cJSON

### Building JSON Payloads

```c
#include "cJSON.h"

static char *build_telemetry_payload(float temperature, float humidity,
                                      uint32_t uptime_ms)
{
    cJSON *root = cJSON_CreateObject();
    if (!root) return NULL;

    cJSON_AddStringToObject(root, "device_id", "esp32_001");
    cJSON_AddNumberToObject(root, "temperature", temperature);
    cJSON_AddNumberToObject(root, "humidity", humidity);
    cJSON_AddNumberToObject(root, "uptime_ms", uptime_ms);
    cJSON_AddNumberToObject(root, "timestamp", (double)time(NULL));

    /* Use PrintUnformatted for smaller payloads on constrained devices */
    char *payload = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    return payload;  /* Caller must free() */
}

void publish_telemetry(esp_mqtt_client_handle_t client)
{
    float temp = read_temperature();
    float hum = read_humidity();
    uint32_t uptime = (uint32_t)(esp_timer_get_time() / 1000);

    char *payload = build_telemetry_payload(temp, hum, uptime);
    if (payload) {
        esp_mqtt_client_publish(client,
            "acme/site-a/line-1/sensor/esp32_001/telemetry",
            payload, 0, 0, 0);
        free(payload);
    }
}
```

### Parsing Incoming JSON Commands

```c
static void handle_command(const char *data, int data_len)
{
    /* cJSON_ParseWithLength is safer -- does not require null termination */
    cJSON *root = cJSON_ParseWithLength(data, data_len);
    if (!root) {
        ESP_LOGE(TAG, "JSON parse error: %s", cJSON_GetErrorPtr());
        return;
    }

    const cJSON *cmd = cJSON_GetObjectItemCaseSensitive(root, "command");
    if (cJSON_IsString(cmd) && cmd->valuestring != NULL) {
        if (strcmp(cmd->valuestring, "reboot") == 0) {
            ESP_LOGW(TAG, "Reboot command received");
            esp_restart();
        } else if (strcmp(cmd->valuestring, "set_interval") == 0) {
            const cJSON *val = cJSON_GetObjectItemCaseSensitive(root, "value");
            if (cJSON_IsNumber(val)) {
                set_reporting_interval((uint32_t)val->valuedouble);
            }
        }
    }

    cJSON_Delete(root);
}
```

### Pre-allocated Buffer Pattern

Avoid heap allocation for frequent telemetry by using `snprintf` for simple payloads:

```c
static void publish_fast_telemetry(esp_mqtt_client_handle_t client,
                                    float temp, float hum)
{
    char buf[128];
    int len = snprintf(buf, sizeof(buf),
        "{\"t\":%.1f,\"h\":%.1f,\"ts\":%lu}",
        temp, hum, (unsigned long)time(NULL));

    if (len > 0 && len < (int)sizeof(buf)) {
        esp_mqtt_client_publish(client,
            "s/esp32_001/t", buf, len, 0, 0);
    }
}
```

---

## Keep-Alive Tuning and Connection Backoff

### Keep-Alive Configuration

The keep-alive interval determines how often the client sends PINGREQ when idle. The broker disconnects if no message arrives within 1.5x the keep-alive period.

```c
.session = {
    .keepalive = 30,  /* seconds, default is 120 */
},
```

**Tuning guidelines:**

| Environment | Keep-Alive | Rationale |
|-------------|-----------|-----------|
| Stable Wi-Fi | 60-120s | Low overhead, adequate detection |
| Cellular/LTE | 30-60s | NAT timeout typically 30-120s |
| Battery device | 300-600s | Minimize radio wake-ups |
| Real-time control | 10-15s | Fast failure detection |

### Reconnection Backoff Strategy

ESP-MQTT reconnects automatically. Configure the base timeout:

```c
.network = {
    .reconnect_timeout_ms = 5000,  /* initial reconnect delay */
},
```

For custom exponential backoff, disable auto-reconnect and manage reconnection manually:

```c
.network = {
    .disable_auto_reconnect = true,
},
```

```c
static int backoff_ms = 1000;
static const int max_backoff_ms = 60000;

case MQTT_EVENT_DISCONNECTED:
    ESP_LOGW(TAG, "Disconnected, reconnecting in %d ms", backoff_ms);
    vTaskDelay(pdMS_TO_TICKS(backoff_ms));
    esp_mqtt_client_reconnect(client);
    backoff_ms = (backoff_ms * 2 > max_backoff_ms) ? max_backoff_ms : backoff_ms * 2;
    /* Add jitter */
    backoff_ms += (esp_random() % 1000);
    break;

case MQTT_EVENT_CONNECTED:
    backoff_ms = 1000;  /* Reset on successful connection */
    break;
```

---

## Payload Size Optimization

### Techniques for Reducing Payload Size

1. **Short JSON keys**: Use `t` instead of `temperature`, `h` instead of `humidity`
2. **Remove unnecessary precision**: `22.5` instead of `22.500000`
3. **Use arrays instead of objects**: `[22.5, 65.2, 1708900000]` vs `{"t":22.5,"h":65.2,"ts":1708900000}`
4. **Batch readings**: Send multiple samples in one message
5. **Binary encoding**: Use CBOR or MessagePack for minimum overhead
6. **Short topics**: Abbreviate topic segments where ACLs allow

### Batched Telemetry Example

```c
static void publish_batch(esp_mqtt_client_handle_t client,
                           const float *temps, const float *hums,
                           int count)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *t_arr = cJSON_AddArrayToObject(root, "t");
    cJSON *h_arr = cJSON_AddArrayToObject(root, "h");

    for (int i = 0; i < count; i++) {
        cJSON_AddItemToArray(t_arr, cJSON_CreateNumber(temps[i]));
        cJSON_AddItemToArray(h_arr, cJSON_CreateNumber(hums[i]));
    }

    cJSON_AddNumberToObject(root, "ts", (double)time(NULL));
    cJSON_AddNumberToObject(root, "n", count);

    char *payload = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);

    if (payload) {
        esp_mqtt_client_publish(client,
            "s/esp32_001/batch", payload, 0, 1, 0);
        free(payload);
    }
}
```

### MQTT Packet Overhead Reference

| Component | Bytes |
|-----------|-------|
| Fixed header | 2-5 |
| Topic (variable) | 2 + topic_length |
| Packet ID (QoS 1/2) | 2 |
| Payload | variable |

Keep total MQTT payload under the broker maximum (typically 256 KB for Mosquitto, 128 KB for AWS IoT Core).

---

## MQTT 5.0 Protocol Features

Enable MQTT 5.0 in the client config:

```c
.session = {
    .protocol_ver = MQTT_PROTOCOL_V_5,
},
```

### User Properties

MQTT 5.0 allows attaching key-value metadata to messages:

```c
esp_mqtt5_publish_data_t pub_data = {
    .payload_format_indicator = true,
    .content_type = "application/json",
};

/* Add user properties */
esp_mqtt5_client_set_user_property(&pub_data.user_property,
    "trace-id", "abc-123");
esp_mqtt5_client_set_user_property(&pub_data.user_property,
    "firmware-version", "1.2.0");

esp_mqtt5_client_set_publish_property(client, &pub_data);
esp_mqtt_client_publish(client, "telemetry/data", payload, 0, 1, 0);

esp_mqtt5_client_delete_user_property(pub_data.user_property);
```

### Topic Aliases

Reduce per-message overhead for frequently used topics. The broker and client negotiate maximum alias count.

### Reason Codes

MQTT 5.0 provides detailed reason codes on CONNACK, PUBACK, SUBACK, and DISCONNECT. Check `event->error_handle->connect_return_code` for diagnostic information.

### Session Expiry Interval

Control how long the broker retains session state after disconnect:

```c
esp_mqtt5_connection_property_config_t conn_props = {
    .session_expiry_interval = 3600,  /* 1 hour */
};
esp_mqtt5_client_set_connect_property(client, &conn_props);
```

---

## Best Practices

1. **Always set a Last Will and Testament** -- enables reliable online/offline detection without polling
2. **Use QoS 0 for telemetry, QoS 1 for commands** -- balance reliability against bandwidth and latency
3. **Use persistent sessions for intermittent connectivity** -- the broker queues messages while the device is offline
4. **Embed CA certificates in firmware** -- never skip server certificate verification in production
5. **Use `cJSON_PrintUnformatted`** -- saves 20-40% payload size compared to `cJSON_Print`
6. **Check outbox size before deep sleep** -- prevents losing unacknowledged QoS 1/2 messages
7. **Use `cJSON_ParseWithLength`** -- safer than `cJSON_Parse` as it does not require null-terminated input
8. **Keep topic names short** -- every byte is transmitted with every message, abbreviate where possible
9. **Set buffer sizes appropriately** -- `buffer.size` must accommodate the largest expected incoming message
10. **Use exponential backoff with jitter** -- prevents thundering herd on broker restart
11. **Publish birth message as retained** -- new subscribers immediately learn device status
12. **Separate telemetry from command topics** -- enables different QoS, ACLs, and processing pipelines
13. **Use `esp_mqtt_client_enqueue`** -- for publishing from ISR context or when the client is disconnected (messages queued in outbox)
14. **Monitor free heap around MQTT operations** -- cJSON and MQTT buffers can exhaust memory on constrained devices
15. **Set task stack size to at least 6 KB** -- TLS handshakes require significant stack space

---

## Anti-Patterns

1. **Using QoS 2 for telemetry** -- excessive overhead for data that is immediately replaced by the next reading
2. **Subscribing to `#` (root wildcard)** -- floods the device with every message on the broker, overwhelming RAM
3. **Blocking in the event handler** -- the MQTT task is single-threaded; long processing stalls all MQTT operations
4. **Using `cJSON_Print` (formatted) in production** -- wastes bandwidth with whitespace on constrained links
5. **Hardcoding broker IP instead of hostname** -- breaks when the broker IP changes; use mDNS or DNS
6. **Skipping TLS in production** -- MQTT credentials and payloads are transmitted in plaintext over TCP
7. **Ignoring `session_present` on connect** -- leads to duplicate subscriptions or missed messages
8. **Not freeing cJSON objects** -- every `cJSON_Create*` and `cJSON_Parse*` must be matched with `cJSON_Delete`
9. **Publishing large payloads without checking buffer size** -- messages silently fail or get truncated
10. **Using clean session with QoS 1 commands** -- commands sent while offline are discarded by the broker
11. **Setting keep-alive too low** -- causes unnecessary PINGREQ traffic and false disconnects on slow networks
12. **Using the same client_id on multiple devices** -- the broker disconnects the first client when the second connects

---

## Sources & References

- [ESP-MQTT Official Documentation (ESP-IDF)](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/mqtt.html)
- [ESP-MQTT GitHub Source (espressif/esp-mqtt)](https://github.com/espressif/esp-mqtt)
- [MQTT 3.1.1 OASIS Standard](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html)
- [MQTT 5.0 OASIS Standard](https://docs.oasis-open.org/mqtt/mqtt/v5.0/os/mqtt-v5.0-os.html)
- [cJSON Library GitHub Repository](https://github.com/DaveGamble/cJSON)
- [Eclipse Mosquitto MQTT Broker](https://mosquitto.org/documentation/)
- [HiveMQ MQTT Essentials Guide](https://www.hivemq.com/mqtt-essentials/)
- [ESP-IDF Programming Guide -- ESP-TLS](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/esp_tls.html)
- [AWS IoT Core MQTT Topics Best Practices](https://docs.aws.amazon.com/whitepapers/latest/designing-mqtt-topics-aws-iot-core/designing-mqtt-topics-aws-iot-core.html)
