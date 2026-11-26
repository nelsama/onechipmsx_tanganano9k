# One Chip MSX en Tang Nano 9K

Port del **One Chip MSX (ESE-MSX)** a la placa **Sipeed Tang Nano 9K**
(Gowin GW1NR-LV9QN88PC6/I5), con salida HDMI y usando como memoria la PSRAM
integrada en la FPGA. No necesita memoria externa adicional.

Funciona en la placa: logo animado, MSX-DOS 2 desde microSD, menú SofaRun y
juegos, incluidos cartuchos con SCC.

> **El repositorio no incluye BIOS, ROMs ni juegos.** Tienes que aportar los
> tuyos; más abajo se explica cómo generar la imagen de BIOS.

## Características

| Bloque | Estado |
|---|---|
| CPU | Z80 (T80) a 3,6 MHz, sin turbo |
| Vídeo | VDP V9938, 128 KB de VRAM, HDMI 720x480p a 60 Hz con audio (solo NTSC) |
| RAM | Mapper de 1 MB |
| Cartucho | MegaRAM ESE-SCC de 512 KB en el slot 2; también MegaRAM brasileña (puerto 8Eh) |
| Sonido | PSG, SCC y MSX-MUSIC (YM2413); mono por HDMI y PWM |
| Almacenamiento | microSD en modo SPI, controlador MegaSD con MSX-DOS 2 |
| Entrada | Joystick, teclado por UART (USB), teclado PS/2 |
| Otros | Reloj RP5C01 sin batería, botones de reset |

La BIOS usada en las pruebas es MSX2+, pero el VDP **no** implementa los modos
YJK (screens 10 a 12) ni el scroll horizontal R25-R27 del V9958: el hardware
equivale a un MSX2.

Uso de la FPGA (release): 8480 / 8640 lógica (98 %), 3925 / 6771 registros,
26 / 26 BSRAM, 4318 / 4320 CLS. No queda espacio para ampliaciones.

### Limitaciones conocidas

- El teclado PS/2 no se ha probado con un teclado real. El cursor arriba del
  teclado por UART tampoco está verificado.
- La carga de la BIOS desde la SD está en el cargador, pero sin probar. Se ha
  usado siempre la flash externa.
- Sin ROM de kanji, sin PAL, sin segundo joystick.
- MegaRAM de 512 KB: los juegos SCC de 2 MB no caben.
- El reloj a 21,6 MHz va un 0,57 % más rápido que el original.

## Qué necesitas

- Tang Nano 9K y un monitor HDMI.
- microSD de hasta 2 GB, formateada en FAT16.
- Gowin EDA (probado con 1.9.12.03) para compilar y grabar.
- Python 3 para las herramientas, y Git Bash si usas `tools/synth.sh`.
- ROMs de BIOS MSX2+ **japonesa (60 Hz)** y un controlador MegaSD.

## Puesta en marcha

### 1. Generar la imagen de BIOS

La imagen ocupa 256 KB. Con las ROMs de un firmware OCM-PLD de KdL
(3.9.2, variante `single_epbios_msx2plus_*`):

```sh
python tools/extract_epbios.py emsx_top.pld build/roms
python tools/make_bios.py -o build/bios/OCM-BIOS.DAT --disk build/roms/disk.rom --main build/roms/main.rom --sub build/roms/sub.rom --fm build/roms/fm.rom --kbasic fs-a1wsx_kanjibasic.rom
```

La combinación probada usa el Kanji BASIC del Panasonic FS-A1WSX; el que extrae
el pack OCM (`kanjibasic.rom`) es distinto. `--kbasic` hace falta para el logo animado. Sin `--disk` la máquina arranca en
BASIC sin acceso a disco.

| Offset | Tamaño | Contenido |
|---|---|---|
| 0x00000 | 64 KB | Controlador MegaSD y MSX-DOS 2 |
| 0x10000 | 32 KB | BIOS principal |
| 0x18000 | 16 KB | SUB-ROM |
| 0x1C000 | 16 KB | FM-BIOS |
| 0x20000 | 32 KB | Kanji BASIC |

### 2. Compilar el bitstream

Con el IDE: abre `ONECHIP_MSX.gprj` y ejecuta *Run All*. Desde Git Bash:

```sh
TOP=tn9k_top PNR=1 PLACE_OPT=1 bash tools/synth.sh tn9k_rel 9k
# resultado: build/tn9k_rel/impl/pnr/ONECHIP_MSX.fs
```

La ruta de Gowin se cambia con la variable `GW_SH`. El bitstream probado en la
placa se generó con `synth.sh`.

### 3. Grabar

Son **dos memorias distintas** y hacen falta las dos. Con Gowin Programmer:

| Qué | Dónde | Operación |
|---|---|---|
| Imagen de BIOS | Flash SPI externa | External Flash Mode, *exFlash C Bin Erase, Program*, dirección 0x000000 |
| `ONECHIP_MSX.fs` | Flash interna de la FPGA | Embedded Flash Mode, *embFlash Erase, Program* |

