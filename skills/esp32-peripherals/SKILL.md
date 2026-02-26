---
name: esp32-peripherals
description: ESP32 Peripheral Programming — GPIO input/output, ADC oneshot & continuous, DAC, PWM via LEDC, I2C master/slave, SPI master, UART, interrupt handling, DMA transfers, pin multiplexing, ESP-IDF 5.x driver APIs
---

# ESP32 Peripheral Programming

Comprehensive reference for programming ESP32 peripherals using ESP-IDF 5.x driver APIs. Covers GPIO configuration (input, output, open-drain), ADC with calibration, PWM generation via the LEDC peripheral, I2C and SPI bus communication, UART with event-driven reception, interrupt handling, DMA transfers for high-throughput data acquisition, and pin multiplexing through the IO MUX and GPIO matrix.

## Table of Contents

1. [GPIO Configuration](#gpio-configuration)
2. [GPIO Interrupts](#gpio-interrupts)
3. [ADC Oneshot Mode](#adc-oneshot-mode)
4. [ADC Continuous Mode with DMA](#adc-continuous-mode-with-dma)
5. [DAC Output](#dac-output)
6. [PWM via LEDC](#pwm-via-ledc)
7. [I2C Master and Slave](#i2c-master-and-slave)
8. [SPI Master](#spi-master)
9. [UART Communication](#uart-communication)
10. [Pin Multiplexing and IO MUX](#pin-multiplexing-and-io-mux)
11. [DMA Transfers](#dma-transfers)
12. [Best Practices](#best-practices)
13. [Anti-Patterns](#anti-patterns)
14. [Sources & References](#sources--references)

---

## GPIO Configuration

ESP-IDF 5.x uses the `driver/gpio.h` API for all GPIO operations. Each pin can be configured as input, output, open-drain output, or input/output with optional internal pull-up/pull-down resistors.

### Output Mode

```c
#include "driver/gpio.h"
#include "esp_log.h"

static const char *TAG = "gpio_example";

esp_err_t configure_gpio_output(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << GPIO_NUM_2) | (1ULL << GPIO_NUM_4),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t ret = gpio_config(&io_conf);
    if (ret != ESP_OK) {
        ESP_LOGE(TAG, "GPIO output config failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Set pin high
    ESP_ERROR_CHECK(gpio_set_level(GPIO_NUM_2, 1));

    // Set pin low
    ESP_ERROR_CHECK(gpio_set_level(GPIO_NUM_4, 0));

    return ESP_OK;
}
```

### Input Mode with Pull-Up

```c
esp_err_t configure_gpio_input(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << GPIO_NUM_34),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&io_conf));

    int level = gpio_get_level(GPIO_NUM_34);
    ESP_LOGI(TAG, "GPIO34 level: %d", level);

    return ESP_OK;
}
```

### Open-Drain Mode

Open-drain output is essential for shared buses like I2C bit-banging or driving multiple devices where the line must be pulled low by any participant. The pin can only sink current to ground; an external pull-up resistor is required.

```c
esp_err_t configure_gpio_open_drain(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << GPIO_NUM_18),
        .mode = GPIO_MODE_OUTPUT_OD,
        .pull_up_en = GPIO_PULLUP_ENABLE,   // internal pull-up, or use external
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&io_conf));

    return ESP_OK;
}
```

**GPIO-safe pins on ESP32:** GPIOs 0, 2, 4, 5, 12-19, 21-23, 25-27, 32-33 are generally safe for output. GPIOs 34-39 are input-only and have no internal pull-up/pull-down. GPIOs 6-11 are connected to internal flash and must not be used.

---

## GPIO Interrupts

ESP-IDF provides ISR-based GPIO interrupts with configurable edge/level triggers. The ISR handler runs in IRAM and must be marked with `IRAM_ATTR`. Use a task notification or queue to defer processing out of the ISR context.

### Interrupt-on-Edge with Task Notification

```c
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "esp_log.h"

#define BUTTON_GPIO     GPIO_NUM_0
#define ESP_INTR_FLAG_DEFAULT 0

static const char *TAG = "gpio_isr";
static QueueHandle_t gpio_evt_queue = NULL;

static void IRAM_ATTR gpio_isr_handler(void *arg)
{
    uint32_t gpio_num = (uint32_t)arg;
    xQueueSendFromISR(gpio_evt_queue, &gpio_num, NULL);
}

static void gpio_task(void *arg)
{
    uint32_t io_num;
    for (;;) {
        if (xQueueReceive(gpio_evt_queue, &io_num, portMAX_DELAY)) {
            int level = gpio_get_level(io_num);
            ESP_LOGI(TAG, "GPIO[%"PRIu32"] intr, level: %d", io_num, level);
        }
    }
}

esp_err_t setup_gpio_interrupt(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << BUTTON_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_NEGEDGE,  // falling edge for active-low button
    };
    ESP_ERROR_CHECK(gpio_config(&io_conf));

    gpio_evt_queue = xQueueCreate(10, sizeof(uint32_t));
    if (gpio_evt_queue == NULL) {
        ESP_LOGE(TAG, "Failed to create GPIO event queue");
        return ESP_ERR_NO_MEM;
    }

    ESP_ERROR_CHECK(gpio_install_isr_service(ESP_INTR_FLAG_DEFAULT));
    ESP_ERROR_CHECK(gpio_isr_handler_add(BUTTON_GPIO, gpio_isr_handler,
                                          (void *)BUTTON_GPIO));

    xTaskCreate(gpio_task, "gpio_task", 2048, NULL, 10, NULL);

    return ESP_OK;
}
```

**Interrupt types:**
- `GPIO_INTR_POSEDGE` -- rising edge
- `GPIO_INTR_NEGEDGE` -- falling edge
- `GPIO_INTR_ANYEDGE` -- both edges
- `GPIO_INTR_LOW_LEVEL` -- low level trigger
- `GPIO_INTR_HIGH_LEVEL` -- high level trigger

**Debouncing:** Hardware buttons require debouncing. Either use a hardware RC filter (10k + 100nF, ~1ms time constant) or implement software debouncing by recording the timestamp in the ISR and ignoring events within a 50ms window.

---

## ADC Oneshot Mode

ESP-IDF 5.x replaced the legacy `adc1_get_raw()` API with the unified ADC oneshot driver. The new API supports calibration via `esp_adc/adc_cali.h` for accurate voltage readings.

### Oneshot Read with Calibration

```c
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_log.h"

static const char *TAG = "adc_oneshot";

esp_err_t adc_oneshot_example(void)
{
    // 1. Initialize ADC oneshot unit
    adc_oneshot_unit_handle_t adc_handle;
    adc_oneshot_unit_init_cfg_t init_cfg = {
        .unit_id = ADC_UNIT_1,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&init_cfg, &adc_handle));

    // 2. Configure channel
    adc_oneshot_chan_cfg_t chan_cfg = {
        .atten = ADC_ATTEN_DB_12,    // 0-3.3V range (ESP32-S3) or 0-2.6V (ESP32)
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(adc_handle, ADC_CHANNEL_6, &chan_cfg));

    // 3. Set up calibration (curve fitting for ESP32-S2/S3/C3)
    adc_cali_handle_t cali_handle = NULL;
    bool calibrated = false;

#if ADC_CALI_SCHEME_CURVE_FITTING_SUPPORTED
    adc_cali_curve_fitting_config_t cali_cfg = {
        .unit_id = ADC_UNIT_1,
        .chan = ADC_CHANNEL_6,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    esp_err_t ret = adc_cali_create_scheme_curve_fitting(&cali_cfg, &cali_handle);
    if (ret == ESP_OK) {
        calibrated = true;
    }
#elif ADC_CALI_SCHEME_LINE_FITTING_SUPPORTED
    adc_cali_line_fitting_config_t cali_cfg = {
        .unit_id = ADC_UNIT_1,
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    esp_err_t ret = adc_cali_create_scheme_line_fitting(&cali_cfg, &cali_handle);
    if (ret == ESP_OK) {
        calibrated = true;
    }
#endif

    // 4. Read raw and calibrated values
    int raw_value = 0;
    int voltage_mv = 0;

    ESP_ERROR_CHECK(adc_oneshot_read(adc_handle, ADC_CHANNEL_6, &raw_value));
    ESP_LOGI(TAG, "ADC raw: %d", raw_value);

    if (calibrated) {
        ESP_ERROR_CHECK(adc_cali_raw_to_voltage(cali_handle, raw_value, &voltage_mv));
        ESP_LOGI(TAG, "ADC calibrated: %d mV", voltage_mv);
    }

    // 5. Cleanup
    ESP_ERROR_CHECK(adc_oneshot_del_unit(adc_handle));
    if (calibrated) {
#if ADC_CALI_SCHEME_CURVE_FITTING_SUPPORTED
        adc_cali_delete_scheme_curve_fitting(cali_handle);
#elif ADC_CALI_SCHEME_LINE_FITTING_SUPPORTED
        adc_cali_delete_scheme_line_fitting(cali_handle);
#endif
    }

    return ESP_OK;
}
```

**Attenuation settings:**
| Attenuation | ESP32 Range | ESP32-S3 Range |
|---|---|---|
| `ADC_ATTEN_DB_0` | 0-1.1V | 0-0.95V |
| `ADC_ATTEN_DB_2_5` | 0-1.5V | 0-1.25V |
| `ADC_ATTEN_DB_6` | 0-2.2V | 0-1.75V |
| `ADC_ATTEN_DB_12` | 0-2.6V | 0-3.1V |

**ADC channel to GPIO mapping (ESP32):** ADC1_CH0=GPIO36, CH3=GPIO39, CH4=GPIO32, CH5=GPIO33, CH6=GPIO34, CH7=GPIO35. ADC2 channels conflict with Wi-Fi and should be avoided when Wi-Fi is active.

---

## ADC Continuous Mode with DMA

For high-throughput sampling (e.g., audio capture, waveform analysis), use ADC continuous mode. The DMA controller transfers samples directly to memory without CPU intervention, achieving sample rates up to several hundred kHz.

### Continuous ADC with DMA Callback

```c
#include "esp_adc/adc_continuous.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "adc_cont";

#define ADC_READ_LEN        256
#define ADC_SAMPLE_FREQ_HZ  20000

static TaskHandle_t s_task_handle = NULL;

static bool IRAM_ATTR adc_conv_done_cb(adc_continuous_handle_t handle,
                                        const adc_continuous_evt_data_t *edata,
                                        void *user_data)
{
    BaseType_t must_yield = pdFALSE;
    vTaskNotifyGiveFromISR(s_task_handle, &must_yield);
    return (must_yield == pdTRUE);
}

esp_err_t adc_continuous_example(void)
{
    s_task_handle = xTaskGetCurrentTaskHandle();

    // 1. Create continuous ADC handle
    adc_continuous_handle_t adc_handle = NULL;
    adc_continuous_handle_cfg_t handle_cfg = {
        .max_store_buf_size = 1024,
        .conv_frame_size = ADC_READ_LEN,
    };
    ESP_ERROR_CHECK(adc_continuous_new_handle(&handle_cfg, &adc_handle));

    // 2. Configure the ADC pattern (which channels to sample)
    adc_digi_pattern_config_t adc_pattern = {
        .atten = ADC_ATTEN_DB_12,
        .channel = ADC_CHANNEL_6,
        .unit = ADC_UNIT_1,
        .bit_width = ADC_BITWIDTH_12,
    };
    adc_continuous_config_t dig_cfg = {
        .sample_freq_hz = ADC_SAMPLE_FREQ_HZ,
        .conv_mode = ADC_CONV_SINGLE_UNIT_1,
        .format = ADC_DIGI_OUTPUT_FORMAT_TYPE2,
        .pattern_num = 1,
        .adc_pattern = &adc_pattern,
    };
    ESP_ERROR_CHECK(adc_continuous_config(adc_handle, &dig_cfg));

    // 3. Register conversion-done callback
    adc_continuous_evt_cbs_t cbs = {
        .on_conv_done = adc_conv_done_cb,
    };
    ESP_ERROR_CHECK(adc_continuous_register_event_callbacks(adc_handle, &cbs, NULL));

    // 4. Start continuous conversion
    ESP_ERROR_CHECK(adc_continuous_start(adc_handle));

    // 5. Read data in a loop
    uint8_t result[ADC_READ_LEN] = {0};
    uint32_t ret_num = 0;

    while (true) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);

        esp_err_t ret = adc_continuous_read(adc_handle, result, ADC_READ_LEN,
                                             &ret_num, 0);
        if (ret == ESP_OK) {
            for (int i = 0; i < ret_num; i += SOC_ADC_DIGI_RESULT_BYTES) {
                adc_digi_output_data_t *data = (adc_digi_output_data_t *)&result[i];
                uint32_t channel = data->type2.channel;
                uint32_t raw = data->type2.data;
                ESP_LOGI(TAG, "Channel: %"PRIu32", Raw: %"PRIu32, channel, raw);
            }
        }
    }

    // Cleanup (unreachable in this example, but shown for completeness)
    ESP_ERROR_CHECK(adc_continuous_stop(adc_handle));
    ESP_ERROR_CHECK(adc_continuous_deinit(adc_handle));

    return ESP_OK;
}
```

**DMA buffer sizing:** The `max_store_buf_size` should be at least 2x `conv_frame_size` to allow double buffering. For high sample rates, increase both values. Each sample is `SOC_ADC_DIGI_RESULT_BYTES` (typically 4 bytes), so a 256-byte frame holds 64 samples.

---

## DAC Output

The original ESP32 and ESP32-S2 have two 8-bit DAC channels. ESP32-S3 and ESP32-C3 do not have DAC peripherals. In ESP-IDF 5.x, the DAC uses the `esp_driver_dac` component.

### DAC Oneshot Output

```c
#include "driver/dac_oneshot.h"
#include "esp_log.h"

static const char *TAG = "dac_example";

esp_err_t dac_output_example(void)
{
    dac_oneshot_handle_t dac_handle;
    dac_oneshot_config_t dac_cfg = {
        .chan_id = DAC_CHAN_0,   // GPIO25 on ESP32
    };
    ESP_ERROR_CHECK(dac_oneshot_new_channel(&dac_cfg, &dac_handle));

    // Output a voltage: value 0-255 maps to 0-VDD (approx 0-3.3V)
    // 128 = ~1.65V (midpoint)
    ESP_ERROR_CHECK(dac_oneshot_output_voltage(dac_handle, 128));
    ESP_LOGI(TAG, "DAC output set to ~1.65V");

    // Generate a simple ramp
    for (int val = 0; val < 256; val++) {
        ESP_ERROR_CHECK(dac_oneshot_output_voltage(dac_handle, val));
        vTaskDelay(pdMS_TO_TICKS(10));
    }

    ESP_ERROR_CHECK(dac_oneshot_del_channel(dac_handle));
    return ESP_OK;
}
```

**DAC channel mapping (ESP32):** DAC_CHAN_0 = GPIO25, DAC_CHAN_1 = GPIO26. For continuous waveform generation (sine, triangle), use the `dac_cosine` driver or DMA-backed `dac_continuous` driver for arbitrary waveforms.

---

## PWM via LEDC

The LEDC (LED Control) peripheral provides up to 8 independent PWM channels. In ESP-IDF 5.x, each channel is bound to a timer. Timers control frequency and resolution; channels control duty cycle and output pin.

### Timer and Channel Setup

```c
#include "driver/ledc.h"
#include "esp_log.h"

static const char *TAG = "ledc_pwm";

#define LEDC_TIMER          LEDC_TIMER_0
#define LEDC_MODE           LEDC_LOW_SPEED_MODE
#define LEDC_CHANNEL        LEDC_CHANNEL_0
#define LEDC_OUTPUT_GPIO    GPIO_NUM_18
#define LEDC_DUTY_RES       LEDC_TIMER_13_BIT  // 8192 levels
#define LEDC_FREQUENCY      5000                // 5 kHz

esp_err_t ledc_pwm_init(void)
{
    // 1. Configure timer
    ledc_timer_config_t timer_cfg = {
        .speed_mode = LEDC_MODE,
        .duty_resolution = LEDC_DUTY_RES,
        .timer_num = LEDC_TIMER,
        .freq_hz = LEDC_FREQUENCY,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ESP_ERROR_CHECK(ledc_timer_config(&timer_cfg));

    // 2. Configure channel
    ledc_channel_config_t channel_cfg = {
        .gpio_num = LEDC_OUTPUT_GPIO,
        .speed_mode = LEDC_MODE,
        .channel = LEDC_CHANNEL,
        .timer_sel = LEDC_TIMER,
        .intr_type = LEDC_INTR_DISABLE,
        .duty = 0,
        .hpoint = 0,
    };
    ESP_ERROR_CHECK(ledc_channel_config(&channel_cfg));

    return ESP_OK;
}

esp_err_t ledc_set_duty_percent(uint32_t percent)
{
    if (percent > 100) percent = 100;
    uint32_t max_duty = (1 << LEDC_DUTY_RES) - 1;
    uint32_t duty = (max_duty * percent) / 100;

    ESP_ERROR_CHECK(ledc_set_duty(LEDC_MODE, LEDC_CHANNEL, duty));
    ESP_ERROR_CHECK(ledc_update_duty(LEDC_MODE, LEDC_CHANNEL));

    ESP_LOGI(TAG, "PWM duty set to %"PRIu32"%% (raw: %"PRIu32")", percent, duty);
    return ESP_OK;
}
```

### Hardware Fade

The LEDC peripheral supports hardware-accelerated duty cycle fading without CPU intervention.

```c
esp_err_t ledc_fade_example(void)
{
    // Install fade service (call once)
    ESP_ERROR_CHECK(ledc_fade_func_install(0));

    // Fade to 75% duty over 2 seconds
    uint32_t target_duty = ((1 << LEDC_DUTY_RES) - 1) * 75 / 100;
    ESP_ERROR_CHECK(ledc_set_fade_with_time(LEDC_MODE, LEDC_CHANNEL,
                                             target_duty, 2000));
    ESP_ERROR_CHECK(ledc_fade_start(LEDC_MODE, LEDC_CHANNEL,
                                     LEDC_FADE_NO_WAIT));

    ESP_LOGI(TAG, "Fade started to 75%% over 2 seconds");
    return ESP_OK;
}
```

**Frequency vs resolution tradeoff:** The maximum duty resolution depends on the source clock and desired frequency. For a 80MHz APB clock: `max_resolution = log2(80,000,000 / frequency)`. At 5kHz, maximum resolution is ~14 bits. At 40kHz, it drops to ~11 bits.

**Servo control:** Standard servos expect 50Hz PWM with 1-2ms pulse width. Use `LEDC_TIMER_16_BIT` at 50Hz for fine positioning control.

---

## I2C Master and Slave

ESP-IDF 5.x provides the new I2C master driver via `driver/i2c_master.h`. The legacy `i2c_driver_install` API is deprecated.

### I2C Master Bus Initialization

```c
#include "driver/i2c_master.h"
#include "esp_log.h"

static const char *TAG = "i2c_master";

#define I2C_MASTER_SDA_GPIO   GPIO_NUM_21
#define I2C_MASTER_SCL_GPIO   GPIO_NUM_22
#define I2C_MASTER_FREQ_HZ    400000    // 400kHz fast mode

static i2c_master_bus_handle_t bus_handle;

esp_err_t i2c_master_init(void)
{
    i2c_master_bus_config_t bus_cfg = {
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .i2c_port = I2C_NUM_0,
        .sda_io_num = I2C_MASTER_SDA_GPIO,
        .scl_io_num = I2C_MASTER_SCL_GPIO,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_cfg, &bus_handle));

    ESP_LOGI(TAG, "I2C master initialized on port 0");
    return ESP_OK;
}
```

### Device Registration and Read/Write

```c
#define BME280_ADDR     0x76
#define BME280_REG_ID   0xD0

static i2c_master_dev_handle_t bme280_handle;

esp_err_t i2c_add_bme280(void)
{
    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = BME280_ADDR,
        .scl_speed_hz = I2C_MASTER_FREQ_HZ,
    };
    ESP_ERROR_CHECK(i2c_master_bus_add_device(bus_handle, &dev_cfg, &bme280_handle));

    return ESP_OK;
}

esp_err_t i2c_read_bme280_id(uint8_t *chip_id)
{
    uint8_t reg_addr = BME280_REG_ID;

    // Write register address, then read one byte
    ESP_ERROR_CHECK(i2c_master_transmit_receive(bme280_handle,
                                                 &reg_addr, 1,
                                                 chip_id, 1,
                                                 pdMS_TO_TICKS(100)));

    ESP_LOGI(TAG, "BME280 chip ID: 0x%02X", *chip_id);
    return ESP_OK;
}

esp_err_t i2c_write_register(uint8_t reg, uint8_t value)
{
    uint8_t write_buf[2] = {reg, value};
    ESP_ERROR_CHECK(i2c_master_transmit(bme280_handle,
                                         write_buf, sizeof(write_buf),
                                         pdMS_TO_TICKS(100)));
    return ESP_OK;
}
```

### I2C Bus Scanning

```c
esp_err_t i2c_bus_scan(void)
{
    ESP_LOGI(TAG, "Scanning I2C bus...");
    uint8_t address;
    int devices_found = 0;

    for (address = 1; address < 127; address++) {
        esp_err_t ret = i2c_master_probe(bus_handle, address,
                                          pdMS_TO_TICKS(50));
        if (ret == ESP_OK) {
            ESP_LOGI(TAG, "Device found at address 0x%02X", address);
            devices_found++;
        }
    }

    ESP_LOGI(TAG, "Scan complete. %d device(s) found.", devices_found);
    return ESP_OK;
}
```

**I2C speed modes:** Standard mode (100kHz), Fast mode (400kHz), Fast mode plus (1MHz on supported chips). Always use external 4.7k pull-up resistors for reliable operation; internal pull-ups are weak (~45k) and only suitable for short traces at low speeds.

---

## SPI Master

ESP-IDF 5.x provides the SPI master driver via `driver/spi_master.h`. The ESP32 has four SPI peripherals: SPI0/SPI1 are reserved for flash; SPI2 (HSPI) and SPI3 (VSPI) are available for user applications.

### SPI Bus and Device Initialization

```c
#include "driver/spi_master.h"
#include "esp_log.h"

static const char *TAG = "spi_master";

#define SPI_MOSI_GPIO   GPIO_NUM_23
#define SPI_MISO_GPIO   GPIO_NUM_19
#define SPI_SCLK_GPIO   GPIO_NUM_18
#define SPI_CS_GPIO      GPIO_NUM_5

static spi_device_handle_t spi_dev;

esp_err_t spi_master_init(void)
{
    // 1. Configure the SPI bus
    spi_bus_config_t bus_cfg = {
        .mosi_io_num = SPI_MOSI_GPIO,
        .miso_io_num = SPI_MISO_GPIO,
        .sclk_io_num = SPI_SCLK_GPIO,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 4096,
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus_cfg, SPI_DMA_CH_AUTO));

    // 2. Add a device on the bus
    spi_device_interface_config_t dev_cfg = {
        .clock_speed_hz = 10 * 1000 * 1000,  // 10 MHz
        .mode = 0,                             // CPOL=0, CPHA=0
        .spics_io_num = SPI_CS_GPIO,
        .queue_size = 7,
        .flags = 0,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &dev_cfg, &spi_dev));

    ESP_LOGI(TAG, "SPI master initialized");
    return ESP_OK;
}
```

### SPI Transactions

```c
esp_err_t spi_read_register(uint8_t reg, uint8_t *data, size_t len)
{
    spi_transaction_t trans = {
        .flags = 0,
        .cmd = 0,
        .addr = 0,
        .length = (len + 1) * 8,       // total bits to transfer
        .rxlength = len * 8,            // bits to receive
        .tx_buffer = NULL,
        .rx_buffer = NULL,
    };

    // For small transfers, use tx_data/rx_data to avoid DMA allocation
    if (len <= 4) {
        trans.flags = SPI_TRANS_USE_TXDATA | SPI_TRANS_USE_RXDATA;
        trans.tx_data[0] = reg | 0x80;  // read flag for many SPI devices
        trans.length = (len + 1) * 8;

        ESP_ERROR_CHECK(spi_device_polling_transmit(spi_dev, &trans));
        memcpy(data, &trans.rx_data[1], len);
    } else {
        uint8_t *tx_buf = heap_caps_calloc(1, len + 1, MALLOC_CAP_DMA);
        uint8_t *rx_buf = heap_caps_calloc(1, len + 1, MALLOC_CAP_DMA);
        if (!tx_buf || !rx_buf) {
            free(tx_buf);
            free(rx_buf);
            return ESP_ERR_NO_MEM;
        }

        tx_buf[0] = reg | 0x80;
        trans.tx_buffer = tx_buf;
        trans.rx_buffer = rx_buf;

        ESP_ERROR_CHECK(spi_device_polling_transmit(spi_dev, &trans));
        memcpy(data, rx_buf + 1, len);

        free(tx_buf);
        free(rx_buf);
    }

    return ESP_OK;
}

esp_err_t spi_write_register(uint8_t reg, uint8_t value)
{
    spi_transaction_t trans = {
        .flags = SPI_TRANS_USE_TXDATA,
        .length = 16,   // 2 bytes = 16 bits
        .tx_data = {reg & 0x7F, value},   // write flag (clear bit 7)
    };
    ESP_ERROR_CHECK(spi_device_polling_transmit(spi_dev, &trans));

    return ESP_OK;
}
```

**SPI modes (CPOL/CPHA):**
| Mode | CPOL | CPHA | Description |
|---|---|---|---|
| 0 | 0 | 0 | Clock idle low, sample on rising edge |
| 1 | 0 | 1 | Clock idle low, sample on falling edge |
| 2 | 1 | 0 | Clock idle high, sample on falling edge |
| 3 | 1 | 1 | Clock idle high, sample on rising edge |

**DMA for SPI:** When `SPI_DMA_CH_AUTO` is specified, the driver automatically selects a DMA channel. Buffers used with DMA must be allocated with `MALLOC_CAP_DMA` (word-aligned, in internal RAM). Transfers of 32 bytes or less can use the internal `tx_data`/`rx_data` fields to avoid DMA overhead.

---

## UART Communication

ESP-IDF 5.x provides the UART driver with event-driven reception via a FreeRTOS queue, enabling non-blocking data reception with pattern detection.

### Basic UART Setup

```c
#include "driver/uart.h"
#include "esp_log.h"

static const char *TAG = "uart_example";

#define UART_PORT       UART_NUM_1
#define UART_TX_GPIO    GPIO_NUM_17
#define UART_RX_GPIO    GPIO_NUM_16
#define UART_BUF_SIZE   1024

esp_err_t uart_init(void)
{
    uart_config_t uart_cfg = {
        .baud_rate = 115200,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    ESP_ERROR_CHECK(uart_param_config(UART_PORT, &uart_cfg));

    ESP_ERROR_CHECK(uart_set_pin(UART_PORT, UART_TX_GPIO, UART_RX_GPIO,
                                  UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

    // Install driver with RX buffer, TX buffer, and event queue
    QueueHandle_t uart_queue;
    ESP_ERROR_CHECK(uart_driver_install(UART_PORT, UART_BUF_SIZE * 2,
                                         UART_BUF_SIZE * 2, 20,
                                         &uart_queue, 0));

    ESP_LOGI(TAG, "UART%d initialized", UART_PORT);
    return ESP_OK;
}

esp_err_t uart_send_data(const char *data)
{
    int len = strlen(data);
    int bytes_written = uart_write_bytes(UART_PORT, data, len);
    ESP_LOGI(TAG, "Wrote %d bytes", bytes_written);
    return (bytes_written == len) ? ESP_OK : ESP_FAIL;
}
```

### Event-Driven Reception

```c
static void uart_event_task(void *arg)
{
    QueueHandle_t uart_queue = (QueueHandle_t)arg;
    uart_event_t event;
    uint8_t *rx_buf = malloc(UART_BUF_SIZE);
    if (!rx_buf) {
        ESP_LOGE(TAG, "Failed to allocate UART RX buffer");
        vTaskDelete(NULL);
        return;
    }

    for (;;) {
        if (xQueueReceive(uart_queue, &event, portMAX_DELAY)) {
            switch (event.type) {
            case UART_DATA:
                {
                    int len = uart_read_bytes(UART_PORT, rx_buf,
                                               event.size, pdMS_TO_TICKS(100));
                    if (len > 0) {
                        rx_buf[len] = '\0';
                        ESP_LOGI(TAG, "Received %d bytes: %s", len, rx_buf);
                    }
                }
                break;

            case UART_FIFO_OVF:
                ESP_LOGW(TAG, "FIFO overflow");
                uart_flush_input(UART_PORT);
                xQueueReset(uart_queue);
                break;

            case UART_BUFFER_FULL:
                ESP_LOGW(TAG, "Ring buffer full");
                uart_flush_input(UART_PORT);
                xQueueReset(uart_queue);
                break;

            case UART_PARITY_ERR:
                ESP_LOGW(TAG, "Parity error");
                break;

            case UART_FRAME_ERR:
                ESP_LOGW(TAG, "Frame error");
                break;

            case UART_PATTERN_DET:
                {
                    size_t buf_len = 0;
                    uart_get_buffered_data_len(UART_PORT, &buf_len);
                    int pos = uart_pattern_pop_pos(UART_PORT);
                    ESP_LOGI(TAG, "Pattern detected at pos: %d, buffered: %d",
                             pos, (int)buf_len);
                }
                break;

            default:
                ESP_LOGD(TAG, "UART event type: %d", event.type);
                break;
            }
        }
    }

    free(rx_buf);
    vTaskDelete(NULL);
}
```

**Pattern detection:** Use `uart_enable_pattern_det_baud_intr()` to trigger an event when a specific byte pattern is received (e.g., newline characters for line-based protocols). This is efficient for parsing AT commands or NMEA GPS sentences.

**RS-485 half-duplex:** ESP32 UART supports RS-485 mode with automatic RTS control for direction switching. Configure with `uart_set_mode(UART_PORT, UART_MODE_RS485_HALF_DUPLEX)`.

---

## Pin Multiplexing and IO MUX

The ESP32 uses two mechanisms for connecting peripheral signals to GPIO pins: the IO MUX (direct connection, lower latency) and the GPIO matrix (flexible routing, one-clock-cycle delay).

### GPIO Matrix

Most peripheral signals are routed through the GPIO matrix, which allows any signal to be mapped to (almost) any pin. The ESP-IDF drivers handle this automatically when you specify GPIO numbers in configuration structs.

```c
#include "driver/gpio.h"
#include "soc/gpio_sig_map.h"

// Manual GPIO matrix routing (rarely needed, drivers do this automatically)
// Route the LEDC channel 0 output signal to GPIO 25
esp_err_t manual_pin_route(void)
{
    // Output signal routing
    esp_rom_gpio_connect_out_signal(GPIO_NUM_25, LEDC_LS_SIG_OUT0_IDX, false, false);

    // Input signal routing
    esp_rom_gpio_connect_in_signal(GPIO_NUM_26, U1RXD_IN_IDX, false);

    return ESP_OK;
}
```

### IO MUX Direct Functions

Some pins have direct IO MUX connections to specific peripherals, bypassing the GPIO matrix for lower latency. This is important for high-speed SPI and SDIO.

**ESP32 SPI2 (HSPI) IO MUX pins:** MOSI=GPIO13, MISO=GPIO12, SCLK=GPIO14, CS=GPIO15. Using these pins enables IO MUX mode automatically, achieving higher SPI clock speeds (up to 80MHz) compared to GPIO matrix routing (up to 40MHz).

**Key constraints:**
- GPIO 6-11: Connected to internal SPI flash. Do not use.
- GPIO 34-39: Input only. No output, no pull-up/pull-down.
- GPIO 0: Bootstrapping pin. Avoid using for input (pulled up at boot).
- GPIO 2: Bootstrapping pin. Must be low or floating during boot for flash programming.
- GPIO 12 (MTDI): Sets flash voltage. If your board uses 3.3V flash, this pin must not be pulled high at boot.
- GPIO 15 (MTDO): Controls startup log output. If pulled low at boot, serial output is suppressed.

---

## DMA Transfers

DMA (Direct Memory Access) allows peripherals to transfer data to/from memory without CPU involvement. On ESP32, DMA is used by SPI, I2S, ADC continuous mode, and the GDMA controller on newer chips (ESP32-S2, S3, C3).

### DMA Buffer Requirements

All DMA buffers must meet alignment and memory region constraints:

```c
#include "esp_heap_caps.h"

// DMA-capable buffer allocation
uint8_t *dma_buf = heap_caps_malloc(4096, MALLOC_CAP_DMA);
if (dma_buf == NULL) {
    ESP_LOGE(TAG, "Failed to allocate DMA buffer");
    return ESP_ERR_NO_MEM;
}

// DMA buffers must be:
// - In internal SRAM (not PSRAM/SPIRAM unless using EDMA on ESP32-S3)
// - Word-aligned (4-byte boundary)
// - Allocated with MALLOC_CAP_DMA flag

// For ESP32-S3 with EDMA (supports PSRAM DMA):
#if CONFIG_IDF_TARGET_ESP32S3
uint8_t *psram_dma_buf = heap_caps_aligned_alloc(64, 4096,
                              MALLOC_CAP_SPIRAM | MALLOC_CAP_DMA);
#endif

// Always free DMA buffers when done
heap_caps_free(dma_buf);
```

### GDMA Controller (ESP32-S2/S3/C3)

Newer ESP32 variants use the General DMA (GDMA) controller instead of dedicated per-peripheral DMA. The GDMA controller provides configurable channels that can be connected to different peripherals.

**DMA descriptor chains:** For large transfers, the DMA engine uses linked descriptor lists. Each descriptor points to a buffer and the next descriptor. The ESP-IDF SPI and I2S drivers manage descriptor chains internally, but understanding them helps when debugging buffer overruns.

**Performance considerations:**
- DMA transfers from PSRAM are slower than from internal SRAM due to the SPI interface.
- Cache line alignment (32 or 64 bytes depending on chip) prevents cache coherency issues.
- For continuous high-throughput applications, use ping-pong (double) buffers: one buffer is being filled by DMA while the CPU processes the other.

---

## Best Practices

1. **Always use ESP_ERROR_CHECK or explicit error handling.** Every ESP-IDF API returns `esp_err_t`. Unchecked errors lead to silent failures that are difficult to debug. Use `ESP_ERROR_CHECK()` during development and explicit `esp_err_t` handling in production code.

2. **Allocate DMA buffers with MALLOC_CAP_DMA.** DMA requires word-aligned buffers in internal SRAM. Using standard `malloc()` may return PSRAM memory on boards with external RAM, causing DMA failures.

3. **Keep ISR handlers minimal.** ISR handlers must be in IRAM (`IRAM_ATTR`) and should only set flags, post to queues, or give task notifications. Never call logging functions, allocate memory, or use floating-point math in ISRs.

4. **Use the new ESP-IDF 5.x driver APIs.** The legacy `adc1_get_raw()`, `i2c_driver_install()`, and similar APIs are deprecated. Use `adc_oneshot_read()`, `i2c_new_master_bus()`, and the corresponding new driver APIs for better performance and maintainability.

5. **Apply ADC calibration for voltage measurements.** Raw ADC readings are non-linear and vary between chips. Always use the calibration API (`adc_cali_raw_to_voltage()`) when accurate voltage readings are needed. The curve fitting scheme provides better accuracy than line fitting.

6. **Respect ADC2 and Wi-Fi conflicts.** ADC2 channels cannot be used while Wi-Fi is active on ESP32. Design your pin assignments to use ADC1 channels for analog inputs when Wi-Fi is required.

7. **Use external pull-ups for I2C.** Internal pull-ups (~45k Ohm) are too weak for reliable I2C communication, especially at 400kHz. Use 4.7k external pull-up resistors on SDA and SCL lines.

8. **Match SPI mode to the slave device datasheet.** An incorrect CPOL/CPHA setting causes garbled data or no communication. Verify the SPI mode, bit order, and maximum clock speed from the peripheral datasheet.

9. **Handle UART buffer overflow events.** Always monitor `UART_FIFO_OVF` and `UART_BUFFER_FULL` events. Flush the input buffer and reset the queue on overflow to prevent stale data from accumulating.

10. **Use IO MUX pins for high-speed SPI.** When SPI clock speed exceeds 40MHz, use the dedicated IO MUX pins for the SPI peripheral. GPIO matrix routing introduces a one-clock-cycle delay that limits maximum frequency.

---

## Anti-Patterns

- **Using GPIO 6-11 for general I/O.** These pins are connected to the internal SPI flash and will crash the chip or corrupt flash if driven externally.
- **Reading ADC2 while Wi-Fi is active.** This will return `ESP_ERR_TIMEOUT` or garbage data on ESP32. Always use ADC1 channels when Wi-Fi is required.
- **Calling `ESP_LOGI()` or `printf()` inside an ISR.** Logging functions are not ISR-safe; they allocate memory and use mutexes. This causes watchdog timeouts, stack overflow, or deadlocks.
- **Using `malloc()` for DMA buffers on boards with PSRAM.** Standard `malloc()` may return PSRAM addresses when `CONFIG_SPIRAM_USE_MALLOC` is enabled. DMA controllers on ESP32 cannot access PSRAM (except EDMA on ESP32-S3). Always use `heap_caps_malloc(size, MALLOC_CAP_DMA)`.
- **Forgetting to call `ledc_update_duty()` after `ledc_set_duty()`.** The duty cycle register is double-buffered. Without the update call, the new duty value never takes effect.
- **Ignoring attenuation when reading ADC.** Without proper attenuation configuration, input voltages above the range will be clipped to the maximum raw value, producing incorrect readings.
- **Polling UART in a tight loop without yielding.** This wastes CPU cycles and starves lower-priority tasks. Use the event-driven approach with `uart_driver_install()` and a FreeRTOS queue instead.
- **Not installing the GPIO ISR service before adding handlers.** Calling `gpio_isr_handler_add()` without a prior `gpio_install_isr_service()` call results in `ESP_ERR_INVALID_STATE`.
- **Using high I2C clock speeds with long wires.** Bus capacitance from long wires and multiple devices limits the maximum clock speed. For cables over 30cm, reduce clock speed to 100kHz or lower and add stronger pull-ups.
- **Hardcoding GPIO numbers without considering chip variant.** Pin assignments vary across ESP32, ESP32-S2, ESP32-S3, and ESP32-C3. Use Kconfig or `SOC_GPIO_PIN_COUNT` to write portable code, and consult the specific chip's technical reference manual.

---

## Sources & References

- [ESP-IDF GPIO Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/gpio.html)
- [ESP-IDF ADC Oneshot Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/adc_oneshot.html)
- [ESP-IDF ADC Continuous Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/adc_continuous.html)
- [ESP-IDF LEDC (PWM) Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/ledc.html)
- [ESP-IDF I2C Master Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/i2c.html)
- [ESP-IDF SPI Master Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/spi_master.html)
- [ESP-IDF UART Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/uart.html)
- [ESP-IDF DAC Driver API Reference](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/peripherals/dac.html)
- [ESP32 Technical Reference Manual - IO MUX and GPIO Matrix](https://www.espressif.com/sites/default/files/documentation/esp32_technical_reference_manual_en.pdf)
- [ESP-IDF Programming Guide - DMA Buffer Allocation](https://docs.espressif.com/projects/esp-idf/en/v5.3/esp32/api-reference/system/mem_alloc.html)
