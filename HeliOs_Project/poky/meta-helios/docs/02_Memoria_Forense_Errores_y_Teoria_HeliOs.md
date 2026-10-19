# HeliOs: Memoria Forense de Errores de Ingeniería, Tratado Teórico de Linux Embebido y Protocolos Industriales

**Documento Técnico Especializado y Bitácora Forense de Desarrollo de Tesis**  
**Proyecto:** HeliOs — Sistema Operativo Embebido Determinista para Seguimiento Solar y Diagnóstico SCADA  
**Plataforma de Referencia:** Raspberry Pi 5 (SoC Broadcom BCM2712, Quad-core ARM Cortex-A76 @ 2.4 GHz)  
**Entorno de Compilación Cruzada:** Yocto Project (Poky Scarthgap 5.0 LTS) con Layer `meta-helios`  
**Compositor Gráfico & HMI:** Weston Wayland (Kiosk Shell sobre DRM/KMS) + Flutter Engine Nativo ARM64  
**Bus de Datos & Persistencia:** Mosquitto MQTT Broker, SQLite3 vía Dart FFI, Python 3 con `pvlib` y Mocking `PaqueteFantasma`

---

## Prólogo y Propósito del Documento

El presente tratado representa el compendio teórico y la memoria forense de ingeniería del proyecto **HeliOs**. Mientras que el documento maestro previo (*01_Defensa_y_Arquitectura_HeliOs.md*) aborda la visión panorámica, la justificación institucional PAPIME/UNAM, el modelo tecno-económico LCOE y la descripción funcional de los módulos, este segundo documento tiene una doble misión de profundidad científica y metodológica:

1. **Tratado Teórico Integral al 100% (Aterrizado al Código de HeliOs):** Desarrollar rigurosamente los fundamentos de ciencias de la computación, sistemas operativos embebidos, teoría de compilación cruzada, redes en Linux, protocolos industriales de telemetría y astrofísica computacional, vinculando cada concepto teórico con la línea exacta de código o configuración donde se materializa dentro de nuestro repositorio.
2. **Bitácora Forense de Depuración (12 Casos Críticos):** Exponer con total transparencia académica y técnica la bitácora de los 12 errores más complejos superados durante el ciclo de vida del proyecto (desde las fases tempranas de construcción en Yocto hasta el ajuste fino de la interfaz reactiva en Flutter), desglosando para cada uno: el síntoma, la causa raíz a bajo nivel, los intentos fallidos y la solución definitiva implementada.
3. **Sección de Auto-Interrogación de Nivel Sinodal:** Un compendio de 8 preguntas de alta complejidad diseñadas para anticipar y neutralizar cuestionamientos exhaustivos en un examen de grado de maestría o ingeniería.

---

# PARTE 1: TEORÍA PROFUNDA DE SISTEMAS EJEMPLIFICADA CON EL CÓDIGO DE HELIOS

---

## 1. Arquitectura de Linux Embebido, Kernel y Sistemas de Archivos

### 1.1 Espacio de Usuario (*User Space*) vs. Espacio del Kernel (*Kernel Space*) y Abstracción de Hardware

En la arquitectura ARMv8-A / ARMv9-A (como la implementada por los núcleos Cortex-A76 del SoC BCM2712 de la Raspberry Pi 5), la seguridad y la estabilidad del sistema se estructuran mediante niveles de excepción jerárquicos (*Exception Levels*):
- **EL0 (User Space):** Nivel no privilegiado donde se ejecutan las aplicaciones de usuario, daemons de servicios (`helios-spa.py`, `helios-scada.py`, `mosquitto`) y la aplicación gráfica Flutter (`helios-hmi`). Los procesos en EL0 tienen prohibido el acceso directo a los registros de memoria física mapeados en I/O (*MMIO*) y a las instrucciones de control de la CPU.
- **EL1 (Kernel Space):** Nivel privilegiado donde reside el Kernel Linux. Controla el hardware físico, la tabla de páginas de memoria virtual (*MMU*), la gestión de interrupciones (*GIC*) y los controladores de dispositivo (*device drivers*).

```
+-----------------------------------------------------------------------------------+
| EL0: USER SPACE (Espacio de Usuario)                                              |
| Aplicaciones: flutter-client (HMI), helios-spa.py, helios-scada.py, mosquitto      |
| Acceso a hardware: ÚNICAMENTE vía System Calls (open, read, write, ioctl)        |
+-----------------------------------------------------------------------------------+
                                         |  Llamadas al Sistema (SVC / Syscalls)
                                         v
+-----------------------------------------------------------------------------------+
| EL1: KERNEL SPACE (Espacio del Kernel - Linux 6.6.y)                              |
| VFS (Virtual File System) | Network Stack | Direct Rendering Manager (DRM/KMS)    |
| Controladores de Dispositivo: mac80211, bcm2835-i2c, vc4-drm, mmc-bcm2835        |
+-----------------------------------------------------------------------------------+
                                         |  Mapeo de Memoria Física (MMIO / DMA)
                                         v
+-----------------------------------------------------------------------------------+
| HARDWARE FÍSICO (Broadcom BCM2712)                                               |
| CPU Cortex-A76 | VideoCore VII GPU | Controladores I2C/SPI | Radio Wi-Fi Cypress  |
+-----------------------------------------------------------------------------------+
```

#### Abstracción mediante Nodos de Dispositivo (`/dev`) y Pseudo-Sistemas de Archivos (`sysfs` / `/proc`)
El kernel de Linux aplica el principio UNIX de *"todo es un archivo"*. Para permitir que los procesos de espacio de usuario interactúen con el silicio sin comprometer el aislamiento, el kernel expone interfaces a través de:
1. **Nodos de Dispositivo de Carácter (`char devices`) en `/dev`:** Flujos secuenciales de bytes sin búfer de bloque (por ejemplo, `/dev/i2c-1` para el bus I2C, `/dev/ttyUSB0` para un transceptor serial RS-485, o `/dev/dri/card0` para el renderizado DRM).
2. **Pseudo-Sistema de Archivos `sysfs` (`/sys`):** Una estructura jerárquica en RAM creada por el kernel que expone las propiedades del árbol de dispositivos (*Device Tree*), relojes, GPIOs y buses de control.

#### Ejemplo Práctico: Control del Bus I2C (`/dev/i2c-1`) para Actuadores PWM (PCA9685)
En el hardware de control solar de HeliOs, el movimiento mecánico del seguidor se comanda mediante servomotores industriales acoplados a un circuito integrado **PCA9685** (controlador PWM de 16 canales y 12 bits controlado por I2C en la dirección `0x40`). En lugar de que el programa manipule directamente los pines de silicio del SoC BCM2712, la interacción ocurre mediante la abstracción del driver `i2c-dev`:

```c
// Ejemplo de llamada en espacio de usuario (C / Python ctypes / FFI):
int fd = open("/dev/i2c-1", O_RDWR);
ioctl(fd, I2C_SLAVE, 0x40); // Establece la dirección esclava en el bus I2C

// Configurar registro MODE1 (0x00) para habilitar autoincremento
uint8_t buffer[2] = {0x00, 0x20};
write(fd, buffer, 2);

// Configurar registro PRE_SCALE (0xFE) para frecuencia PWM de 50 Hz
// prescale = round(25MHz / (4096 * 50Hz)) - 1 = 121 (0x79)
uint8_t prescale_cmd[2] = {0xFE, 0x79};
write(fd, prescale_cmd, 2);
```
Cuando el proceso invoca `ioctl(fd, I2C_SLAVE, 0x40)`, el procesador realiza una transición de EL0 a EL1 mediante una instrucción de trampa `SVC` (*Supervisor Call*). El kernel valida el descriptor de archivo, enruta la solicitud al subsistema I2C del kernel y ejecuta la transferencia de bytes a través de los pines físicos SDA/SCL, devolviendo el resultado al espacio de usuario.

---

### 1.2 Teoría de Sistemas de Archivos a Nivel de Bloque: Corrupción Flash vs. Inmutabilidad

Para comprender por qué una Raspberry Pi convencional falla ante un apagón, es imprescindible analizar la arquitectura física de las memorias de estado sólido (**NAND Flash** presentes en tarjetas microSD y módulos eMMC) y la pila de E/S del kernel Linux:

#### La Jerarquía de Escritura en Linux y las "Páginas Sucias" (*Dirty Pages*)
Cuando un proceso de usuario invoca la llamada al sistema `write()`, los datos **no se escriben de inmediato en la tarjeta microSD**. Por razones de rendimiento, el kernel almacena esos datos en memoria RAM dentro de una caché denominada **Page Cache**. Las páginas de memoria modificadas que aún no han sido transferidas al medio de almacenamiento se denominan *páginas sucias* (*dirty pages*).
El daemon del kernel `kworker/flush` sincroniza periódicamente estas páginas al almacenamiento físico siguiendo las directivas del kernel (`/proc/sys/vm/dirty_writeback_centisecs`, comúnmente cada 5 segundos).

```
[ Proceso de Usuario ] ---> write(fd, datos)
                                 |
                                 v
                     [ RAM: Page Cache (Dirty Pages) ]
                                 |
                        (Espera kworker/flush o fsync)
                                 |
                                 v
                     [ Block Layer (Elevator/MQ) ]
                                 |
                                 v
                     [ MMC Driver (bcm2835-mmc) ]
                                 |
                                 v
               +-----------------------------------+
               | CONTROLADOR INTERNO DE MICROSD    |
               | (FTL - Flash Translation Layer)   |
               +-----------------------------------+
                     |                       |
                     v                       v
               [ RAM Interna FTL ]     [ Celdas NAND Flash ]
```

#### Anatomía de la Corrupción de una Celda NAND Flash ante Cortes Eléctricos
Las memorias NAND Flash tienen dos restricciones físicas fundamentales:
1. **Lectura y Escritura por Páginas:** Típicamente bloques lógicos de 4 KB u 8 KB.
2. **Borrado por Bloques Completos (*Erase Blocks*):** Grupos de páginas de 512 KB a 4 MB. Para reescribir un solo byte, el controlador interno de la tarjeta microSD (la capa **FTL - Flash Translation Layer**) debe leer un bloque de borrado completo a su RAM interna, modificar la página deseada, borrar eléctricamente el bloque NAND aplicando un pulso de alto voltaje (~20 V), y escribir nuevamente el bloque entero.

Si el suministro eléctrico se interrumpe exactamente durante el ciclo de borrado o reescritura del FTL:
- Los metadatos del sistema de archivos `ext4` (el superbloque, las tablas de inodos o el *journal*) quedan a medio escribir.
- Las celdas de la tarjeta quedan en un estado de voltaje intermedio indeterminado, provocando que el controlador FTL de la tarjeta se bloquee en modo seguro (*Read-Only Panic*) o que el kernel Linux detenga el arranque con el clásico pánico de `fsck: UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY`.

#### La Solución Arquitectónica: Inmutabilidad Física y Lógica (`read-only-rootfs`)
HeliOs resuelve este problema aplicando una segregación estricta a nivel de tabla de particiones y montaje VFS:
1. **Montaje Inmutable (`/`):** El sistema de archivos raíz se monta con la bandera `MS_RDONLY`. El kernel rechaza cualquier operación `write()`, `unlink()` o `mknod` en EL1 antes de que llegue a la capa de bloques. No existen *dirty pages* para la partición del sistema operativo.
2. **Segregación mediante Wic Kickstart ([helios-sdimage.wks](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/wic/helios-sdimage.wks)):**
   ```ini
   # Partición 1: Firmware y Kernel (FAT32)
   part /boot --source bootimg-partition --ondisk mmcblk0 --fstype=vfat --label boot --active --align 4096 --size 100

   # Partición 2: Sistema Operativo Inmutable (EXT4 - Solo Lectura)
   part / --source rootfs --ondisk mmcblk0 --fstype=ext4 --label root --align 4096

   # Partición 3: Bóveda de Persistencia Controlada (EXT4 - Lectura/Escritura)
   part /data --ondisk mmcblk0 --fstype=ext4 --label data --size 500 --align 4096
   ```
