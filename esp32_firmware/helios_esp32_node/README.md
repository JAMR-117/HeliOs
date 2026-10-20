# Firmware ESP32 - Nodo de Actuación y Telemetría HeliOs (SAT)

Este módulo implementa el firmware en C++ para microcontroladores ESP32, encargado del control cinemático de los paneles fotovoltaicos mediante un controlador PWM I2C (PCA9685), la lectura de telemetría de inversores solares mediante Modbus RTU SunSpec (RS-485), la medición de velocidad de viento con anemómetro y la sincronización automática de red Wi-Fi en cascada desde la Raspberry Pi 5.

---

## 1. Conexiones y Pinout de Hardware

| Dispositivo / Sensor | Pin ESP32 | Pin Dispositivo | Descripción |
| :--- | :--- | :--- | :--- |
| **PCA9685 (I2C)** | GPIO 21 | SDA | Bus de datos I2C (Dirección `0x40`) |
| | GPIO 22 | SCL | Bus de reloj I2C |
| | 3V3 / GND | VCC / GND | Alimentación lógica |
| | Fuente Externa (5V-6V) | V+ / GND | Alimentación de potencia de servos |
| **RS-485 (MAX485 / SunSpec)** | GPIO 16 | RO / RXD | Recepción UART Serial2 |
| | GPIO 17 | DI / TXD | Transmisión UART Serial2 |
| | GPIO 4 | DE & RE | Control de dirección TX/RX (Half-Duplex) |
| | 3V3 / GND | VCC / GND | Alimentación del transceptor RS-485 |
| **Anemómetro (Pulsos)** | GPIO 18 | Señal (Pulse) | Interrupción de pulso por efecto Hall / reed switch |
| | GND | GND | Referencia de tierra |

---

## 2. Librerías Requeridas

Para compilar con **Arduino IDE** o **PlatformIO**, instala las siguientes librerías:
1. `WiFi` (integrada en el paquete de placas ESP32 de Espressif)
2. `Preferences` (integrada en el ESP32 Core para almacenamiento NVS)
3. `Wire` (integrada en el ESP32 Core para I2C)
4. `PubSubClient` (por Nick O'Leary)
5. `ArduinoJson` (v6.x o v7.x por Benoit Blanchon)
6. `Adafruit PWM Servo Driver Library` (por Adafruit)
7. `ModbusMaster` (por Doc Walker / 4-20ma)

---

## 3. Arquitectura de Sincronización Wi-Fi en Cascada (NVS)

1. **Arranque:** El ESP32 lee la memoria Flash no volátil (`Preferences.h` / NVS).
2. **Prioridad 1 (Red de Planta):** Si existe un SSID guardado, intenta conectarse durante 15 segundos.
3. **Prioridad 2 (Modo Cautivo / Fallback):** Si no hay credenciales o la red no responde, conmuta a la red **`HeliOs_Setup`** con IP de broker fija `192.168.4.1`.
4. **Sincronización en Caliente:** Al recibir un mensaje MQTT en `helios/esp32/wifi_config`:
   - Almacena las nuevas credenciales (`ssid`, `pass`, `broker_ip`) en NVS.
   - Realiza la reconexión automática en caliente sin necesidad de pulsar botones físicos.

---

## 4. Tópicos MQTT Utilizados

- **Suscripciones del ESP32:**
  - `helios/esp32/wifi_config`: Nuevas credenciales de red y broker emitidas por la Raspberry Pi.
  - `helios/spa/coordinates`: Ángulo objetivo calculado (`target_angle`) y estado de estiba (`is_stow`).
  - `helios/tracker/command`: Comandos manuales (`{"manual_stow": true/false}`).
- **Publicaciones del ESP32:**
  - `helios/inverter/telemetry`: Métricas eléctricas SunSpec (tensión, corriente, potencia, eficiencia, temperatura) y viento.
  - `helios/tracker/status`: Ángulo físico actual, ángulo objetivo, modo estiba, estado de movimiento de motores y RSSI Wi-Fi.
  - `helios/environment/wind`: Velocidad de viento medida en km/h.
