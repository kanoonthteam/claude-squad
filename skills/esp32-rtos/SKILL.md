---
name: esp32-rtos
description: FreeRTOS on ESP32 — task management, inter-task communication, synchronization primitives, dual-core pinning, memory management, and watchdog timers
---

# FreeRTOS on ESP32

Comprehensive reference for FreeRTOS programming on ESP32 using the ESP-IDF framework. Covers task creation and lifecycle, scheduling on dual cores, queues, semaphores, mutexes, event groups, task notifications, software timers, watchdog timers, memory management, and stack overflow detection. All examples target ESP-IDF v5.x with FreeRTOS SMP (Symmetric Multiprocessing) support.

## Table of Contents

1. [Task Creation and Lifecycle](#task-creation-and-lifecycle)
2. [Task Priorities and Scheduling](#task-priorities-and-scheduling)
3. [Dual-Core Task Pinning](#dual-core-task-pinning)
4. [Queues and Inter-Task Communication](#queues-and-inter-task-communication)
5. [Semaphores](#semaphores)
6. [Mutexes and Priority Inversion](#mutexes-and-priority-inversion)
7. [Event Groups](#event-groups)
8. [Task Notifications](#task-notifications)
9. [Software Timers](#software-timers)
10. [Watchdog Timers](#watchdog-timers)
11. [Critical Sections and ISR-Safe APIs](#critical-sections-and-isr-safe-apis)
12. [Memory Management and Heap Strategies](#memory-management-and-heap-strategies)
13. [Stack Overflow Detection and Sizing](#stack-overflow-detection-and-sizing)
14. [FreeRTOS Configuration in sdkconfig](#freertos-configuration-in-sdkconfig)
15. [Idle Task Hooks](#idle-task-hooks)
16. [Best Practices](#best-practices)
17. [Anti-Patterns](#anti-patterns)
18. [Sources & References](#sources--references)

---

## Task Creation and Lifecycle

FreeRTOS tasks are the fundamental execution units. ESP-IDF supports both dynamic and static task creation. Dynamic allocation uses the FreeRTOS heap; static allocation uses caller-provided buffers.

### Dynamic Task Creation

The most common approach. FreeRTOS allocates the Task Control Block (TCB) and stack from the heap.

```c
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

static const char *TAG = "task_demo";

// Task function signature: void func(void *pvParameters)
void sensor_read_task(void *pvParameters) {
    int sensor_id = (int)pvParameters;

    // Task loop — tasks must never return
    for (;;) {
        ESP_LOGI(TAG, "Reading sensor %d", sensor_id);
        // ... perform sensor read ...

        // Yield CPU for 1000ms
        vTaskDelay(pdMS_TO_TICKS(1000));
    }

    // If a task must exit, delete itself
    vTaskDelete(NULL);
}

void app_main(void) {
    TaskHandle_t sensor_handle = NULL;

    BaseType_t ret = xTaskCreate(
        sensor_read_task,       // Task function
        "sensor_read",          // Name (max 16 chars by default)
        4096,                   // Stack size in bytes (ESP-IDF uses bytes, not words)
        (void *)1,              // Parameter passed to task
        5,                      // Priority (0 = lowest, configMAX_PRIORITIES - 1 = highest)
        &sensor_handle          // Output handle (can be NULL if not needed)
    );

    if (ret != pdPASS) {
        ESP_LOGE(TAG, "Failed to create sensor task");
    }

    // Later, to delete from outside:
    // vTaskDelete(sensor_handle);
}
```

### Static Task Creation

Static allocation avoids heap fragmentation and guarantees memory availability at compile time. The caller provides the stack buffer and the StaticTask_t structure.

```c
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#define STACK_SIZE 4096

// Statically allocated stack and TCB
static StackType_t task_stack[STACK_SIZE / sizeof(StackType_t)];
static StaticTask_t task_tcb;

void worker_task(void *pvParameters) {
    for (;;) {
        // ... do work ...
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void app_main(void) {
    TaskHandle_t handle = xTaskCreateStatic(
        worker_task,            // Task function
        "worker",               // Name
        STACK_SIZE / sizeof(StackType_t),  // Stack depth in words
        NULL,                   // Parameter
        5,                      // Priority
        task_stack,             // Stack buffer
        &task_tcb               // TCB buffer
    );

    // xTaskCreateStatic always succeeds (returns non-NULL)
    // unless the arguments are invalid
    assert(handle != NULL);
}
```

### Task Lifecycle States

Tasks in FreeRTOS exist in one of four states:

- **Running** - Currently executing on a CPU core
- **Ready** - Able to run but waiting for a core to become available
- **Blocked** - Waiting for an event (delay, queue, semaphore, notification)
- **Suspended** - Explicitly suspended via `vTaskSuspend()`; resumed with `vTaskResume()`

Use `vTaskSuspend(handle)` and `vTaskResume(handle)` sparingly. Prefer blocking on a synchronization primitive so the scheduler can manage timing.

### Task Deletion

Deleting a task frees its TCB and stack (for dynamic tasks). The idle task performs the actual memory reclamation, so the idle task must get CPU time.

- `vTaskDelete(NULL)` - delete the calling task
- `vTaskDelete(handle)` - delete another task

---

## Task Priorities and Scheduling

ESP-IDF FreeRTOS uses preemptive priority-based scheduling with optional time-slicing. Higher numeric values mean higher priority.

### Priority Levels

- **0** - Idle task priority (`tskIDLE_PRIORITY`). Reserved for the idle task and very low priority background work.
- **1** - Lowest application priority. Suitable for logging, telemetry.
- **5** - Mid-range. Suitable for periodic sensor reads, communication tasks.
- **10-15** - High priority. Suitable for control loops, safety-critical logic.
- **configMAX_PRIORITIES - 1** - Maximum. Default is 25 in ESP-IDF. Use only for hard-deadline tasks.

### Scheduling Behavior

- **Preemptive**: A higher-priority task that becomes ready will immediately preempt a lower-priority running task.
- **Time-slicing**: Tasks of equal priority share CPU time in round-robin fashion when `configUSE_TIME_SLICING` is enabled (default).
- **Dual-core**: ESP32 has two cores (PRO_CPU = core 0, APP_CPU = core 1). The scheduler runs independently on each core.

### Changing Priority at Runtime

```c
// Get current priority
UBaseType_t prio = uxTaskPriorityGet(task_handle);

// Set new priority (triggers reschedule if needed)
vTaskPrioritySet(task_handle, 10);
```

---

## Dual-Core Task Pinning

The ESP32 has two Xtensa LX6 cores. By default, `xTaskCreate` lets the scheduler assign tasks to any core. Use `xTaskCreatePinnedToCore` to bind a task to a specific core.

### Core Affinity

- **`tskNO_AFFINITY`** - Task can run on any core (default for `xTaskCreate`)
- **`0` (PRO_CPU)** - Core 0, typically handles Wi-Fi/BT protocol stack
- **`1` (APP_CPU)** - Core 1, preferred for application tasks

### Pinned Task Creation

```c
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

static const char *TAG = "pinned";

void control_loop_task(void *pvParameters) {
    for (;;) {
        // Tight control loop on dedicated core
        // ... read sensor, compute PID, write actuator ...
        vTaskDelay(pdMS_TO_TICKS(10));  // 100 Hz loop
    }
}

void comms_task(void *pvParameters) {
    for (;;) {
        // Handle MQTT / HTTP on core 0 alongside Wi-Fi stack
        // ... publish telemetry ...
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}

void app_main(void) {
    // Pin control loop to APP_CPU (core 1) to avoid Wi-Fi jitter
    xTaskCreatePinnedToCore(
        control_loop_task,
        "control_loop",
        4096,
        NULL,
        10,             // High priority
        NULL,
        1               // APP_CPU
    );

    // Pin comms to PRO_CPU (core 0) where Wi-Fi runs
    xTaskCreatePinnedToCore(
        comms_task,
        "comms",
        8192,           // Larger stack for TLS/HTTP
        NULL,
        5,
        NULL,
        0               // PRO_CPU
    );
}
```

### When to Pin Tasks

- **Pin to core 1**: Real-time control loops, timing-sensitive tasks, tasks that must not be interrupted by Wi-Fi/BT ISRs.
- **Pin to core 0**: Tasks that interact heavily with the Wi-Fi/BT stack (reduces cross-core cache thrashing).
- **No affinity**: General-purpose tasks where latency is not critical. Allows better load balancing.

---

## Queues and Inter-Task Communication

Queues are the primary mechanism for passing data between tasks (and from ISRs to tasks). They are thread-safe FIFO buffers.

### Queue Creation and Usage

```c
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "esp_log.h"

static const char *TAG = "queue_demo";

typedef struct {
    int sensor_id;
    float value;
    uint32_t timestamp;
} sensor_data_t;

static QueueHandle_t sensor_queue;

void producer_task(void *pvParameters) {
    sensor_data_t data;
    for (;;) {
        data.sensor_id = 1;
        data.value = 23.5f;  // simulated reading
        data.timestamp = xTaskGetTickCount();

        // Send to queue; block up to 100ms if queue is full
        if (xQueueSend(sensor_queue, &data, pdMS_TO_TICKS(100)) != pdPASS) {
            ESP_LOGW(TAG, "Queue full, dropping reading");
        }

        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

void consumer_task(void *pvParameters) {
    sensor_data_t received;
    for (;;) {
        // Block indefinitely until data is available
        if (xQueueReceive(sensor_queue, &received, portMAX_DELAY) == pdPASS) {
            ESP_LOGI(TAG, "Sensor %d: %.1f at tick %lu",
                     received.sensor_id, received.value,
                     (unsigned long)received.timestamp);
        }
    }
}

void app_main(void) {
    // Create queue: 10 items, each sizeof(sensor_data_t)
    sensor_queue = xQueueCreate(10, sizeof(sensor_data_t));
    assert(sensor_queue != NULL);

    xTaskCreate(producer_task, "producer", 4096, NULL, 5, NULL);
    xTaskCreate(consumer_task, "consumer", 4096, NULL, 6, NULL);
}
```

### Queue Variants

- **`xQueueSend` / `xQueueSendToBack`** - Add item to the back (FIFO)
- **`xQueueSendToFront`** - Add item to the front (LIFO behavior)
- **`xQueueOverwrite`** - Overwrite the item in a length-1 queue (mailbox pattern)
- **`xQueuePeek`** - Read without removing the item
- **`xQueueReset`** - Empty the queue

### Queue Sets

Queue sets allow a task to block on multiple queues simultaneously.

```c
QueueSetHandle_t queue_set = xQueueCreateSet(QUEUE1_LEN + QUEUE2_LEN);
xQueueAddToSet(queue1, queue_set);
xQueueAddToSet(queue2, queue_set);

// Block until any queue in the set has data
QueueSetMemberHandle_t active = xQueueSelectFromSet(queue_set, portMAX_DELAY);
if (active == queue1) {
    xQueueReceive(queue1, &data1, 0);
} else if (active == queue2) {
    xQueueReceive(queue2, &data2, 0);
}
```

---

## Semaphores

Semaphores are lightweight synchronization primitives. ESP-IDF provides binary and counting semaphores.

### Binary Semaphore

Used for task synchronization (signaling). A binary semaphore is either available (1) or not (0).

```c
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static SemaphoreHandle_t data_ready_sem;

// ISR signals that data is ready
void IRAM_ATTR gpio_isr_handler(void *arg) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    xSemaphoreGiveFromISR(data_ready_sem, &xHigherPriorityTaskWoken);
    if (xHigherPriorityTaskWoken) {
        portYIELD_FROM_ISR();
    }
}

void processing_task(void *pvParameters) {
    for (;;) {
        // Block until ISR signals data ready
        if (xSemaphoreTake(data_ready_sem, portMAX_DELAY) == pdTRUE) {
            // Process the data
        }
    }
}

void app_main(void) {
    data_ready_sem = xSemaphoreCreateBinary();
    // Binary semaphores start as "empty" (not available)
    // Must be given before first take succeeds

    xTaskCreate(processing_task, "process", 4096, NULL, 10, NULL);
    // ... configure GPIO ISR ...
}
```

### Counting Semaphore

Used when multiple resources are available or when counting events is needed.

```c
// Create counting semaphore: max count = 5, initial count = 5
SemaphoreHandle_t pool_sem = xSemaphoreCreateCounting(5, 5);

// Acquire one resource from pool (blocks if count == 0)
if (xSemaphoreTake(pool_sem, pdMS_TO_TICKS(1000)) == pdTRUE) {
    // ... use resource ...

    // Release resource back to pool
    xSemaphoreGive(pool_sem);
}
```

### Key Differences

| Feature | Binary Semaphore | Counting Semaphore | Mutex |
|---------|------------------|--------------------|-------|
| Max count | 1 | Configurable | 1 |
| Priority inheritance | No | No | Yes |
| Ownership | None | None | Owner task |
| ISR give | Yes | Yes | No |
| Use case | Signaling | Resource pools | Mutual exclusion |

---

## Mutexes and Priority Inversion

Mutexes provide mutual exclusion with priority inheritance. Unlike semaphores, mutexes have an "owner" and support priority inheritance to prevent priority inversion.

### Standard Mutex

```c
static SemaphoreHandle_t spi_mutex;

void init_spi_mutex(void) {
    spi_mutex = xSemaphoreCreateMutex();
    assert(spi_mutex != NULL);
}

void spi_transfer(uint8_t *data, size_t len) {
    // Acquire mutex before accessing shared SPI bus
    if (xSemaphoreTake(spi_mutex, pdMS_TO_TICKS(500)) == pdTRUE) {
        // ... perform SPI transaction ...

        // Always release the mutex
        xSemaphoreGive(spi_mutex);
    } else {
        ESP_LOGE(TAG, "Failed to acquire SPI mutex within timeout");
    }
}
```

### Recursive Mutex

A recursive mutex can be taken multiple times by the same task. It must be given the same number of times before it becomes available to other tasks. Use when a function that holds the mutex calls another function that also needs the mutex.

```c
static SemaphoreHandle_t recursive_mutex;

void init_recursive_mutex(void) {
    recursive_mutex = xSemaphoreCreateRecursiveMutex();
}

void outer_function(void) {
    if (xSemaphoreTakeRecursive(recursive_mutex, portMAX_DELAY) == pdTRUE) {
        // ... do work ...
        inner_function();  // This also takes the same mutex
        xSemaphoreGiveRecursive(recursive_mutex);
    }
}

void inner_function(void) {
    if (xSemaphoreTakeRecursive(recursive_mutex, portMAX_DELAY) == pdTRUE) {
        // ... do work ...
        xSemaphoreGiveRecursive(recursive_mutex);
    }
}
```

### Priority Inversion and Inheritance

**Priority inversion** occurs when a high-priority task is blocked waiting for a mutex held by a low-priority task, while a medium-priority task preempts the low-priority task. This causes the high-priority task to be indirectly blocked by the medium-priority task.

**Priority inheritance** (built into FreeRTOS mutexes) temporarily raises the mutex holder's priority to match the highest-priority task waiting for the mutex. This prevents unbounded priority inversion.

- Standard mutexes: single level of priority inheritance
- Recursive mutexes: also support priority inheritance
- Binary semaphores: do NOT support priority inheritance. Never use them for mutual exclusion.

---

## Event Groups

Event groups allow tasks to wait for a combination of events (bits). Each event group has 24 usable bits (8 bits reserved by FreeRTOS internally on ESP32).

### Event Group Usage

```c
#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"

#define WIFI_CONNECTED_BIT  BIT0
#define MQTT_CONNECTED_BIT  BIT1
#define NTP_SYNCED_BIT      BIT2

static EventGroupHandle_t system_events;

void wifi_task(void *pvParameters) {
    // ... connect to WiFi ...
    xEventGroupSetBits(system_events, WIFI_CONNECTED_BIT);
    // ...
}

void mqtt_task(void *pvParameters) {
    // Wait for WiFi before attempting MQTT
    xEventGroupWaitBits(
        system_events,
        WIFI_CONNECTED_BIT,     // Bits to wait for
        pdFALSE,                // Don't clear bits on exit
        pdTRUE,                 // Wait for ALL specified bits
        portMAX_DELAY           // Wait indefinitely
    );

    // WiFi is connected, now connect MQTT
    // ...
    xEventGroupSetBits(system_events, MQTT_CONNECTED_BIT);
}

void main_task(void *pvParameters) {
    // Wait for ALL subsystems to be ready
    EventBits_t bits = xEventGroupWaitBits(
        system_events,
        WIFI_CONNECTED_BIT | MQTT_CONNECTED_BIT | NTP_SYNCED_BIT,
        pdFALSE,                // Don't clear
        pdTRUE,                 // Wait for ALL bits
        pdMS_TO_TICKS(30000)    // 30 second timeout
    );

    if ((bits & (WIFI_CONNECTED_BIT | MQTT_CONNECTED_BIT | NTP_SYNCED_BIT)) ==
        (WIFI_CONNECTED_BIT | MQTT_CONNECTED_BIT | NTP_SYNCED_BIT)) {
        ESP_LOGI(TAG, "All subsystems ready");
    } else {
        ESP_LOGE(TAG, "Subsystem initialization timeout");
    }
}

void app_main(void) {
    system_events = xEventGroupCreate();
    assert(system_events != NULL);

    xTaskCreate(wifi_task, "wifi", 4096, NULL, 5, NULL);
    xTaskCreate(mqtt_task, "mqtt", 4096, NULL, 5, NULL);
    xTaskCreate(main_task, "main_ctrl", 4096, NULL, 3, NULL);
}
```

### Synchronization with Event Groups

`xEventGroupSync` allows multiple tasks to synchronize at a rendezvous point. Each task sets its bit and waits for all bits to be set.

```c
#define TASK_A_BIT BIT0
#define TASK_B_BIT BIT1
#define ALL_SYNC_BITS (TASK_A_BIT | TASK_B_BIT)

void task_a(void *pvParameters) {
    // Do initialization work...

    // Signal ready and wait for all tasks
    xEventGroupSync(system_events, TASK_A_BIT, ALL_SYNC_BITS, portMAX_DELAY);

    // All tasks have reached this point
}
```

---

## Task Notifications

Task notifications are a lightweight alternative to queues and semaphores for direct task-to-task communication. Each task has a built-in 32-bit notification value. They are faster and use less RAM than queues or semaphores.

### Notification as Binary Semaphore

```c
static TaskHandle_t worker_handle;

void isr_handler(void *arg) {
    BaseType_t xHigherPriorityTaskWoken = pdFALSE;
    vTaskNotifyGiveFromISR(worker_handle, &xHigherPriorityTaskWoken);
    portYIELD_FROM_ISR(xHigherPriorityTaskWoken);
}

void worker_task(void *pvParameters) {
    for (;;) {
        // Block until notified; clears notification count on exit
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        // ... handle event ...
    }
}
```

### Notification with Value

```c
// Sender: set specific bits
xTaskNotify(target_handle, 0x01, eSetBits);

// Receiver: wait for and read notification value
uint32_t notification_value;
if (xTaskNotifyWait(
        0x00,           // Bits to clear on entry
        ULONG_MAX,      // Bits to clear on exit (clear all)
        &notification_value,
        portMAX_DELAY
    ) == pdTRUE) {
    if (notification_value & 0x01) {
        // Handle bit 0 event
    }
}
```

### Notification Actions

- **`eNoAction`** - Notify without updating the value
- **`eSetBits`** - OR bits into the notification value
- **`eIncrement`** - Increment the notification value (counting semaphore behavior)
- **`eSetValueWithOverwrite`** - Set the value, overwriting any pending notification
- **`eSetValueWithoutOverwrite`** - Set the value only if no notification is pending

### Limitations

- Only one notification per task (ESP-IDF v5.x adds indexed notifications with `configTASK_NOTIFICATION_ARRAY_ENTRIES`)
- Only one task can wait on a notification (no broadcast)
- Cannot be used from ISR to receive (only to send)

---

## Software Timers

Software timers execute a callback function at a specified time in the future, either once (one-shot) or periodically (auto-reload). Timer callbacks run in the context of the timer service task (daemon task).

### Timer Creation

```c
#include "freertos/FreeRTOS.h"
#include "freertos/timers.h"

// Timer callback — runs in timer task context, keep it short
void heartbeat_callback(TimerHandle_t xTimer) {
    ESP_LOGI(TAG, "Heartbeat tick");
    // Do NOT block in timer callbacks (no vTaskDelay, no mutex take with timeout)
}

void telemetry_callback(TimerHandle_t xTimer) {
    // Retrieve timer ID to identify which timer fired
    int timer_id = (int)pvTimerGetTimerID(xTimer);
    ESP_LOGI(TAG, "Telemetry timer %d fired", timer_id);
}

void app_main(void) {
    // Auto-reload timer: fires every 5 seconds
    TimerHandle_t heartbeat_timer = xTimerCreate(
        "heartbeat",                // Name
        pdMS_TO_TICKS(5000),        // Period
        pdTRUE,                     // Auto-reload (pdTRUE) vs one-shot (pdFALSE)
        (void *)0,                  // Timer ID
        heartbeat_callback          // Callback
    );

    // One-shot timer: fires once after 10 seconds
    TimerHandle_t oneshot_timer = xTimerCreate(
        "oneshot",
        pdMS_TO_TICKS(10000),
        pdFALSE,                    // One-shot
        (void *)1,
        telemetry_callback
    );

    // Start timers (commands are queued to the timer task)
    xTimerStart(heartbeat_timer, portMAX_DELAY);
    xTimerStart(oneshot_timer, portMAX_DELAY);

    // Change period at runtime
    xTimerChangePeriod(heartbeat_timer, pdMS_TO_TICKS(2000), portMAX_DELAY);

    // Stop a timer
    // xTimerStop(heartbeat_timer, portMAX_DELAY);

    // Reset a timer (restart the period from now)
    // xTimerReset(heartbeat_timer, portMAX_DELAY);
}
```

### Timer Task Configuration

The timer service task (daemon) processes all timer commands and callbacks. Configure via sdkconfig:

- `CONFIG_FREERTOS_TIMER_TASK_PRIORITY` - Default is 1. Raise if timer callbacks need timely execution.
- `CONFIG_FREERTOS_TIMER_TASK_STACK_DEPTH` - Default is 2048. Increase if callbacks do heavy work.
- `CONFIG_FREERTOS_TIMER_QUEUE_LENGTH` - Default is 10. Increase if many timers start/stop simultaneously.

---

## Watchdog Timers

ESP-IDF provides Task Watchdog Timer (TWDT) to detect tasks that run too long without yielding, and the Interrupt Watchdog Timer (IWDT) to detect ISRs that take too long.

### Task Watchdog Timer (TWDT)

The TWDT monitors subscribed tasks and triggers a panic (or callback) if a task fails to reset the watchdog within the timeout period.

```c
#include "esp_task_wdt.h"

void monitored_task(void *pvParameters) {
    // Subscribe this task to the TWDT
    esp_task_wdt_add(NULL);  // NULL = current task

    for (;;) {
        // ... do work ...

        // Reset (feed) the watchdog — must be called within the timeout period
        esp_task_wdt_reset();

        vTaskDelay(pdMS_TO_TICKS(100));
    }

    // Unsubscribe before deleting (if the task ever exits)
    esp_task_wdt_delete(NULL);
}
```

### TWDT Configuration

- `CONFIG_ESP_TASK_WDT_EN` - Enable/disable TWDT
- `CONFIG_ESP_TASK_WDT_TIMEOUT_S` - Timeout in seconds (default 5)
- `CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU0` - Watch idle task on core 0
- `CONFIG_ESP_TASK_WDT_CHECK_IDLE_TASK_CPU1` - Watch idle task on core 1
- `CONFIG_ESP_TASK_WDT_PANIC` - Trigger panic on timeout (vs. just printing warning)

### Interrupt Watchdog Timer (IWDT)

The IWDT ensures that ISRs and critical sections do not run for too long. It is configured separately and should rarely be disabled.

- `CONFIG_ESP_INT_WDT` - Enable/disable IWDT
- `CONFIG_ESP_INT_WDT_TIMEOUT_MS` - Timeout in milliseconds (default 300)

---

## Critical Sections and ISR-Safe APIs

### Critical Sections with portMUX

On the dual-core ESP32, `taskENTER_CRITICAL` / `taskEXIT_CRITICAL` use a spinlock (portMUX_TYPE) to ensure mutual exclusion across both cores. This disables interrupts on the current core and spins on the other core if the lock is held.

```c
static portMUX_TYPE my_spinlock = portMUX_INITIALIZER_UNLOCKED;

void update_shared_counter(void) {
    taskENTER_CRITICAL(&my_spinlock);
    // Interrupts disabled on this core; other core spins if it tries to enter
    shared_counter++;
    taskEXIT_CRITICAL(&my_spinlock);
}

// ISR-safe version (call from within an ISR)
void IRAM_ATTR my_isr_handler(void *arg) {
    taskENTER_CRITICAL_ISR(&my_spinlock);
    shared_counter++;
    taskEXIT_CRITICAL_ISR(&my_spinlock);
}
```

### ISR-Safe API Variants

FreeRTOS provides `FromISR` variants of most API functions for use inside interrupt service routines. These never block and use `BaseType_t *pxHigherPriorityTaskWoken` to signal if a context switch is needed.

| Task API | ISR-Safe Variant |
|----------|-----------------|
| `xQueueSend` | `xQueueSendFromISR` |
| `xQueueReceive` | `xQueueReceiveFromISR` |
| `xSemaphoreGive` | `xSemaphoreGiveFromISR` |
| `xEventGroupSetBits` | `xEventGroupSetBitsFromISR` |
| `xTaskNotifyGive` | `vTaskNotifyGiveFromISR` |
| `xTimerStart` | `xTimerStartFromISR` |

### ISR Best Practices

- Keep ISR handlers short. Defer heavy processing to a task via semaphore or queue.
- Always check `xHigherPriorityTaskWoken` and call `portYIELD_FROM_ISR()` if needed.
- ISR handler functions must be placed in IRAM using the `IRAM_ATTR` attribute.
- Never call blocking APIs (`vTaskDelay`, `xSemaphoreTake` with timeout) from an ISR.

---

## Memory Management and Heap Strategies

ESP32 has multiple memory types with different capabilities. ESP-IDF extends FreeRTOS heap management with capability-based allocation.

### Memory Types

| Memory | Speed | DMA-capable | Size (ESP32) |
|--------|-------|-------------|--------------|
| DRAM (Internal) | Fast | Yes | ~520 KB total |
| IRAM (Internal) | Fast | No | ~200 KB total |
| PSRAM (External) | Slower | No (SPI) | 4-8 MB (if equipped) |
| RTC memory | Slow | No | 8 KB (persists in deep sleep) |

### Capability-Based Allocation

```c
#include "esp_heap_caps.h"

// Allocate from internal DRAM (default malloc behavior)
void *buf1 = heap_caps_malloc(1024, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);

// Allocate DMA-capable memory
void *dma_buf = heap_caps_malloc(4096, MALLOC_CAP_DMA);

// Allocate from PSRAM (external SPI RAM)
void *large_buf = heap_caps_malloc(100000, MALLOC_CAP_SPIRAM);

// Allocate with preference: try internal first, fall back to PSRAM
void *flex_buf = heap_caps_malloc_prefer(8192,
    2,  // number of caps sets
    MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT,
    MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT
);

// Check available memory
size_t free_internal = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
size_t free_psram = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
size_t min_ever_free = heap_caps_get_minimum_free_size(MALLOC_CAP_DEFAULT);

ESP_LOGI(TAG, "Free internal: %d, Free PSRAM: %d, Min ever free: %d",
         free_internal, free_psram, min_ever_free);
```

### FreeRTOS Task Stack Allocation from PSRAM

To allocate task stacks from PSRAM (useful when internal RAM is scarce):

```c
// Enable in sdkconfig: CONFIG_SPIRAM_ALLOW_STACK_EXTERNAL_MEMORY=y

// Then use xTaskCreatePinnedToCore with a stack allocated from PSRAM
StaticTask_t *task_tcb = heap_caps_malloc(sizeof(StaticTask_t), MALLOC_CAP_SPIRAM);
StackType_t *task_stack = heap_caps_malloc(8192, MALLOC_CAP_SPIRAM);

xTaskCreateStatic(my_task, "psram_task", 8192 / sizeof(StackType_t),
                  NULL, 5, task_stack, task_tcb);
```

### Heap Debugging

- `heap_caps_check_integrity_all(true)` - Check heap integrity (use in development)
- `heap_caps_dump_all()` - Dump all heap block information
- Enable `CONFIG_HEAP_TRACING_STANDALONE` in sdkconfig for heap leak detection

---

## Stack Overflow Detection and Sizing

### Stack Overflow Detection

FreeRTOS provides two methods for detecting stack overflow, configured via `CONFIG_FREERTOS_CHECK_STACKOVERFLOW`:

- **Method 1**: Checks if the stack pointer has gone past the stack boundary when the task is swapped out. Fast but can miss overflows that occur between context switches.
- **Method 2** (recommended): Fills the stack with a known pattern (0xa5) at creation and checks the last 16 bytes for corruption at context switch. More reliable but slightly slower.

The overflow hook function is called when an overflow is detected:

```c
void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    ESP_LOGE("STACK", "Stack overflow in task: %s", pcTaskName);
    // In production, consider triggering a controlled restart
    esp_system_abort("Stack overflow detected");
}
```

### Stack Sizing Guidelines

Use `uxTaskGetStackHighWaterMark()` to measure actual stack usage at runtime:

```c
void my_task(void *pvParameters) {
    for (;;) {
        // ... do work ...

        UBaseType_t high_water = uxTaskGetStackHighWaterMark(NULL);
        ESP_LOGI(TAG, "Stack high water mark: %u bytes remaining",
                 (unsigned int)(high_water * sizeof(StackType_t)));

        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
```

### Recommended Stack Sizes

| Task Type | Minimum Stack | Recommended |
|-----------|--------------|-------------|
| Simple periodic task | 2048 | 3072-4096 |
| Task using ESP_LOG | 3072 | 4096 |
| HTTP/MQTT client task | 6144 | 8192 |
| TLS/SSL connections | 8192 | 10240-12288 |
| JSON parsing (large) | 4096 | 8192+ |
| Task calling sprintf/snprintf | 3072 | 4096 |

Always add at least 512 bytes of headroom above the measured high water mark.

---

## FreeRTOS Configuration in sdkconfig

Key FreeRTOS configuration options set via `idf.py menuconfig` under "Component config > FreeRTOS":

### Task Configuration

- `CONFIG_FREERTOS_MAX_TASK_NAME_LEN` - Maximum task name length (default 16)
- `CONFIG_FREERTOS_TASK_NOTIFICATION_ARRAY_ENTRIES` - Number of notification slots per task (default 1, max 5 in ESP-IDF v5.x)
- `CONFIG_FREERTOS_IDLE_TASK_STACKSIZE` - Idle task stack size (default 1536)
- `CONFIG_FREERTOS_ISR_STACKSIZE` - ISR stack size (default 1536)

### Scheduling

- `CONFIG_FREERTOS_HZ` - Tick rate in Hz (default 100, set to 1000 for finer timing)
- `CONFIG_FREERTOS_MAX_PRIORITIES` - Maximum priority levels (default 25)
- `CONFIG_FREERTOS_USE_TIME_SLICING` - Enable round-robin for equal-priority tasks (default enabled)
- `CONFIG_FREERTOS_OPTIMIZED_SCHEDULER` - Use optimized priority-bitmap scheduler (default enabled)

### Debugging

- `CONFIG_FREERTOS_CHECK_STACKOVERFLOW` - Stack overflow detection: None / Method 1 / Method 2
- `CONFIG_FREERTOS_GENERATE_RUN_TIME_STATS` - Enable runtime statistics collection
- `CONFIG_FREERTOS_USE_TRACE_FACILITY` - Enable trace facility for vTaskList and vTaskGetRunTimeStats
- `CONFIG_FREERTOS_VTASKLIST_INCLUDE_COREID` - Include core ID in vTaskList output

### Timer Configuration

- `CONFIG_FREERTOS_TIMER_TASK_PRIORITY` - Timer daemon task priority (default 1)
- `CONFIG_FREERTOS_TIMER_TASK_STACK_DEPTH` - Timer daemon stack size (default 2048)
- `CONFIG_FREERTOS_TIMER_QUEUE_LENGTH` - Timer command queue length (default 10)

### Memory

- `CONFIG_FREERTOS_SUPPORT_STATIC_ALLOCATION` - Enable static task/queue/semaphore creation
- `CONFIG_SPIRAM_USE` - How to use PSRAM: disabled / as malloc fallback / as separate heap
- `CONFIG_SPIRAM_ALLOW_STACK_EXTERNAL_MEMORY` - Allow task stacks in PSRAM

---

## Idle Task Hooks

The idle task runs at priority 0 on each core when no other task is ready. ESP-IDF provides a hook mechanism to run custom code in the idle task context.

### Registering Idle Hooks

```c
#include "esp_freertos_hooks.h"

// Idle hook function — must NOT block or call any blocking FreeRTOS API
// Returns true to indicate the idle task can proceed to tickless idle
bool my_idle_hook(void) {
    // Lightweight background work
    // e.g., increment a counter, toggle a heartbeat pin
    gpio_set_level(LED_PIN, !gpio_get_level(LED_PIN));
    return true;
}

void app_main(void) {
    // Register idle hook on core 0
    esp_register_freertos_idle_hook_for_cpu(my_idle_hook, 0);

    // Register idle hook on core 1
    esp_register_freertos_idle_hook_for_cpu(my_idle_hook, 1);

    // Or register for the current core
    // esp_register_freertos_idle_hook(my_idle_hook);

    // Deregister when no longer needed
    // esp_deregister_freertos_idle_hook_for_cpu(my_idle_hook, 0);
}
```

### Tick Hooks

Tick hooks execute on every FreeRTOS tick. They run in ISR context and must be extremely fast.

```c
#include "esp_freertos_hooks.h"

void IRAM_ATTR my_tick_hook(void) {
    // Called every tick (every 1ms if CONFIG_FREERTOS_HZ=1000)
    // Must be VERY fast — no logging, no blocking, no heap allocation
    static uint32_t counter = 0;
    counter++;
}

void app_main(void) {
    esp_register_freertos_tick_hook_for_cpu(my_tick_hook, 0);
}
```

### Idle Hook Rules

- **Never block**: No `vTaskDelay`, no semaphore/mutex take, no queue receive with timeout
- **Keep it short**: The idle task must run frequently for watchdog feeding and memory cleanup
- **No heap allocation**: The idle task is responsible for freeing memory from deleted tasks
- If the idle task is starved (hook runs too long, or no idle time), the TWDT will trigger if the idle task is subscribed

---

## Best Practices

1. **Always use `pdMS_TO_TICKS()` for delays** instead of raw tick counts. This makes code portable across different `CONFIG_FREERTOS_HZ` settings.

2. **Never let a task function return.** Task functions must contain an infinite loop or call `vTaskDelete(NULL)` before returning. Returning from a task function causes undefined behavior.

3. **Pin time-critical tasks to core 1 (APP_CPU).** Core 0 handles Wi-Fi and BT protocol processing, which can introduce unpredictable latency.

4. **Use mutexes for mutual exclusion, semaphores for signaling.** Do not use binary semaphores to protect shared resources because they lack priority inheritance.

5. **Prefer task notifications over semaphores and queues** when only one task needs to be notified. Notifications are ~45% faster and use zero additional RAM.

6. **Size stacks with measurement, not guessing.** Use `uxTaskGetStackHighWaterMark()` during development and add 20-30% headroom for production.

7. **Subscribe long-running tasks to the TWDT.** Call `esp_task_wdt_reset()` in each iteration of the task loop to detect deadlocks and infinite waits.

8. **Use `heap_caps_get_minimum_free_size()` to track worst-case memory.** Log this at boot and periodically to detect slow memory leaks.

9. **Keep ISR handlers minimal.** Use `FromISR` API variants to send data to a processing task. Mark ISR handlers with `IRAM_ATTR`.

10. **Avoid dynamic allocation in steady state.** Allocate all resources (queues, semaphores, buffers) during initialization. This prevents heap fragmentation during long-running operation.

11. **Set `CONFIG_FREERTOS_CHECK_STACKOVERFLOW` to method 2** during development. The performance cost is negligible and it catches most overflow cases.

12. **Use event groups for multi-condition waits** instead of polling multiple flags in a loop. This reduces CPU usage and simplifies synchronization logic.

---

## Anti-Patterns

- **Using `vTaskDelay(0)` or `taskYIELD()` as a busy-wait.** This starves lower-priority tasks and wastes CPU. Block on a synchronization primitive instead.

- **Calling blocking FreeRTOS APIs from ISR context.** Only `FromISR` variants are safe in ISRs. Using the non-ISR API from an ISR causes undefined behavior and likely crashes.

- **Creating and deleting tasks repeatedly.** Task creation/deletion involves heap allocation/deallocation, leading to fragmentation. Create tasks once at startup and use suspend/resume or blocking primitives for lifecycle control.

- **Holding a mutex across a `vTaskDelay` or other blocking call.** This blocks other tasks from accessing the shared resource for the entire delay period. Acquire, do the work, release — keep the critical section short.

- **Using binary semaphores for mutual exclusion.** Binary semaphores have no ownership and no priority inheritance. Any task can "give" the semaphore even if it did not "take" it, leading to subtle bugs.

- **Ignoring the return value of `xQueueSend` / `xSemaphoreTake`.** These functions can fail (timeout, queue full). Always check the return value and handle the failure case.

- **Allocating large buffers on the stack.** The task stack is limited. Allocate large buffers on the heap or use static globals. A 4 KB buffer on a 4 KB stack will overflow immediately.

- **Starving the idle task.** If no task ever blocks or yields, the idle task never runs. This prevents memory cleanup from deleted tasks and causes the watchdog to trigger.

- **Using `printf` instead of `ESP_LOGx`.** `printf` is not thread-safe by default on ESP32. `ESP_LOGx` macros are thread-safe and provide log-level filtering.

- **Forgetting `portYIELD_FROM_ISR()` after `FromISR` calls.** Without the yield, the woken high-priority task does not run until the next tick or context switch, adding up to one tick period of latency.

- **Using `taskENTER_CRITICAL` for long sections.** Critical sections disable interrupts. Sections longer than a few microseconds risk missing hardware interrupts and triggering the IWDT.

---

## Sources & References

- [ESP-IDF FreeRTOS SMP Documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/freertos_idf.html)
- [FreeRTOS Kernel Reference Manual](https://www.freertos.org/Documentation/02-Kernel/04-API-references/01-Task-creation/00-TaskHandle)
- [ESP-IDF Task Watchdog Timer API](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/wdts.html)
- [ESP-IDF Heap Memory Allocation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/mem_alloc.html)
- [FreeRTOS Queue API Reference](https://www.freertos.org/Documentation/02-Kernel/04-API-references/07-Queue-management/00-QueueHandle)
- [ESP-IDF FreeRTOS Task Notifications](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/system/freertos_idf.html#task-notifications)
- [ESP32 Technical Reference Manual (Espressif)](https://www.espressif.com/sites/default/files/documentation/esp32_technical_reference_manual_en.pdf)
- [FreeRTOS Mutex and Priority Inheritance](https://www.freertos.org/Documentation/02-Kernel/02-Kernel-features/04-Resource-management/01-Mutexes)