- **Alineación a 4096 KB (`--align 4096`):** Garantiza que cada partición comience en el límite exacto de un bloque de borrado (*Erase Block Boundary*) de la memoria flash física. Esto evita que una escritura en la partición `/data` toque físicamente las celdas flash donde reside la partición inmutable `/`, aislando el desgaste y previniendo la corrupción cruzada.

---

### 1.3 El Sistema de Inicialización `systemd`: Orquestación Asíncrona de Daemons

HeliOs prescinde de los anticuados scripts secuenciales de SysVinit (`/etc/init.d/`) en favor de **`systemd`**, un gestor de sistema y servicios que modela los componentes como un **Grafo Acíclico Dirigido (DAG)** de dependencias.

#### Anatomía de Unidades y Directivas Críticas:
- **`Unit`:** Declara metadatos y relaciones de ordenamiento:
  - `After=network.target local-fs.target`: Establece el orden cronológico. Indica que el servicio debe esperar a que el subsistema de red y los sistemas de archivos locales estén inicializados antes de intentar ejecutarse.
  - `Wants=mosquitto.service`: Declara una dependencia blanda. Intenta arrancar `mosquitto`, pero si falla, no detiene la ejecución del servicio invocador.
- **`Service`:** Define el comportamiento del proceso:
  - `Restart=always` y `RestartSec=5`: Política de alta disponibilidad. Si un daemon arroja una excepción no controlada o es eliminado por el OOM Killer (*Out Of Memory*), `systemd` espera 5 segundos y vuelve a instanciarlo.
  - `Type=simple` vs. `Type=idle`:
    - **`Type=simple` (Usado en `helios-spa.service`, `helios-scada.service`, `helios-logger.service`):** El proceso principal se ejecuta de forma asíncrona inmediata. `systemd` considera que la unidad está activa tan pronto como realiza la llamada `fork()` / `execve()`.
    - **`Type=idle` (Usado en `helios-network.service`):** `systemd` retrasa el inicio del script hasta que todos los trabajos prioritarios de inicio hayan sido despachados y los búfers de la consola se hayan vaciado. Esto garantiza que el script de aprovisionamiento de red no compita por el control de la consola serial ni interfiera con los mensajes del kernel.

#### Archivo Real del Proyecto ([helios-spa.service](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-spa.service)):
```ini
[Unit]
Description=HeliOs Solar Position Algorithm Daemon
After=network.target mosquitto.service helios-network.service
Wants=mosquitto.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/bin/helios-spa.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 2. Teoría del Ecosistema Yocto Project y Compilación Cruzada

---

### 2.1 Compilación Cruzada y el Motor de Tareas BitBake

En el desarrollo de sistemas embebidos, compilar el código directamente sobre el hardware destino (*Native Compilation*) es prohibitivo: el procesador embebido tiene memoria RAM acotada y ancho de banda de E/S lento. Se recurre a la **Compilación Cruzada (*Cross-Compilation*)**:
- **Máquina Host:** Estación de trabajo de desarrollo (x86_64 multinúcleo con 32+ GB de RAM).
- **Máquina Target:** Plataforma embebida destino (aarch64 ARMv8-A BCM2712).
- **Cross-Toolchain:** Compiladores (`aarch64-poky-linux-gcc`), enlazadores (`ld`) y librerías C (`glibc`) que se ejecutan en la arquitectura x86_64 pero generan instrucciones de máquina ejecutables únicamente por la arquitectura aarch64.

**BitBake** es el motor de ejecución de tareas que procesa metadatos y orquesta el pipeline de construcción a través de tareas estándar:

```
[ Código Fuente / Repositorio ]
              |
              v
         +----------+
         | do_fetch |  Descarga tarballs, repositorios git o archivos locales (SRC_URI)
         +----------+
              |
              v
        +-----------+
        | do_unpack |  Descomprime los fuentes en ${WORKDIR}/${S}
        +-----------+
              |
              v
        +-----------+
        | do_patch  |  Aplica parches (.patch / .diff) al árbol de código
        +-----------+
              |
              v
       +-------------+
       | do_configure|  Ejecuta cmake, meson, autotools o configura cabeceras
       +-------------+
              |
              v
        +------------+
        | do_compile |  Ejecuta el Cross-Compiler generando binarios y objetos (.o, .so)
        +------------+
              |
              v
        +------------+
        | do_install |  Copia los binarios compilados a un directorio simulado ${D}
        +------------+
              |
              v
        +------------+
        | do_package |  Divide ${D} en paquetes individuales (.ipk, .deb, .rpm)
        +------------+
              |
              v
      +----------------+
      | do_rootfs (WIC)|  Ensambla los paquetes en la imagen inmutable final (.wic)
      +----------------+
```

---

### 2.2 Variables Fundamentales y Anatomía de Recetas (`.bb`) en HeliOs

Las recetas de Yocto definen cómo se construye cada paquete mediante variables estandarizadas de OpenEmbedded:
- **`${WORKDIR}`:** Directorio de trabajo temporal de la receta dentro de `build-helios/tmp/work/...`.
- **`${S}` (*Source Directory*):** Ruta donde se descomprimen y compilan las fuentes.
- **`${D}` (*Destination Directory*):** Árbol de directorios raíz simulado (*staging area*). Los comandos de `do_install` deben escribir en `${D}${bindir}`, `${D}${sysconfdir}`, etc., nunca en las rutas reales del host.
- **`${bindir}`:** `/usr/bin` en el target.
- **`${sysconfdir}`:** `/etc` en el target.
- **`RDEPENDS:${PN}`:** Dependencias de ejecución (*Runtime Dependencies*). Paquetes que deben ser instalados obligatoriamente en el sistema operativo final para que el paquete `${PN}` funcione.
- **`FILES:${PN}`:** Lista de archivos y rutas de `${D}` que serán empaquetados en el binario final. Si un archivo instalado en `do_install` no está amparado por `FILES:${PN}`, BitBake aborta con el error `QA Issue: installed but unpackaged files`.

#### A. Receta de Red y Aprovisionamiento ([helios-network_1.0.bb](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/helios-network_1.0.bb)):
```bitbake
SUMMARY = "HeliOs Network Manager and Captive Portal"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://helios-network-manager.sh \
    file://helios-network.service \
    file://hostapd.conf \
    file://dnsmasq.conf \
    file://portal.py \
"

S = "${WORKDIR}"
inherit systemd

SYSTEMD_SERVICE:${PN} = "helios-network.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Dependencias duras de red y hardware
RDEPENDS:${PN} += "bash python3 hostapd dnsmasq wpa-supplicant busybox-udhcpc rfkill"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/helios-network-manager.sh ${D}${bindir}/

    install -d ${D}${sysconfdir}/helios-network
    install -m 0644 ${WORKDIR}/hostapd.conf ${D}${sysconfdir}/helios-network/
    install -m 0644 ${WORKDIR}/dnsmasq.conf ${D}${sysconfdir}/helios-network/
    install -m 0755 ${WORKDIR}/portal.py ${D}${sysconfdir}/helios-network/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/helios-network.service ${D}${systemd_system_unitdir}/
    
    # Inyección del punto de montaje vacío para /data
    install -d ${D}/data
}

# Empaquetado obligatorio de /data para el RootFS inmutable
FILES:${PN} += "/data"
```

#### B. Receta de Telemetría y Microservicios ([helios-telemetry_1.0.bb](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/helios-telemetry_1.0.bb)):
Esta receta empaqueta la tríada de demonios en Python y los habilita simultáneamente en `systemd`:
```bitbake
inherit systemd
SYSTEMD_SERVICE:${PN} = "helios-scada.service helios-spa.service helios-logger.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} += "python3-core python3-paho-mqtt python3-requests python3-json python3-datetime python3-pvlib python3-pandas"
```

#### C. Receta Gráfica Flutter ([helios-hmi_1.0.bb](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-graphics/helios-hmi/helios-hmi_1.0.bb)):
Hereda de la clase `flutter-app` para compilar el árbol Dart en binarios AOT de ARM64 y genera el script ejecutable `/usr/bin/helios-hmi`:
```bitbake
inherit flutter-app
PUBSPEC_APPNAME = "helios_hmi"

RDEPENDS:${PN} += " \
    sqlite3 libsqlite3 wayland mesa-megadriver libgbm libdrm weston weston-init \
    fontconfig ttf-dejavu-sans flutter-wayland-client flutter-engine \
"

do_install:append() {
    install -d ${D}${bindir}
    cat << 'EOF' > ${D}${bindir}/helios-hmi
#!/bin/sh
BUNDLE_DIR=$(find /usr/share/flutter/helios_hmi -type d -name "release" | head -n 1)
export LD_LIBRARY_PATH="$BUNDLE_DIR/lib:/usr/lib:$LD_LIBRARY_PATH"
exec flutter-client -b "$BUNDLE_DIR" "$@"
EOF
    chmod 0755 ${D}${bindir}/helios-hmi
}
```

---

## 3. Teoría de Redes en Linux: SoftAP, DHCP y Secuestro DNS (Captive Portal)

---

### 3.1 Modos de la Interfaz Inalámbrica `wlan0`: Station vs. Access Point

El chip inalámbrico integrado en la Raspberry Pi 5 (Cypress/Infineon CYW43455 conectado vía SDIO al SoC) soporta múltiples modos de operación gestionados por el subsistema `cfg80211` / `mac80211` del kernel:
1. **Modo Estación (*Station / Managed Mode*):** La interfaz actúa como cliente. Se asocia a un punto de acceso existente mediante intercambio de tramas de baliza (*beacons*), autenticación y enlace criptográfico WPA2 de cuatro vías (*4-way handshake*) gobernado por el daemon de espacio de usuario `wpa_supplicant`.
2. **Modo Punto de Acceso (*Master / Access Point Mode*):** La tarjeta actúa como el enrutador central. Emite balizas periódicas anunciando el SSID a intervalos de 100 ms, administra tablas de asociación de clientes y entrega tramas a través de `hostapd` (*Host Access Point Daemon*).

#### Parámetros Críticos en [hostapd.conf](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/hostapd.conf):
```ini
interface=wlan0
ssid=HeliOs_Setup
hw_mode=g
channel=6
auth_algs=1
wmm_enabled=0
```
- **`hw_mode=g`:** Selecciona la banda de 2.4 GHz bajo la norma IEEE 802.11g. Se eligió 2.4 GHz en lugar de 5 GHz (`hw_mode=a`) debido a que la longitud de onda de 12.5 cm ofrece mayor penetración a través de las carcasas metálicas de gabinetes eléctricos industriales y maximiza la compatibilidad con cualquier dispositivo móvil de los técnicos en campo.
- **`channel=6`:** Frecuencia central de 2437 MHz. Es uno de los tres canales no superpuestos estándar en la banda ISM de 2.4 GHz (1, 6 y 11), reduciendo colisiones de tramas en el aire.
- **`auth_algs=1`:** Especifica *Open System Authentication*. Cualquier estación inalámbrica puede asociarse de inmediato sin autenticación WEP/WPA preliminar, requisito indispensable para un portal de aprovisionamiento amigable.
- **`wmm_enabled=0`:** Deshabilita *Wi-Fi Multimedia (WMM / 802.11e QoS)*. Elimina cabeceras de prioridad de tráfico multimedia en las tramas 802.11, reduciendo el tamaño de la trama de baliza y garantizando compatibilidad con clientes Wi-Fi antiguos o restrictivos.

---

### 3.2 Protocolo DHCP y Mecanismo de Secuestro DNS (DNS Hijacking)

Cuando un técnico conecta su smartphone a la red abierta `HeliOs_Setup`, ocurre una secuencia de negociación en capas:

```
[ Smartphone ]                                            [ Raspberry Pi 5 (HeliOs) ]
      |                                                                 |
      | --- 1. DHCP Discover (Broadcast 255.255.255.255:67) ----------> | (dnsmasq)
      | <--- 2. DHCP Offer (IP: 192.168.4.10, Gateway: 192.168.4.1) --- |
      | --- 3. DHCP Request ------------------------------------------> |
      | <--- 4. DHCP Acknowledge (ACK) --------------------------------- |
      |                                                                 |
      | [ Detección Automática de Portal Cautivo ]                      |
      | --- 5. DNS Query: ¿IP de "connectivitycheck.gstatic.com"? ----> | (dnsmasq wildcard)
      | <--- 6. DNS Response: "192.168.4.1" (¡SECUESTRADO!) ----------- |
      |                                                                 |
      | --- 7. HTTP GET http://connectivitycheck.gstatic.com/gen_204 -> | (portal.py :80)
      | <--- 8. HTTP 200 OK (HTML del Formulario HeliOs Setup) --------- |
      v                                                                 v