El selector de archivos de *C Bin* puede pedir extensión `.bin`: copia
`OCM-BIOS.DAT` como `ocm_bios.bin`.

Para probar sin grabar, carga el `.fs` en SRAM; se pierde al apagar.

### 4. Preparar la microSD

Formato FAT16 (no FAT32), 2 GB como máximo. En la raíz van al menos `MSXDOS2.SYS` y
`COMMAND2.COM`. Para arrancar directamente en SofaRun, instalado en `\SR`:

```bat
path %1\dos;%1\util
set help %1\help
set temp %1\tmp
del \settings\srom.flh
cd sr
sr
```

Guárdalo como `AUTOEXEC.BAT` con finales de línea CRLF. La línea `del` borra el
registro con el que SofaRun podría dar por cargado en la MegaRAM un juego que
ya se perdió al apagar.

En SofaRun, los juegos SCC se pueden lanzar con *Memory mapper* o *ESE SCC*.

## Conexiones

Los pines de esta tabla son de 3,3 V, salvo el reset del pin 86, que es de
1,8 V. **No apliques 5 V a ninguno.**

| Función | Pin |
|---|---|
| Joystick arriba / abajo / izquierda / derecha | 30 / 33 / 34 / 40 |
| Joystick disparo A / disparo B | 29 / 35 |
| Botón extra: tecla ESPACIO | 42 |
| Reset externo (contacto a GND) | 86 |
| Audio izquierdo / derecho (mono en ambos) | 77 / 76 |
| PS/2 reloj / datos (con adaptador de niveles) | 51 / 53 |
| UART TX / RX (USB de la placa) | 17 / 18 |
| UART TX adicional de depuración | 32 |

Joystick y botones son activos a 0: cada contacto va entre el pin y GND, con
pull-up interno. La salida de audio es PWM de un bit y necesita un filtro
paso bajo RC. HDMI, microSD y flash usan los conectores de la placa; el
listado completo está en [src/board/tn9k.cst](src/board/tn9k.cst).

El botón **S1** de la placa es reset. **S2** solo se usa en compilaciones de
depuración.

### Teclado por UART

Abre el puerto serie USB de la placa (115200 8N1, sin control de flujo) con
PuTTY o similar. Cada carácter pulsa la tecla equivalente del MSX. Enter,
retroceso, TAB, ESC y cursores funcionan como tales; Ctrl+C es CTRL+STOP.
Está pensado para teclear a mano: el texto pegado pierde caracteres.

### LEDs

| LED | Encendido significa |
|---|---|
| 0 | La flash externa respondió |
| 1 | **Error:** la PSRAM no llegó a tiempo para el VDP |
| 2 | **Error:** PSRAM no inicializada |
| 3 | El cargador escribió la BIOS en RAM |
| 4 | La CPU leyó la BIOS principal |
| 5 | Parpadeo: el sistema tiene reloj |

Arranque normal: 0, 3 y 4 encendidos, 1 y 2 apagados, 5 parpadeando.

## Si algo falla

| Síntoma | Qué revisar |
|---|---|
| Pantalla negra, LED 0 apagado | La flash externa no responde |
| Pantalla negra, LED 3 o 4 apagado | La BIOS no está en 0x000000 o la imagen es incorrecta |
| Arranca en BASIC en vez de DOS | SD ausente, no FAT16, o faltan `MSXDOS2.SYS` / `COMMAND2.COM` |
| Todo se pierde al apagar | El `.fs` se cargó en SRAM, no en la flash interna |
| Imagen inestable | Programa o BIOS en modo PAL (50 Hz), no soportado |

## Más documentación

- [docs/arquitectura.md](docs/arquitectura.md): relojes, memoria, slots, VDP y PSRAM.
- [docs/desarrollo.md](docs/desarrollo.md): compilación, simulación y depuración.
- Diario del port: [fase 0](docs/fase0-recursos.md), [fase 1](docs/fase1-nucleo.md), [fase 2](docs/fase2-hallazgos.md).

## Créditos y licencias

Los archivos conservan la licencia de su autor; no hay una licencia única.

- **ESE-MSX / One Chip MSX**: Kazuhiro Tsujikawa (ESE Artists' factory).
- **VDP**: Kunihiko Ohnaka.
- **VM2413 (OPLL) y filtros**: Mitsutaka Okazaki.
- **T80**: Daniel Wallner.
- **Controlador PSRAM**: basado en
  [psram-tang-nano-9k](https://github.com/zf3/psram-tang-nano-9k) de Feng Zhou
  ([Apache 2.0](LICENSE-APACHE-2.0.txt)).
- **Codificador TMDS**: Furkan Cayci.
- **Port a Tang Nano 9K**: Nelson Figueroa.

Las fuentes de partida son las del port a Xilinx descrito en
[readme.txt](readme.txt).

**La licencia del núcleo ESE-MSX no permite vender este código ni usarlo en un
producto o actividad comercial sin permiso previo por escrito.**