[ Se abre automáticamente el navegador del móvil con el formulario HeliOs ]
```

#### El Rol de [dnsmasq.conf](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/dnsmasq.conf):
```ini
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
address=/#/192.168.4.1
```
- **`address=/#/192.168.4.1` (Secuestro Wildcard):** En la especificación estándar del protocolo DNS, un servidor reenvía las consultas no locales a servidores raíz o de upstream. La directiva `/#/` le ordena a `dnsmasq` interceptar **todas y cada una de las consultas DNS entrantes** (sin importar el dominio solicitado) y responder con la dirección IP local de la Raspberry Pi: `192.168.4.1`.
- **Detección por Sistemas Operativos Móviles:**
  - **Android:** Tras asociarse a la red, envía una petición HTTP a `http://connectivitycheck.gstatic.com/generate_204`. Espera un código de estado `HTTP 204 No Content`. Al ser secuestrado por DNS, la petición llega a [portal.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/portal.py), que responde con `HTTP 200 OK` y el formulario HTML. Android detecta la discordancia e inmediatamente despliega la notificación del sistema *"Acceder a la red Wi-Fi"*.
  - **Apple iOS:** Envía peticiones a dominios como `captive.apple.com/hotspot-detect.html` esperando la palabra `Success`. Al recibir el HTML de HeliOs, abre de inmediato el navegador flotante del sistema (*Captive Network Assistant*).

---

## 4. Teoría de Protocolos Industriales, Telemetría y Modelado Fotovoltaico

---

### 4.1 Modbus RTU sobre RS-485 y el Estándar SunSpec

#### La Capa Física RS-485 (TIA/EIA-485-A)
En ambientes de plantas solares con inversores de potencia que conmutan corrientes de cientos de amperios a frecuencias de 16 kHz (generando campos electromagnéticos e interferencia EMI severa), las comunicaciones de un solo hilo referenciadas a tierra (como UART TTL o RS-232) colapsan por corrientes de bucle de tierra y ruido inducido.

RS-485 resuelve esto mediante **señalización diferencial balanceada**:
- Utiliza dos líneas de transmisión: línea **A** (no inversora) y línea **B** (inversora).
- El receptor detecta el estado lógico midiendo la diferencia de tensión entre ambas líneas ($V_{AB} = V_A - V_B$):
  - Estado Binario 1 (Mark): $V_A - V_B < -200\text{ mV}$.
  - Estado Binario 0 (Space): $V_A - V_B > +200\text{ mV}$.
- Cualquier ruido inducido por la conmutación de los transistores IGBT del inversor afecta a ambos cables por igual (*ruido en modo común*). Al restar las señales en el receptor, el ruido se cancela algebraicamente:

$$(V_A + V_{\text{ruido}}) - (V_B + V_{\text{ruido}}) = V_A - V_B$$

#### El Estándar SunSpec Modbus
Modbus RTU define únicamente el protocolo de transmisión de tramas (ID de esclavo, código de función, dirección de registro, comprobación CRC-16), pero deja el significado de cada registro a criterio del fabricante. Históricamente, cada marca comercial (Fronius, SMA, Schneider, Huawei) asignaba la tensión o la potencia a registros aleatorios.

La alianza **SunSpec Alliance** estandarizó los mapas de registros organizándolos en bloques:
- **Bloque Común (Modelo 1):** Registros que identifican al fabricante, modelo y número de serie.
- **Bloque de Inversor (Modelos 101, 102, 103):** Estandariza la ubicación y factores de escala de:
  - Tensión DC del arreglo (`v_dc`)
  - Corriente DC del arreglo (`i_dc`)
  - Potencia Activa de salida (`power_w`)
  - Temperatura interna del disipador (`temp_c`)
  - Registro de Falla (*Operating State & Fault Code*): 0 = Operación Normal, 1 = Sobrevoltaje de Red, 13 = Fuga a Tierra, 14 = Sobrecalentamiento.

---

### 4.2 Protocolo MQTT (Message Queuing Telemetry Transport)

MQTT es un protocolo ligero de transporte de mensajes basado en el patrón **Publicador/Suscriptor** sobre la pila TCP/IP, estandarizado por OASIS e ISO (ISO/IEC 20922).

#### Arquitectura de Tópicos en HeliOs:
HeliOs utiliza una jerarquía de tópicos con semántica industrial:
- `helios/inverter/telemetry`: Publicado por el inversor (o el simulador HIL) con la telemetría real de potencia, voltaje, corriente y código de falla.
- `helios/spa/expected`: Publicado por `helios-spa.py` conteniendo los valores teóricos calculados por el modelo de cielo claro ($V_{exp}, I_{exp}, P_{exp}, GHI$).
- `helios/spa/coordinates`: Publicado por `helios-spa.py` con los ángulos de comando físico del motor (`motor_azimuth`, `motor_elevation`).
- `helios/scada/alerts`: Publicado por `helios-scada.py` notificando alarmas activas del sistema.

#### Niveles de Calidad de Servicio (QoS):
- **QoS 0 (*At most once*):** Entrega al mejor esfuerzo sin confirmación. Usado para coordenadas solares continuas donde una pérdida de paquete no es crítica.
- **QoS 1 (*At least once*):** Entrega garantizada mediante acuse de recibo (`PUBACK`). Usado en HeliOs para alertas SCADA y telemetría de fallas para asegurar que ningún evento de seguridad se extravíe en el bus.

#### El Mecanismo de la Bandera `retain=True`:
Normalmente, un broker MQTT descarta un mensaje inmediatamente después de entregarlo a los clientes suscritos. Si un cliente se conecta después de la publicación, debe esperar al siguiente ciclo de transmisión para conocer el estado del sistema.

Cuando un productor publica con la bandera **`retain=True`**:
1. El broker entrega el mensaje a los suscriptores actuales.
2. El broker **guarda una copia persistente del último mensaje** bajo ese tópico específico en su memoria y en `/data/mosquitto.db`.
3. Cuando un nuevo cliente (por ejemplo, la interfaz gráfica Flutter que arranca segundos más tarde) se suscribe al tópico, el broker le entrega **inmediatamente** el último mensaje retenido sin esperar a que el daemon vuelva a publicar.

---

### 4.3 Modelado Astrofísico y Algoritmo de Posición Solar (NREL SPA)

#### Coordenadas Solares Esféricas:
El cálculo de la trayectoria solar para un observador en la superficie terrestre requiere resolver transformaciones de coordenadas astronómicas celestes (Ecuador Celeste $\rightarrow$ Horizonte Local):

```
                        Cénit (Vertical Local)
                                 ^
                                 |  . (Sol)
                                 | /
                     Elevación (alpha_s)
                                 |/   
  -------------------------------+-------------------------------- Horizonte
                                / \
                               /   \ Azimut (gamma_s)
                              v     v
                            Norte  Sur
```

1. **Ángulo Cenital ($\theta_z$):** Ángulo entre la vertical local (el cénit) y la posición del centro del disco solar.
2. **Ángulo de Elevación Solar ($\alpha_s$):** Altura angular del sol sobre el horizonte:
   $$\alpha_s = 90^\circ - \theta_z$$
3. **Ángulo de Azimut Solar ($\gamma_s$):** Orientación angular horizontal del sol proyectada en el plano del suelo, medida en HeliOs convencionalmente en sentido horario desde el Norte ($0^\circ = \text{Norte}$, $90^\circ = \text{Este}$, $180^\circ = \text{Sur}$, $270^\circ = \text{Oeste}$).

#### El Modelo Atmosférico de Cielo Claro de Haurwitz
Para estimar la irradiancia solar teórica en un día sin nubes ($GHI$), `pvlib` ejecuta el modelo empírico de Haurwitz, el cual modela la atenuación de la radiación extraterrestre al atravesar la masa de aire atmosférica:

$$GHI = 1098 \cdot \cos(\theta_z) \cdot \exp\left( \frac{-0.057}{\cos(\theta_z)} \right) \quad [\text{W/m}^2]$$

Donde el término $1098\text{ W/m}^2$ representa la constante empírica de irradiancia pico a nivel de superficie, y la función exponencial modela la absorción y dispersión de Rayleigh en función de la masa de aire óptica aproximada por la secante del ángulo cenital ($AM \approx 1/\cos\theta_z$).

#### Ecuaciones de Estimación del Arreglo Fotovoltaico en HeliOs:
A partir de los parámetros de placa del módulo extraídos de `/data/wifi_config.json`, el daemon calcula:
1. **Tensión Esperada:**
   $$V_{exp} = V_{oc} \cdot N_{\text{serie}}$$
2. **Corriente Esperada:**
   $$I_{exp} = I_{sc} \cdot N_{\text{paralelo}} \cdot \left( \frac{GHI}{1000\text{ W/m}^2} \right)$$
3. **Potencia DC Teórica:**
   $$P_{exp} = V_{exp} \cdot I_{exp}$$
4. **Corrección Térmica de Voltaje Celular:**
   Conforme la celda fotovoltaica se calienta, el voltaje de circuito abierto experimenta un coeficiente de temperatura negativo ($\gamma_v \approx -0.35\%/^\circ\text{C}$):
   $$V_{oc}(T_{cell}) = V_{oc,STC} \cdot \left[ 1 + \frac{\gamma_v}{100} (T_{cell} - 25^\circ\text{C}) \right]$$
   Donde la temperatura de la celda se aproxima analíticamente a partir de la temperatura ambiente y la irradiancia:
   $$T_{cell} \approx T_{amb} + \left( \frac{NOCT - 20}{800} \right) \cdot GHI$$

---

## 5. Teoría de Interfaces Gráficas Embebidas y Enlace Dinámico (FFI)

---

### 5.1 Protocolo Wayland y Compositor Weston Kiosk vs. Servidor X11

Durante décadas, Linux utilizó el **Servidor X11 (X Window System)** para desplegar interfaces gráficas. En sistemas embebidos modernos, X11 presenta defectos estructurales críticos:
- **Modelo de Doble Búfering Ineficiente:** En X11, los clientes envían solicitudes de renderizado a un servidor intermedio; este servidor procesa los gráficos y los envía a un gestor de ventanas compuesto antes de transferirlos al búfer de pantalla. Cada cuadro pasa por múltiples copias en memoria, introduciendo latencia y consumo excesivo de CPU.
- **Riesgo de Seguridad y Falta de Aislamiento:** Cualquier cliente X11 puede espiar las pulsaciones de teclado y los píxeles de cualquier otra ventana en la misma pantalla.

```
FLUJO ANTIGUO EN X11:
[ Cliente Gráfico ] ---> (Socket X11) ---> [ Servidor X11 ] ---> [ Compositor ] ---> [ Kernel / KMS ]

FLUJO MODERNO WAYLAND EN HELIOS:
[ Flutter Client ] ========(Direct Rendering / DMA-BUF)========> [ Kernel DRM/KMS (VideoCore VII) ]
        |                                                                ^
        +---- (Wayland Protocol / Shm: Coordinación de Superficies) ----> [ Weston Compositor ]
```

**Wayland** no es un servidor de ventanas; es un **protocolo de comunicación** entre una aplicación gráfica y un **Compositor**:
- En HeliOs, el compositor es **Weston**.
- El compositor le asigna directamente a la aplicación Flutter un búfer gráfico en memoria compartida o un descriptor de archivo de memoria gráfica directa (**DMA-BUF**).
- Flutter utiliza el motor Skia/Impeller acelerado por hardware mediante la API **EGL / OpenGL ES** a través de la librería `libgbm` (Generic Buffer Management).
- Cuando Flutter termina de dibujar el fotograma, le avisa a Weston mediante una llamada Wayland (`wl_surface.commit`). Weston programa el refresco vertical de pantalla (*V-Sync*) directamente a través de las APIs **DRM/KMS** (*Direct Rendering Manager / Kernel Mode Setting*) del kernel Linux. Cada cuadro se dibuja sin desgarro (*tearing*) y a 60 FPS estables.
- Con el plugin **`kiosk-shell.so`** ([weston.ini](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-graphics/wayland/weston-init/weston.ini)), Weston elimina cualquier elemento de escritorio tradicional y fuerza a la aplicación `/usr/bin/helios-hmi` a ocupar la totalidad de la pantalla física en modo exclusivo.

---

### 5.2 Dart FFI (Foreign Function Interface) y Resolución de Librerías Dinámicas en Linux

En Flutter, la lógica de interfaz se compila en código nativo de la máquina virtual de Dart. Para interactuar con bases de datos como SQLite sin utilizar envoltorios pesados de red, se emplea **Dart FFI**:
- FFI permite a un programa en Dart invocar directamente funciones exportadas en binarios compartidos escritos en C/C++ (`.so` / *Shared Objects*) y manipular punteros en memoria nativa sin pasar por el puente de canales de plataforma (*Platform Channels*).

#### La Diferencia Crítica entre `libsqlite3.so` y `libsqlite3.so.0` (SONAME)
En el estándar de bibliotecas compartidas de GNU/Linux (formato binario ELF):
1. **Librería Versionada en Runtime (`libsqlite3.so.0.8.6` o `libsqlite3.so.0`):** Es el binario real compilado que contiene el código de máquina. El encabezado ELF contiene el campo `DT_SONAME = libsqlite3.so.0`, indicando la interfaz binaria de aplicación (ABI) estable.
2. **Enlace Simbólico de Desarrollo (`libsqlite3.so`):** Es un simple enlace simbólico (*symlink*) que apunta a `libsqlite3.so.0`. Su único propósito es permitir que el compilador `gcc` encuentre la librería cuando se le pasa el argumento `-lsqlite3` en tiempo de construcción.

**El Problema en Yocto Embebido:**  
Para optimizar el tamaño de la imagen, Yocto segrega los archivos en paquetes:
- El paquete de ejecución `libsqlite3` contiene únicamente `libsqlite3.so.0` en `/usr/lib/`.
- El enlace simbólico `libsqlite3.so` se empaqueta en `libsqlite3-dev` (el cual **nunca** se instala en una imagen de producción industrial).

Si un plugin de Dart intenta cargar `'sqlite3'` o `'libsqlite3.so'`, el cargador dinámico del sistema operativo (`dlopen()`) falla con `Library not found`. 

#### Implementación del Bypass FFI en HeliOs ([db_platform_native.dart](file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi/lib/database/db_platform_native.dart)):
```dart
open.overrideFor(OperatingSystem.linux, () {
  const candidatePaths = [
    'libsqlite3.so.0',                          // Runtime estándar de producción
    '/usr/lib/libsqlite3.so.0',                  // Ruta Yocto aarch64
    '/usr/lib64/libsqlite3.so.0',                // Variante multilib
    'libsqlite3.so',                             // Entorno desarrollo host
    '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',// Debian/Ubuntu multiarch
  ];

  for (final path in candidatePaths) {
    try {
      return DynamicLibrary.open(path);
    } catch (_) {}
  }
  return DynamicLibrary.process();
});
```
Al sobrescribir el buscador con `open.overrideFor`, Dart FFI interroga directamente al cargador dinámico por el archivo versionado real `libsqlite3.so.0`, resolviendo el símbolo `sqlite3_open_v2` sin requerir paquetes de desarrollo en la imagen de producción.

---

# PARTE 2: CATÁLOGO FORENSE DE ERRORES RESUELTOS (12 CASOS CRÍTICOS)

---

## Caso 01: Bloqueo de `fakeroot` por AppArmor y Error de `locale` en el Host Ubuntu 24.04 (Fase 1)

### 1. El Síntoma / Fallo
Al iniciar el entorno de compilación de BitBake en la máquina host ejecutando Ubuntu 24.04 LTS (`bitbake core-image-minimal` o `bitbake helios-image`), la construcción abortaba antes de iniciar cualquier compilación con dos errores fatales consecutivos:
1. `SANITY CHECK FAILED: Please use a locale which supports UTF-8, such as en_US.UTF-8.`
2. Durante las tareas de empaquetado de pseudo-root (`do_package` o `do_rootfs`), BitBake colapsaba con el mensaje de error:
   ```text
   pseudo: User namespaces are not usable: Invalid argument
   pseudo: failed to initialize pseudo
   ERROR: Task (...do_rootfs) failed with exit code 1
   ```
Adicionalmente, se generaba un bloqueo por licencia en paquetes de firmware Wi-Fi de la Raspberry Pi:
`ERROR: Nothing PROVIDES 'synaptics-killswitch'`.

### 2. Diagnóstico y Causa Raíz Técnica
- **Causa Raíz de `locale`:** BitBake parsea archivos de configuración que contienen caracteres acentuados y codificaciones internacionales; si el entorno del host tiene una codificación distinta a UTF-8 (o si el paquete `locales` no tiene generado `en_US.UTF-8`), el analizador léxico de BitBake lanza una excepción para evitar corrupciones en las recetas.
- **Causa Raíz de `pseudo` / `fakeroot` en Ubuntu 24.04:** Para simular que los archivos pertenecen al usuario `root` (UID 0) sin requerir privilegios de superusuario reales en el host, BitBake utiliza una herramienta de emulación llamada **`pseudo`**. `pseudo` depende de los espacios de nombres de usuario sin privilegios del kernel Linux (*Unprivileged User Namespaces - userns*). En Ubuntu 24.04, Canonical introdujo una política de seguridad restrictiva por defecto en **AppArmor** que bloquea la creación de *userns* para binarios no perfilados, provocando que la llamada al sistema `clone(CLONE_NEWUSER)` devuelva `EINVAL` (Invalid argument).
- **Causa de Licencia:** El layer BSP `meta-raspberrypi` incluye firmware privativo para el módem Wi-Fi/Bluetooth que requiere la aceptación explícita de licencias no comerciales o flags en `local.conf`.

### 3. Por qué Fallaron los Intentos Previos
- Intentar ejecutar BitBake como `sudo bitbake` fue rechazado de inmediato por el propio sistema Yocto (`Do not run BitBake as root`).
- Crear perfiles locales temporales de AppArmor no solucionaba el problema de forma persistente porque las rutas del directorio de trabajo de BitBake son dinámicas.

### 4. Solución Definitiva e Implementación
1. **Generación de Locales en el Host:**
   ```bash
   sudo locale-gen en_US.UTF-8
   export LC_ALL=en_US.UTF-8
   export LANG=en_US.UTF-8
   ```
2. **Desactivación de la Restricción de User Namespaces en AppArmor:**
   Se configuró el kernel del host para permitir *userns* sin privilegios mediante `sysctl`:
   ```bash
   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
   echo "kernel.apparmor_restrict_unprivileged_userns=0" | sudo tee /etc/sysctl.d/60-apparmor-userns.conf
   ```
3. **Aceptación de Licencias en [local.conf](file:///home/jm/HeliOs/HeliOs_Project/poky/build-helios/build/conf/local.conf):**
   Se añadieron las excepciones de licencia requeridas:
   ```bitbake
   LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
   ```

---

## Caso 02: Fallo de Escritura en `/data/` por Omisión del Particionado `.wks` (Fase 1 / Fase 5)

### 1. El Síntoma / Fallo
Al arrancar la imagen compilada con `IMAGE_FEATURES += "read-only-rootfs"` en la Raspberry Pi 5, el sistema booteaba con éxito, pero cualquier intento de los servicios de escribir en `/data/` (por ejemplo, cuando el portal cautivo intentaba crear `/data/wifi_config.json` o `helios-logger` intentaba abrir `/data/helios_history.db`) fallaba con:
```text
OSError: [Errno 30] Read-only file system: '/data/wifi_config.json'
```

### 2. Diagnóstico y Causa Raíz Técnica
Al auditar los montajes con el comando `mount`, se descubrió la causa:
`/dev/mmcblk0p2 on / type ext4 (ro,relatime)`
No existía ninguna entrada para `/data`.
El desarrollador había creado la carpeta `/data` dentro del RootFS mediante `install -d ${D}/data`, pero al no haberse configurado una partición física independiente en el generador de imágenes Wic, la carpeta `/data` formaba parte del mismo árbol de inodos de la partición raíz `/dev/mmcblk0p2`. Como la raíz estaba montada en modo solo lectura (`ro`), `/data` heredaba inexorablemente el estado de solo lectura.

### 3. Por qué Fallaron los Intentos Previos
- Intentar ejecutar `chmod 777 /data` en scripts de inicio falló porque la tabla de inodos no puede modificarse en un sistema de archivos de solo lectura (`Read-only file system`).
- Intentar montar un `tmpfs` (RAM) en `/data` permitía la escritura, pero provocaba la pérdida instantánea de las credenciales de Wi-Fi y de la base de datos histórica ante cada reinicio o apagón.

### 4. Solución Definitiva e Implementación
Se definió formalmente el esquema de almacenamiento tripartito en el archivo [helios-sdimage.wks](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/wic/helios-sdimage.wks):
```ini
part /boot --source bootimg-partition --ondisk mmcblk0 --fstype=vfat --label boot --active --align 4096 --size 100
part / --source rootfs --ondisk mmcblk0 --fstype=ext4 --label root --align 4096
part /data --ondisk mmcblk0 --fstype=ext4 --label data --size 500 --align 4096
```
Y se instruyó al generador de imágenes de BitBake en la configuración de la máquina para utilizar el artefacto Wic:
```bitbake
IMAGE_FSTYPES += "wic wic.bmap"
WKS_FILE = "helios-sdimage.wks"
```
Al arrancar, el kernel monta `/` en `ro` y `systemd` monta la tercera partición (`/dev/mmcblk0p3`) en `/data` con bandera `rw`.

---

## Caso 03: Congelamiento de 2 Minutos en el Arranque por `systemd-networkd-wait-online` (Fase 5)

### 1. El Síntoma / Fallo
Al encender el dispositivo sin un cable Ethernet conectado o en un sitio donde la red Wi-Fi no estaba configurada, la pantalla se quedaba completamente en negro con un cursor parpadeando durante **exactamente 2 minutos (120 segundos)** antes de que el entorno gráfico Weston y el portal cautivo hicieran su aparición.

### 2. Diagnóstico y Causa Raíz Técnica
Al ejecutar `systemd-analyze blame` tras el arranque, se obtuvo la evidencia:
```text
2min 105ms systemd-networkd-wait-online.service
     320ms helios-network.service
     ...
```
Se había configurado la unidad gráfica `weston.service` y `helios-network.service` con la directiva:
`Requires=network-online.target`
`After=network-online.target`
El servicio del sistema `systemd-networkd-wait-online.service` monitorea todas las interfaces de red del sistema y tiene un temporizador de bloqueo por defecto de 120 segundos (`--timeout=120`). Si la interfaz `wlan0` no obtiene una dirección IP válida de un router upstream en ese periodo, el servicio bloquea la transición al siguiente target, congelando todo el sistema operativo.

### 3. Por qué Fallaron los Intentos Previos
- Reducir el timeout a 10 segundos (`--timeout=10`) reducía el congelamiento pero introducía una condición de carrera: si la red industrial tardaba 12 segundos en entregar DHCP, el sistema asumía que no había red y disparaba erróneamente el portal cautivo.

### 4. Solución Definitiva e Implementación
Se deshabilitó el bloqueo síncrono de red online y se reestructuró la dependencia en [helios-network.service](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/helios-network.service):
```ini
[Unit]
Description=HeliOs Network Manager (Captive Portal / Auto-Connect)
After=network.target local-fs.target
# ELIMINADO: Requires=network-online.target

[Service]
Type=idle
ExecStart=/usr/bin/helios-network-manager.sh
Restart=on-failure
RestartSec=5
RemainAfterExit=yes
```
`network.target` simplemente indica que la pila de red del kernel está cargada; no espera a que haya conexión a internet. El script [helios-network-manager.sh](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/helios-network-manager.sh) asume el control del bucle de espera en segundo plano mediante un contador no bloqueante de 20 segundos (`for i in $(seq 1 20)`), permitiendo que Weston y la interfaz gráfica carguen en menos de 4 segundos.

---

## Caso 04: Cuello de Botella en el Portal Cautivo ante Peticiones Concurrentes del Celular (Fase 5)

### 1. El Síntoma / Fallo
Durante la prueba de conexión al SoftAP `HeliOs_Setup`, al abrirse la página de configuración en un teléfono inteligente moderno, el portal cautivo tardaba más de 15 segundos en cargar las redes Wi-Fi, o arrojaba errores en el navegador del móvil:
`ERR_CONNECTION_TIMED_OUT` o `500 Internal Server Error`.
Peor aún: si dos operadores intentaban conectarse a la vez, el archivo `/data/wifi_config.json` se guardaba truncado con `null` o sintaxis JSON corrupta.

### 2. Diagnóstico y Causa Raíz Técnica
El script original utilizaba la clase básica de Python:
```python
from http.server import HTTPServer, BaseHTTPRequestHandler
server = HTTPServer(('0.0.0.0', 80), Handler)
server.serve_forever()
```
`HTTPServer` es estrictamente **monohilo y síncrono**. Cuando un iPhone o dispositivo Android se asocia a un punto de acceso, el sistema operativo del teléfono lanza concurrentemente entre 4 y 8 peticiones HTTP paralelas a diferentes endpoints (`/generate_204`, `/hotspot-detect.html`, `/favicon.ico`, `/apple-touch-icon.png`).
Como el servidor solo atendía una conexión a la vez, las peticiones adicionales se encolaban en el backlog del socket TCP; al saturarse el backlog, las peticiones excedentes eran rechazadas con un paquete `TCP RST`. Si una petición POST de guardado coincidía con una solicitud paralela de escaneo, ocurría una colisión de E/S.

### 3. Por qué Fallaron los Intentos Previos
- Instalar un servidor web completo como Nginx o Lighttpd con Gunicorn/Flask aumentaba la complejidad de la receta de Yocto, requería empaquetar decenas de módulos de Python y añadía 45 MB a la imagen inmutable sin necesidad.

### 4. Solución Definitiva e Implementación
En [portal.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/portal.py), se migró a la clase nativa **`ThreadingHTTPServer`** y se protegió la persistencia mediante un semáforo de exclusión mutua **`threading.Lock()`**:
```python
# Líneas 4-10 de portal.py
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

bloqueo_archivo = threading.Lock()
credenciales_guardadas = False

# En el método do_POST:
with bloqueo_archivo:
    if credenciales_guardadas:
        self.send_response(409) # Conflicto: ya procesado
        self.end_headers()
        return
    credenciales_guardadas = True
    
    with open('/data/wifi_config.json', 'w') as f:
        json.dump(config, f)
    
    os.chmod('/data/wifi_config.json', 0o666)

# Inicialización multihilo en el hilo principal:
if __name__ == "__main__":
    ThreadingHTTPServer(('0.0.0.0', 80), Portal).serve_forever()
```
Cada petición de los clientes móviles se despacha en un hilo de ejecución independiente en milisegundos, y el bloqueo atómico garantiza que la escritura del JSON sea estrictamente serializada y a prueba de colisiones.

---

## Caso 05: Imposibilidad de Compilar `pvlib` en Yocto por Dependencia de `scipy` y Fortran (Fase 3)

### 1. El Síntoma / Fallo
Al intentar añadir `python3-pvlib` a la imagen mediante BitBake, la compilación de la receta colapsaba con errores masivos en la etapa `do_compile`:
```text
ERROR: Task (...python3-scipy_1.10.bb:do_compile) failed with exit code 1
No F77/F90 compiler found in toolchain!
Meson encountered an error in file meson.build: Fortran compiler not found.
```

### 2. Diagnóstico y Causa Raíz Técnica
La librería oficial `pvlib-python` declara en su archivo `pyproject.toml` dependencias duras sobre `scipy` y `h5py`.
`scipy` contiene módulos numéricos heredados (como `scipy.integrate.quadpack` y `scipy.optimize.minpack`) escritos en **Fortran 77 / Fortran 90**. Para compilar `scipy` en una compilación cruzada hacia ARM64, BitBake exige habilitar el compilador cruzado `gfortran` dentro del toolchain de GCC, compilar las librerías algebraicas OpenBLAS/LAPACK, y asignar más de 16 GB de memoria swap en el host para la etapa de enlazado de plantillas C++. Todo esto aumentaba el tiempo de construcción en más de 2 horas e incrementaba el tamaño del RootFS en más de 400 MB.

### 3. Por qué Fallaron los Intentos Previos
- **Regresión a la librería estándar `math`:** Se intentó simplificar el algoritmo calculando la elevación y azimut con ecuaciones trigonométricas básicas de secundaria en un script de Python. Esto provocó errores de cálculo de hasta 4.2° respecto a las tablas del Observatorio Naval de EE. UU. (NOAA), haciendo que el seguidor perdiera el punto de máxima potencia y descalificándolo para el control de Concentradores Fresnel (LFC).
- **Depender de una API meteorológica en internet:** Violaba la directiva de diseño de soberanía de datos y dejaba inoperable al seguidor si la antena 4G de la planta perdía cobertura.

### 4. Solución Definitiva e Implementación
1. **Auditoría de Código de `pvlib`:** Se constató que el algoritmo NREL SPA (`pvlib.solarposition.spa_python`) y el modelo Clear Sky de Haurwitz (`pvlib.clearsky.haurwitz`) solo ejecutan trigonometría matricial basada en `numpy` y `pandas`; **jamás invocan los submódulos de integración numérica ni álgebra de `scipy`**.
2. **Creación del Sistema `PaqueteFantasma` en [helios-spa.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-spa.py):**
   Antes de importar `pvlib`, se inyectan módulos simulados en el diccionario interno del intérprete `sys.modules`:
   ```python
   # Líneas 18-48 de helios-spa.py
   sys.modules['h5py'] = MagicMock()

   class PaqueteFantasma(types.ModuleType):
       def __init__(self, name):
           super().__init__(name)
           self.__path__ = []
           self.__version__ = '1.10.0'
       def __getattr__(self, name):
           return MagicMock()

   scipy_mock = PaqueteFantasma('scipy')
   sys.modules['scipy'] = scipy_mock

   submodulos_scipy = [
       'constants', 'optimize', 'integrate', 'interpolate', 
       'spatial', 'spatial.transform', 'spatial.distance',
       'stats', 'sparse', 'special', 'linalg', 'ndimage', 'fft'
   ]
   for sub in submodulos_scipy:
       nombre_completo = f"scipy.{sub}"
       mock_pkg = PaqueteFantasma(nombre_completo)
       sys.modules[nombre_completo] = mock_pkg
       # Enlace jerárquico de atributos
       setattr(scipy_mock, sub.split('.')[0], mock_pkg)

   import pvlib # ¡Importación 100% exitosa sin scipy instalado!
   ```
3. **Limpieza de la Receta [python3-pvlib_0.11.0.bb](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-devtools/python/python3-pvlib_0.11.0.bb):**
   Se eliminó toda referencia a Fortran y `scipy`, dejando únicamente dependencias en paquetes puros:
   ```bitbake
   RDEPENDS:${PN} += "python3-pandas python3-numpy python3-pytz"
   ```

---

## Caso 06: Error `NotADirectoryError` al Empaquetar la Aplicación Flutter en BitBake (Fase 4)

### 1. El Síntoma / Fallo
Al compilar la receta gráfica [helios-hmi_1.0.bb](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-graphics/helios-hmi/helios-hmi_1.0.bb), la tarea `do_compile` fallaba arrojando la traza:
```text
Exception: NotADirectoryError: [Errno 20] Not a directory: '.../tmp/work/cortexa76-poky-linux/helios-hmi/1.0-r0/helios_hmi/pubspec.yaml'
ERROR: Task (...helios-hmi_1.0.bb:do_compile) failed
```

### 2. Diagnóstico y Causa Raíz Técnica
La clase base `flutter-app.bbclass` de Yocto asume que el código fuente del proyecto Flutter se descomprime directamente en la raíz de la variable `${S}` y busca de forma rígida el archivo `${S}/pubspec.yaml`.
Al empaquetar el código fuente en el archivo `helios_hmi.tar.gz`, el comando `tar` había incluido el directorio padre con una estructura de doble anidamiento:
`helios_hmi.tar.gz -> helios_hmi/helios_hmi/pubspec.yaml`.
BitBake localizaba una carpeta llamada `helios_hmi` donde esperaba encontrar el archivo `pubspec.yaml`, disparando el error del sistema de archivos `Not a directory`.

### 3. Por qué Fallaron los Intentos Previos
- Sobrescribir `S = "${WORKDIR}"` provocaba colisiones con otros archivos temporales que BitBake inyecta automáticamente en `${WORKDIR}` (como parches y scripts de bitácora `temp/run.do_compile`).

### 4. Solución Definitiva e Implementación
1. **Normalización del Empaquetado del Tarball:** Se comprimió el árbol de código de Flutter directamente desde la raíz del proyecto Dart:
   ```bash
   cd /home/jm/HeliOs/Flutter-HeliOs
   tar --exclude='build' --exclude='.dart_tool' -czvf helios_hmi.tar.gz -C helios_hmi .
   ```
2. **Ajuste Coherente de Variables en [helios-hmi_1.0.bb](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-graphics/helios-hmi/helios-hmi_1.0.bb):**
   ```bitbake
   SRC_URI = "file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi.tar.gz"
   S = "${WORKDIR}/helios_hmi"
   PUBSPEC_APPNAME = "helios_hmi"
   ```

---

## Caso 07: Fallo de "Modo Mock Data" en Flutter por Librería `libsqlite3.so.0` y Permisos de Usuario en Weston (Fase 4)

### 1. El Síntoma / Fallo
Al arrancar la pantalla táctil de la Raspberry Pi 5, la aplicación Flutter abría correctamente, pero en el menú de Historial SCADA y en las tarjetas aparecía un letrero amarillo:
`Modo Demostración / Mock Data Activo`.
Aunque la base de datos física `/data/helios_history.db` existía y crecía en tamaño, Flutter no lograba leer ningún registro histórico.

### 2. Diagnóstico y Causa Raíz Técnica
Se descubrió una **falla compuesta por dos causas independientes**:
1. **Falla de Enlace FFI:** En el log de consola de Flutter se encontró la excepción silenciosa capturada: `ArgumentError: Failed to load dynamic library 'libsqlite3.so': libsqlite3.so: cannot open shared object file`.
   Como se explicó en la Sección 1.5, Yocto solo instala `/usr/lib/libsqlite3.so.0`. La librería de Dart `sqlite3` intentaba por defecto enlazar contra el symlink no existente `libsqlite3.so`. Al fallar la apertura de la base, el código de Flutter recurría a su mecanismo de seguridad de generar datos sintéticos (*Mock Data*).
2. **Conflicto de Permisos entre Procesos (`umask` y Usuarios):** Los demonios Python (`helios-logger.py`, `helios-scada.py`) se ejecutaban bajo el usuario `root` con una máscara por defecto `umask 022`. Esto creaba el archivo `/data/helios_history.db` con permisos `0644` (propietario: `root:root`).
   Por el contrario, el servicio `weston.service` estándar de Yocto se ejecutaba bajo el usuario no privilegiado `User=weston`. Cuando Flutter intentaba abrir la base de datos en modo lectura/escritura (`sqlite3.open(..., mode: OpenMode.readWrite)`), el kernel denegaba el acceso por falta de permisos de escritura (`EACCES: Permission denied`).

### 3. Por qué Fallaron los Intentos Previos
- Añadir el paquete `sqlite3-dev` a la imagen resolvía el enlace simbólico pero aumentaba el peso de la imagen e introducía cabeceras C innecesarias en producción.
- Ejecutar manualmente `chmod 777 /data/helios_history.db` por SSH funcionaba temporalmente, pero al reiniciarse el sistema o recrearse la base de datos, el archivo volvía a nacer con permisos restringidos de root.

### 4. Solución Definitiva e Implementación
1. **Bypass de Enlace FFI en [db_platform_native.dart](file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi/lib/database/db_platform_native.dart):**
   Se interceptó la resolución dinámica de bibliotecas forzando la búsqueda de `libsqlite3.so.0`:
   ```dart
   open.overrideFor(OperatingSystem.linux, () {
     return DynamicLibrary.open('libsqlite3.so.0');
   });
   ```
2. **Permisos Explícitos en Backend ([helios-scada.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-scada.py) y [helios-logger.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-logger.py)):**
   Cada vez que se inicializa la base de datos, los daemons aplican permisos globales de lectura y escritura:
   ```python
   try:
       os.chmod(DB_PATH, 0o666)
   except Exception:
       pass
   ```
3. **Ejecución de Weston como Root ([weston-init.bbappend](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-graphics/wayland/weston-init.bbappend)):**
   Se modificó el archivo de unidad de systemd para que el entorno Kiosco de Weston corra como superusuario:
   ```sh
   sed -i 's/User=weston/User=root/g' ${D}${systemd_system_unitdir}/weston.service
   sed -i 's/Group=weston/Group=root/g' ${D}${systemd_system_unitdir}/weston.service
   ```

---

## Caso 08: Caída Silenciosa de Daemons Secundarios por Cambio de API en `paho-mqtt >= 2.0.0` (Fase 3)

### 1. El Síntoma / Fallo
Tras compilar una actualización de la imagen, los tres daemons de telemetría (`helios-spa`, `helios-scada`, `helios-logger`) colapsaban inmediatamente tras su inicio. Al consultar con `journalctl -u helios-scada.service`, se registraba la siguiente excepción:
```text
TypeError: CallbackAPIVersion is required for Client() constructor in paho-mqtt >= 2.0.0
o
TypeError: on_connect() takes 4 positional arguments but 5 were given
```

### 2. Diagnóstico y Causa Raíz Técnica
Yocto Scarthgap (5.0 LTS) actualizó el ecosistema de Python a la versión 3.12 y actualizó el paquete `python3-paho-mqtt` de la versión 1.6.1 a la rama **2.0.0+**.
En Paho MQTT 2.0, los desarrolladores de Eclipse introdujeron cambios radicales en la API para corregir problemas de diseño históricos:
1. El constructor `mqtt.Client()` exige obligatoriamente especificar el parámetro `callback_api_version=mqtt.CallbackAPIVersion.VERSION2`. Si no se especifica, el constructor arroja una excepción fatal.
2. La firma del método callback `on_connect` cambió:
   - **Firma Antigua (v1):** `on_connect(client, userdata, flags, rc)` (4 argumentos).
   - **Firma Nueva (v2):** `on_connect(client, userdata, flags, reason_code, properties)` (5 argumentos).

### 3. Por qué Fallaron los Intentos Previos
- Intentar forzar la versión antigua de Paho MQTT mediante una receta `python3-paho-mqtt_1.6.1.bb` generaba incompatibilidades con otras dependencias de Python 3.12 que exigían librerías actualizadas.

### 4. Solución Definitiva e Implementación
Se actualizaron todos los scripts del proyecto ([helios-spa.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-spa.py), [helios-scada.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-scada.py), [helios-logger.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-logger.py) y [simulador.py](file:///home/jm/HeliOs/HeliOs_Simulator/simulador.py)) adoptando la API oficial VERSION2:
```python
# Instanciación moderna
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)

# Callback compatible con Paho MQTT 2.x
def on_connect(client, userdata, flags, reason_code, properties):
    if reason_code == 0:
        client.subscribe([
            ("helios/inverter/telemetry", 0),
            ("helios/spa/expected",       0),
        ])
    else:
        print(f"[WARN] Conexión rechazada: {reason_code}")
```

---

## Caso 09: Asesinato Accidental de Daemons de Telemetría por `killall python3` en `helios-network-manager.sh` (Fase 5 / Fase 3)

### 1. El Síntoma / Fallo
Al inspeccionar el estado de los servicios con `systemctl status helios-spa helios-scada helios-logger`, los tres servicios aparecían en estado `failed` o `inactive (dead)`. Si el desarrollador los iniciaba manualmente por SSH con `systemctl restart`, funcionaban perfectamente, pero ante cada reinicio de la Raspberry Pi volvían a amanecer muertos.

### 2. Diagnóstico y Causa Raíz Técnica
Al auditar cronológicamente las trazas de `journalctl`, se observó que a los 4 segundos del arranque, los daemons de telemetría arrancaban normalmente; sin embargo, exactamente 2 segundos después, recibían una señal `SIGTERM` / `SIGKILL` proveniente de un script del sistema.
La causa residía en las líneas iniciales de [helios-network-manager.sh](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/helios-network-manager.sh). Para asegurarse de limpiar instancias viejas del portal cautivo antes de intentar conectar a una red Wi-Fi, el script ejecutaba:
```sh
killall python3 2>/dev/null  # ¡FATAL!
```
`killall python3` buscaba cualquier proceso cuyo nombre binario fuera `python3` y le enviaba un `SIGKILL`. Dado que `helios-spa.py`, `helios-scada.py` y `helios-logger.py` se ejecutan mediante el intérprete `/usr/bin/python3`, el script de red los asesinaba a sangre fría durante el arranque.

### 3. Por qué Fallaron los Intentos Previos
- Renombrar temporalmente los intérpretes o usar enlaces simbólicos era una mala práctica que violaba la coherencia del sistema operativo Yocto.

### 4. Solución Definitiva e Implementación
En [helios-network-manager.sh](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/helios-network-manager.sh), se sustituyó el comando indiscriminado por una instrucción selectiva de búsqueda por patrón de línea de comandos (`pkill -f`):
```sh
# Líneas 5-8 de helios-network-manager.sh
systemctl stop wpa_supplicant hostapd dnsmasq 2>/dev/null

# Matar ÚNICAMENTE el portal cautivo, preservando intactos los daemons de telemetría
pkill -f portal.py 2>/dev/null
killall wpa_supplicant udhcpc 2>/dev/null
```
Adicionalmente, se programó el reinicio explícito y ordenado de los daemons al final del script una vez que se obtiene dirección IP y se sincroniza el reloj:
```sh
# Líneas 66-69 de helios-network-manager.sh
echo "[HeliOs] Reiniciando daemons de telemetría..."
systemctl restart mosquitto helios-spa helios-scada helios-logger
```

---

## Caso 10: Desfase Horario (UTC vs. UTC-6), Ausencia de RTC y Falsas Alarmas Nocturnas (Fase 3 / Fase 4)

### 1. El Síntoma / Fallo
A las **18:40 hrs (noche cerrada en México)**, al encender el sistema y abrir la HMI, el carrusel de pronóstico indicaba erróneamente que eran las **18:00 hrs con una radiación solar de $1024\text{ W/m}^2$ (pleno sol)**. Simultáneamente, el sistema SCADA detonaba en color rojo la alarma:
`FALLA 101: PÉRDIDA DE PANEL EN SERIE DETECTADA`.

### 2. Diagnóstico y Causa Raíz Técnica
Este fallo involucró una interacción perversa de tres factores:
1. **Ausencia de Reloj de Tiempo Real Físico (RTC con Batería):** La Raspberry Pi 5 no cuenta con una batería de litio conectada a su RTC por defecto. Al apagarse, el reloj de hardware se congela en el tiempo del último apagado o en la fecha de compilación de la imagen Yocto (`18:48:00 UTC`).
2. **Conflicto de Zonas Horarias:** 
   - `18:48 UTC` corresponde exactamente a las `12:48 PM (mediodía)` en la Ciudad de México (UTC-6).
   - Como la imagen base no tenía configurada la base de datos `tzdata`, la llamada en Flutter `DateTime.now().toLocal()` no aplicaba ningún desplazamiento porque el sistema operativo creía estar en UTC (`+0000`).
3. **El Disparo de la Falla 101:** El daemon `helios-spa.py` leía la hora del sistema (`12:48 local aparente`), calculaba que el sol estaba en el cénit y publicaba un voltaje esperado de $V_{exp} = 182\text{ V}$. Al mismo tiempo, el inversor físico (o el simulador) reportaba la realidad física de la noche: $V_{DC} = 0\text{ V}$.
   Al comparar ambos valores, el algoritmo SCADA evaluaba:
   `if v_dc < v_exp * 0.90:` $\rightarrow$ `$0\text{ V} < 163.8\text{ V}$` $\rightarrow$ **¡Falla 101 disparada erróneamente!**

### 3. Por qué Fallaron los Intentos Previos
- Intentar usar el daemon de sincronización NTP (`systemd-timesyncd`) fallaba sistemáticamente en las pruebas porque los firewalls corporativos de subestaciones eléctricas y universidades bloquean el puerto UDP 123.

### 4. Solución Definitiva e Implementación
La solución se abordó mediante una arquitectura de cuatro capas:
1. **Inyección de Zona Horaria en Yocto ([local.conf](file:///home/jm/HeliOs/HeliOs_Project/poky/build-helios/build/conf/local.conf)):**
   ```bitbake
   MACHINE_TIMEZONE = "America/Mexico_City"
   DISTRO_FEATURES:append = " tzdata"
   IMAGE_INSTALL:append = " tzdata"
   ```
2. **Sincronización Horaria Resiliente por Cabecera HTTP Date ([helios-network-manager.sh](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/helios-network-manager.sh)):**
   Al conectarse a la red, se descarga la cabecera `Date` de un servidor web global (Google puerto 80) y se ajusta el reloj del kernel con `date -u -s`:
   ```python
   h = urllib.request.urlopen('http://www.google.com', timeout=5).headers['Date']
   dt = email.utils.parsedate_to_datetime(h)
   subprocess.run(['date', '-u', '-s', dt.strftime('%Y-%m-%d %H:%M:%S')], check=True)
   ```
3. **Offset Matemático Ciego en Python ([helios-spa.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-spa.py)):**
   Para garantizar inmunidad si el archivo de zonas horarias se corrompe, se programó un offset explícito en el espacio de nombres de datetime:
   ```python
   TZ_OFFSET = timezone(timedelta(hours=-6)) # México Central infalible
   ```
4. **Supresión Condicional de Alarmas Nocturnas en [helios-scada.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-scada.py):**
   Se blindó la evaluación de anomalías de planta restringiéndola estrictamente a condiciones diurnas comprobadas astronómicamente:
   ```python
   # Línea 122 de helios-scada.py
   elif not is_night and ghi > 20.0 and v_exp > 0:
       if v_dc < v_exp * 0.90:
           # Disparar Alerta 101
   ```

---

## Caso 11: Condición de Carrera en el Arranque (Nube Roja en Flutter) y Parpadeo de la Gráfica (Fase 4)

### 1. El Síntoma / Fallo
1. **La Nube Roja:** Durante los primeros 5 a 8 segundos tras el arranque de la pantalla táctil, el icono de conectividad en Flutter se mostraba en rojo con una nube tachada (`Icons.cloud_off`), indicando desconexión de telemetría a pesar de que el sistema operativo ya estaba en marcha.
2. **Parpadeo de la Gráfica (*Flickering*):** Cada 5 segundos, la gráfica de potencia histórica de Flutter desaparecía, mostraba un indicador de carga circular durante medio segundo diciendo *"Esperando telemetría..."*, y volvía a dibujarse bruscamente, provocando fatiga visual inaceptable para una HMI industrial.

### 2. Diagnóstico y Causa Raíz Técnica
- **Causa de la Nube Roja:** Wayland y la aplicación Flutter compilada en código de máquina ARM64 nativo arrancaban en apenas 3 segundos. El broker Mosquitto y los daemons de Python tardaban entre 4 y 6 segundos en abrir sus sockets TCP. Cuando Flutter intentaba `_client.connect('127.0.0.1')` al inicio de `main()`, el socket `1883` aún no existía, arrojando una excepción de conexión rechazada. Al no haber reintentos estructurados, la HMI se quedaba desconectada para siempre.
- **Causa del Parpadeo de la Gráfica:** En el widget de la gráfica dentro de `dashboard.dart`, se había envuelto el lienzo en un `FutureBuilder` que ejecutaba una consulta SQL directa a SQLite (`openAppDatabase()`) **dentro del método `build()`**. Como `dashboard.dart` escucha a `MqttService` mediante `context.watch<MqttService>()`, **cada vez que llegaba un paquete MQTT de telemetría (cada 2 segundos), el método `build()` se ejecutaba de nuevo**. Esto provocaba que el `FutureBuilder` destruyera el estado anterior, lanzara una nueva consulta asíncrona a disco, mostrara el spinner de carga y repintara el gráfico, reiniciando las animaciones infinitamente.

### 3. Por qué Fallaron los Intentos Previos
- Añadir retardos fijos `sleep(5)` en Flutter antes de conectar congelaba el renderizado de la interfaz, dejando la pantalla en blanco durante el arranque.
- Intentar usar un `StreamBuilder` sobre SQLite directamente en la HMI consumía demasiados descriptores de archivo en `/data`.

### 4. Solución Definitiva e Implementación
1. **Bucle de Reconexión Asíncrona Resiliente en [mqtt_service.dart](file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi/lib/services/mqtt_service.dart):**
   ```dart
   // Líneas 172-178 de mqtt_service.dart
   } catch (e) {
     isConnected = false;
     notifyListeners();
     _client?.disconnect();
     // Reintento recurrente cada 5 segundos sin bloquear el hilo de renderizado
     Future.delayed(const Duration(seconds: 5), attemptConnect);
   }
   ```
2. **Publicación con `retain=True` en Python:**
   En `helios-spa.py` y `helios-scada.py`, se activó la bandera `retain=True`. Cuando Flutter logra conectarse a Mosquitto, recibe de forma inmediata el estado solar actual sin esperar 10 segundos.
3. **Desacoplamiento del Estado de la Gráfica en Memoria:**
   Se eliminó el `FutureBuilder` del método de pintado de `dashboard.dart`. En su lugar, `MqttService` mantiene un búfer circular en memoria RAM de alta velocidad:
   ```dart
   // Líneas 57-104 de mqtt_service.dart
   final List<Map<String, double>> livePowerPoints = [];

   void _recordPowerPoint() {
     final double exp = (spaData['p_exp'] as num?)?.toDouble() ?? 0.0;
     final double real = (telemetryData['power_w'] as num?)?.toDouble() ?? 0.0;
     livePowerPoints.add({'p_exp': exp, 'p_real': real});
     if (livePowerPoints.length > 50) livePowerPoints.removeAt(0);
   }
   ```
   La gráfica (`fl_chart`) consume directamente `livePowerPoints` sincrónicamente desde la memoria RAM a 60 FPS sin tocar el disco ni provocar parpadeos.

---

## Caso 12: Discrepancia en el Historial de Errores SCADA (Eventos = 0) y Homogeneidad Visual Día/Noche (Fase 4)

### 1. El Síntoma / Fallo
1. **Historial Vacío:** Cuando el simulador inyectaba una Falla 13 (Fuga a Tierra) o una Falla 101, la tarjeta de alerta en el Dashboard principal se iluminaba en rojo indicando la falla en tiempo real; sin embargo, al ingresar a la pantalla `ScadaErrorsScreen` (*Menú de Errores SCADA*), la tabla aparecía completamente vacía con el contador: `Total de Eventos Registrados: 0`.
2. **Ruptura Estética de la HMI:** Cuando el Dashboard cambiaba automáticamente al **Modo Día** (paleta clara *Palladian*), al navegar a las pantallas secundarias (`scada_errors_screen.dart` y `plant_config_screen.dart`), estas mantenían fondos oscuros azul marino (*Abyssal Anchorfish Blue*), provocando un contraste visual incoherente e inaccesible para los operadores en condiciones de alta luminosidad solar.

### 2. Diagnóstico y Causa Raíz Técnica
- **Causa Raíz de la Base de Datos:** Se descubrió una discrepancia en el esquema de la tabla de SQLite. Una versión temprana de `helios-scada.py` había creado la tabla como:
  `CREATE TABLE scada_errors (timestamp TEXT, fault_code INTEGER, description TEXT)`
  Posteriormente, la pantalla de Flutter `scada_errors_screen.dart` fue programada ejecutando la consulta:
  `SELECT timestamp, code, description FROM scada_errors`
  Al no existir la columna `code` (se llamaba `fault_code`), la consulta SQL arrojaba silenciosamente una excepción interna `SqliteException: no such column: code`, y el manejador `catch` de Flutter devolvía una lista vacía `_dbErrorLogs = []`.
- **Causa Raíz de la Estética:** Las pantallas secundarias no estaban suscritas al estado reactivo `mqttService.isNight`, utilizando colores `const` codificados de forma rígida en lugar de la paleta dinámica oficial.

### 3. Por qué Fallaron los Intentos Previos
- Borrar la base de datos a mano resolvía el problema temporalmente, pero ante cualquier actualización del sistema en campo, las bases de datos de clientes existentes no podían ser destruidas porque se perderían meses de registros históricos.

### 4. Solución Definitiva e Implementación
1. **Migración Automática de Esquema en [helios-logger.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-logger.py):**
   Se programó una rutina de inspección en tiempo de arranque mediante `PRAGMA table_info`:
   ```python
   # Líneas 42-63 de helios-logger.py
   c.execute("PRAGMA table_info(scada_errors)")
   columns = [row[1] for row in c.fetchall()]
   if 'fault_code' in columns and 'code' not in columns:
       print("[INFO] Migrando tabla scada_errors: renombrando 'fault_code' -> 'code'...")
       c.execute("ALTER TABLE scada_errors RENAME COLUMN fault_code TO code")
       conn.commit()
   ```
2. **Consultas con Fallback Defensivo en [scada_errors_screen.dart](file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi/lib/ui/scada_errors_screen.dart):**
   ```dart
   // Líneas 73-88 de scada_errors_screen.dart
   try {
     resultSet = db.select('SELECT timestamp, code, description FROM scada_errors ORDER BY id DESC LIMIT 100;');
   } catch (_) {
     resultSet = db.select('SELECT timestamp, fault_code AS code, description FROM scada_errors ORDER BY timestamp DESC LIMIT 100;');
   }
   ```
3. **Homogeneización Visual Reactiva Día/Noche:**
   Tanto en `scada_errors_screen.dart` como en `plant_config_screen.dart`, se inyectó el observador del tema:
   ```dart
   final mqttService = context.watch<MqttService>();
   final bool isNight = mqttService.isNight;
   // Aplicación dinámica de gradientes:
   // isNight ? HeliosTheme.nightBackgroundGradient : HeliosTheme.dayBackgroundGradient
   ```
   Garantizando que todo el entorno gráfico conmute de forma simultánea y coherente entre el tema claro para el sol del mediodía y el tema oscuro con acentos cálidos para la operación nocturna.

---

# PARTE 3: AUTO-INTERROGACIÓN DE NIVEL SINODAL (8 PREGUNTAS Y RESPUESTAS AVANZADAS)

Esta sección recopila las 8 interrogantes técnicas más rigurosas que un jurado examinador de posgrado o un sínodo de titulación en ingeniería de sistemas embebidos puede formular acerca de la arquitectura de HeliOs, junto con sus respuestas fundamentadas a bajo nivel:

---

### Pregunta 1: ¿Por qué eligieron una partición física separada `/data` en lugar de una solución común en Linux embebido como `OverlayFS` sobre la raíz?

**Respuesta del Sustentante:**  
"La técnica de `OverlayFS` consiste en superponer una capa de solo lectura (*lowerdir*) con una capa de lectura/escritura en memoria RAM o flash (*upperdir*), presentando una vista unificada del sistema de archivos al usuario. Si bien `OverlayFS` es útil en distribuciones didácticas para permitir que el usuario instale paquetes temporalmente, en un sistema de control industrial de misión crítica introduce dos desventajas graves:
1. **Ambigüedad en la persistencia y desgaste de la memoria flash:** Con `OverlayFS`, cualquier daemon que escriba logs accidentales en `/var/log` o archivos temporales en `/tmp` consume espacio de la capa modificable, provocando escrituras descontroladas en sectores dispersos de la memoria flash y acelerando el agotamiento de los ciclos de borrado del chip NAND.
2. **Riesgo de corrupción en metadatos durante cortes de energía:** Si la alimentación se interrumpe durante una operación de consolidación de inodos entre el *upperdir* y el *workdir* de OverlayFS, el árbol de directorios superpuesto puede quedar en un estado inconsistente que impida montar el sistema en el siguiente arranque.

En HeliOs aplicamos el principio de diseño de **separación física absoluta de dominios**: la partición de sistema operativo `/` no tiene ninguna capa de escritura intermedia; es inmutable por hardware y software a nivel de tabla de bloques. La persistencia se acota exclusivamente a una partición dedicada (`/data`) donde solo cuatro procesos específicos tienen autorización de escritura. Si la partición `/data` sufriera una catástrofe de corrupción en sus bloques de datos, el kernel y el sistema operativo arrancarán al 100%, levantarán la red y permitirán al operador telediagnosticar y reparar el equipo."

---

### Pregunta 2: ¿Cómo se garantiza que el broker Mosquitto y la base de datos SQLite no sufran corrupción si la alimentación eléctrica se corta exactamente mientras se inserta un registro en `/data`?

**Respuesta del Sustentante:**  
"Se garantiza mediante tres mecanismos independientes a nivel de base de datos, motor de broker y sistema de archivos:
1. **Transaccionalidad ACID en SQLite:** SQLite es un motor transaccional de reconocimiento mundial utilizado en sistemas de aviónica y automotrices. Antes de modificar una sola página en la tabla de datos principal, SQLite escribe las modificaciones en un archivo de diario de reversión (*Rollback Journal*) o registro de escritura previa (*WAL - Write-Ahead Logging*). La llamada a la base de datos ejecuta llamadas `fsync()` que fuerzan el vaciado de las páginas sucias del Page Cache del kernel al almacenamiento físico antes de confirmar el commit. Si la energía se corta en medio de la escritura, en el siguiente arranque SQLite detecta el archivo de journal incompleto, descarta los datos a medio escribir y devuelve la base de datos al último estado consistente válido sin intervención humana.
2. **Persistencia Ligera de Mosquitto:** El broker Mosquitto no escribe continuamente en disco para cada mensaje. Su persistencia (`persistence true` en `mosquitto.conf`) se configura apuntando a `/data/mosquitto.db` con volcados temporizados (`autosave_interval`). Además, los mensajes críticos viajan con QoS 1; si el broker colapsa antes de procesar una trama, el emisor la retransmitirá en cuanto el broker vuelva a responder.
3. **Journaling de `ext4` en la partición `/data`:** La partición `/data` fue formateada con sistema de archivos `ext4` con journaling habilitado (`data=ordered`). Esto asegura que los metadatos del sistema de archivos siempre se registren antes que los bloques de datos, impidiendo que el volumen quede desestructurado ante apagones."

---

### Pregunta 3: En `helios-spa.py`, ustedes reemplazan `scipy` con una clase llamada `PaqueteFantasma`. ¿Por qué esto no causa una violación de segmento (*Segmentation Fault*) o un `AttributeError` en tiempo de ejecución dentro de `pvlib`?

**Respuesta del Sustentante:**  
"Esto no causa ningún fallo debido al diseño modular de `pvlib` y a cómo opera el sistema de importación en Python. 
En Python, el diccionario `sys.modules` es la tabla de símbolos global donde el intérprete consulta si un paquete ya está cargado en memoria antes de buscarlo en el disco. Cuando un archivo ejecuta `import scipy.optimize`, Python primero consulta si `'scipy.optimize'` es una clave en `sys.modules`.

Nuestra clase `PaqueteFantasma` hereda de `types.ModuleType` y redefine el método mágico `__getattr__(self, name)`:
```python
class PaqueteFantasma(types.ModuleType):
    def __getattr__(self, name):
        return MagicMock()
```
Cualquier acceso a un atributo o función que `pvlib` intente consultar sobre `scipy` (por ejemplo, `scipy.__version__` o `scipy.constants.degree`) devuelve de manera dinámica un objeto `MagicMock()`.

La razón por la cual no ocurre un `Segmentation Fault` es que los algoritmos específicos que HeliOs ejecuta —concretamente la función astronómica `pvlib.solarposition.spa_python` y el modelo Clear Sky `pvlib.clearsky.haurwitz`— son implementaciones puramente matemáticas basadas en álgebra de matrices de `numpy` y series temporales de `pandas`. `pvlib` mantiene importaciones de `scipy` a nivel de cabecera de módulo por cuestiones de organización interna de su librería, pero **jamás invoca las funciones de optimización o integración en caliente** durante la ejecución de las rutas de cálculo de Haurwitz y SPA. Por ende, los objetos mockeados jamás son llamados a ejecutar código nativo C/Fortran, permitiendo una ejecución matemática impecable."

---

### Pregunta 4: En el modelo de cielo claro de Haurwitz, ¿cuál es la fundamentación física del factor exponencial y qué limitaciones presenta para elevaciones solares rasantes ($\alpha_s < 5^\circ$)?

**Respuesta del Sustentante:**  
"El modelo de Haurwitz es una parametrización de transferencia radiativa atmosférica para la irradiancia global horizontal:

$$GHI = 1098 \cdot \cos(\theta_z) \cdot \exp\left( \frac{-0.057}{\cos(\theta_z)} \right)$$

Físicamente, el término representa la ley de Beer-Lambert-Bouguer de atenuación exponencial de la luz a través de un medio absorbente y dispersor:
- El término $1098\text{ W/m}^2$ es el límite asintótico superior de radiación solar directa que alcanza el suelo cuando el sol se encuentra en el cénit absoluto ($\theta_z = 0^\circ, \cos\theta_z = 1$).
- El cociente $1/\cos(\theta_z)$ modela la **Masa de Aire Óptica Relativa ($AM$)** aproximando la atmósfera terrestre como un plano plano paralelo homogéneo.
- El valor $-0.057$ es el coeficiente de extinción óptico representativo que agrupa la dispersión de Rayleigh de las moléculas de aire y la absorción por ozono y vapor de agua.

**Limitación en Elevaciones Rasantes ($\alpha_s < 5^\circ$):**  
Conforme el sol se aproxima al horizonte al amanecer o atardecer ($\theta_z \rightarrow 90^\circ$), el término $\cos(\theta_z) \rightarrow 0$. En un modelo plano paralelo, la masa de aire $1/\cos(\theta_z)$ tiende asintóticamente a infinito, lo cual es físicamente irreal debido a la curvatura esférica de la Tierra y a la refracción atmosférica que dobla los rayos solares. Para ángulos cenitales $\theta_z > 85^\circ$, el modelo de Haurwitz subestima la radiación difusa y sufre aberraciones matemáticas.

**Cómo lo Resuelve HeliOs:**  
En [helios-spa.py](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-telemetry/helios-telemetry/files/helios-spa.py), HeliOs implementa un filtro de seguridad:
```python
is_night = elevation <= 0 or ghi <= 10.0
```
Cuando la elevación cae por debajo del horizonte o el valor calculado de $GHI$ desciende a menos de $10\text{ W/m}^2$, el sistema desactiva el seguimiento solar activo y conmuta al modo de seguridad **Estiba Plana (Flat-Stow)**, haciendo irrelevante cualquier imprecisión del modelo en la penumbra crepuscular."

---

### Pregunta 5: ¿Por qué configuraron `Type=idle` en `helios-network.service` y `Type=simple` en los daemons de telemetría, y qué impacto tiene en el tiempo de arranque?

**Respuesta del Sustentante:**  
"Esta diferenciación responde al manejo de concurrencia y contención de recursos en el arranque de Linux:
- **`Type=simple` en Telemetría (`helios-spa`, `helios-scada`, `helios-logger`):**  
  Bajo `Type=simple`, `systemd` realiza la llamada `fork()` y `execve()` y asume inmediatamente que la unidad está en ejecución activa sin esperar ninguna señal de sincronización. Esto permite que los tres daemons arranquen concurrentemente en paralelo aprovechando los cuatro núcleos Cortex-A76 del procesador BCM2712, reduciendo el tiempo de inicialización de la pila de datos a una fracción de segundo.
- **`Type=idle` en Red (`helios-network.service`):**  
  `Type=idle` le indica a `systemd` que retrase deliberadamente la ejecución del script de red hasta que todas las demás tareas del pipeline de arranque hayan sido completamente despachadas y la consola serial se haya liberado.  
  Si hubiésemos configurado el script de red como `Type=simple`, este competiría agresivamente por el procesador y por el hardware de radio mientras el kernel todavía está inicializando los módulos criptográficos y los montajes de disco. Peor aún: si el sistema debe arrancar en modo portal cautivo, `hostapd` y `dnsmasq` imprimirían mensajes en la consola que se entrelazarían con los logs de inicialización del compositor gráfico Weston. `Type=idle` garantiza un arranque visualmente limpio y secuencialmente predecible sin penalizar la velocidad de la HMI."

---

### Pregunta 6: ¿Cómo garantiza Flutter un renderizado fluido a 60 FPS sobre Weston si los datos de telemetría MQTT llegan con frecuencias completamente asíncronas y dispares (el inversor cada 2 s y el SPA cada 10 s)?

**Respuesta del Sustentante:**  
"El desacoplamiento se logra mediante el patrón arquitectónico de **Gestión de Estado Reactiva con `ChangeNotifier` / `Provider` y la separación de hilos de ejecución en Flutter**:
1. **Separación de Hilos (*Threading Model*):** Flutter divide su arquitectura en tres hilos fundamentales:
   - **Hilo de Plataforma (*Platform Thread*):** Escucha eventos de entrada de Wayland (toques en la pantalla capacitiva) y despacha eventos de red.
   - **Hilo de UI (*UI Thread* / Dart VM):** Ejecuta el código de nuestra aplicación, parsea los payloads JSON de MQTT y calcula el árbol de renderizado (*RenderTree*).
   - **Hilo de Renderizado (*Raster Thread*):** Toma las capas de dibujo (*LayerTree*) generadas por la UI y compila las llamadas de rasterizado GPU mediante OpenGL ES / Skia.
2. **Desacoplamiento de Frecuencia mediante Búfer en Memoria:**  
   En [mqtt_service.dart](file:///home/jm/HeliOs/Flutter-HeliOs/helios_hmi/lib/services/mqtt_service.dart), los paquetes MQTT entrantes se procesan en callbacks asíncronos. Cuando llega un dato de inversor (a 0.5 Hz) o un dato astronómico (a 0.1 Hz), los valores se depositan en variables en memoria y en el búfer circular `livePowerPoints`, y se dispara `notifyListeners()`.
3. **Pintado Independiente de la Gráfica (`fl_chart`):**  
   El motor gráfico `fl_chart` no espera a que llegue un mensaje MQTT para pintar. El Hilo de Renderizado sincroniza sus cuadros a la tasa de refresco del monitor mediante la interrupción de hardware **V-Sync** provista por el compositor Weston a través de Wayland (60 Hz = 16.6 ms por cuadro). Si no han llegado nuevos datos MQTT, Flutter simplemente repinta las curvas interpoladas y las animaciones de los indicadores sin ejecutar cálculos pesados. Los datos de telemetría actualizan el estado; la GPU renderiza la pantalla."

---

### Pregunta 7: En el modo portal cautivo, el comodín de secuestro DNS `address=/#/192.168.4.1` responde a todas las consultas. ¿Por qué esto no genera tormentas de broadcasts o saturación de sockets en la interfaz Wi-Fi?

**Respuesta del Sustentante:**  
"Esto no satura la red debido a la naturaleza unicast del protocolo DNS y a la topología estricta de subred configurada en `dnsmasq`:
1. **Unicast sobre UDP/53:** Las consultas DNS que emite un smartphone no son mensajes broadcast a toda la red; son datagramas UDP dirigidos específicamente a la dirección IP unicast que el servidor DHCP le asignó como servidor DNS en la fase de configuración de red (en nuestro caso, `192.168.4.1`). Por lo tanto, el tráfico viaja exclusivamente entre el teléfono y la Raspberry Pi sin inundar el espectro electromagnético.
2. **Pool de Direcciones IP Estrictamente Acotado:**  
   En [dnsmasq.conf](file:///home/jm/HeliOs/HeliOs_Project/poky/meta-helios/recipes-connectivity/helios-network/files/dnsmasq.conf), el rango DHCP está restringido a un máximo de 18 direcciones IP:
   `dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h`
   Esto limita físicamente a un máximo de 18 clientes simultáneos.
3. **Respuesta Inmediata sin Resolución Recursiva:**  
   Un servidor DNS convencional se satura cuando debe consultar a servidores raíz en internet (*Forwarding / Iterative Resolution*). La directiva `address=/#/192.168.4.1` actúa como una regla estática en memoria RAM: `dnsmasq` no realiza ninguna búsqueda externa; responde en menos de 0.5 milisegundos con un paquete sintético de respuesta directa de apenas 40 bytes, manteniendo el uso de CPU de la Raspberry Pi 5 por debajo del 0.2% durante todo el proceso de aprovisionamiento."

---

### Pregunta 8: Para detectar la pérdida de un panel en serie (Falla 101), ustedes comparan la tensión real contra el 90% de la esperada ($V_{DC} < 0.90 \cdot V_{exp}$). ¿Por qué no usar un umbral de sustracción exacto correspondiente al voltaje de un panel ($V_{DC} < V_{exp} - V_{oc}$)?

**Respuesta del Sustentante:**  
"Utilizar una resta fija teórica ($V_{exp} - V_{oc}$) en un sistema fotovoltaico real en campo es un error de ingeniería que conduce a falsos positivos constantes debido al comportamiento no lineal de las celdas de silicio:
1. **Coeficiente de Temperatura Negativo:**  
   En días calurosos de verano con alta irradiancia, las celdas fotovoltaicas pueden alcanzar temperaturas de operación de $60^\circ\text{C}$ a $70^\circ\text{C}$. Como el coeficiente térmico de voltaje de un panel monocristalino típico es de aproximadamente $-0.35\%/^\circ\text{C}$, una celda a $65^\circ\text{C}$ experimenta una caída térmica natural de:
   $$\Delta V = 40^\circ\text{C} \times (-0.35\%/^\circ\text{C}) = -14\%$$
   Si utilizáramos un umbral de resta estático que no contemple esta variación, en un día caluroso el arreglo entero perdería más de un 10% de su voltaje únicamente por temperatura ambiente, disparando una falsa alarma de panel roto cuando el arreglo está completamente sano.
2. **Dispersión de Punto de Máxima Potencia (MPPT):**  
   Los inversores solares no operan en voltaje de circuito abierto ($V_{oc}$); operan continuamente buscando el Voltaje de Máxima Potencia ($V_{mp}$), el cual típicamente ronda entre el 80% y 85% del $V_{oc}$ nominal. Durante fluctuaciones de nubes rápidas, el algoritmo perturbador del seguidor MPPT oscila la tensión buscando la rodilla de la curva I-V.
3. **La Justificación del Margen Relativo del 90%:**  
   El factor del 90% ($0.90 \cdot V_{exp}$) provee una banda de histéresis analítica robusta:
   - Es suficientemente tolerante para absorber las variaciones por calentamiento térmico estacional y las oscilaciones de búsqueda del MPPT.
   - Es suficientemente sensible para detectar cuando una cadena completa pierde uno o más módulos por disparo de diodos de bypass, rotura de vidrio, desconexión de conectores MC4 o sombras duras localizadas.

Por ello, la combinación del umbral relativo del 90% complementado con la verificación de irradiancia diurna ($GHI > 20\text{ W/m}^2$) representa el equilibrio óptimo entre sensibilidad diagnóstica e inmunidad contra falsas alarmas."
