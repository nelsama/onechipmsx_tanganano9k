# Arquitectura

    tn9k_top ─┬─ PLLs, reset, LEDs
              ├─ emsx_core   MSX completo (Z80, VDP, PSG, SCC, OPLL, MegaSD, RTC)
              ├─ psram_msx   dos canales PSRAM, uno por die
              ├─ vdp2hdmi    VGA 31 kHz -> raster 720x480p
              ├─ hdmi_*      HDMI con audio (hdmi_tx) y serialización (hdmi_phy)
              └─ uart_kbd    teclado MSX por UART

## Relojes

| Reloj | Frecuencia | Uso |
|---|---|---|
| clk27 | 27 MHz | Cristal de la placa (pin 52) |
| memclk | 86,4 MHz | Controlador PSRAM |
| memclk_p | 86,4 MHz, 90° | CK de la PSRAM |
| clk21m | 21,6 MHz (memclk / 4) | Todo el MSX |
| cpuclk | 3,6 MHz (clk21m / 6) | Z80 |
| TMDS | 135 MHz | Serializadores HDMI |
| píxel | 27 MHz | Raster HDMI |

memclk, memclk_p y clk21m salen del mismo VCO y son síncronos. Una línea del
VDP dura 1368 clk21m, es decir, 228 ciclos del Z80.

## Memoria

La PSRAM integrada son dos dies independientes de 4 MB:

- **Die 0:** VRAM del VDP, un acceso por dot (4 clk21m).
- **Die 1:** memoria de la CPU, con petición y acuse.

Direcciones del die 1, formadas por `CpuAdr(22) & CpuAdr(20 downto 0)`:

| Rango | Contenido |
|---|---|
| 0x000000-0x0FFFFF | Mapper (1 MB) |
| 0x200000-0x27FFFF | MegaRAM (512 KB) |
| 0x280000-0x2BFFFF | ESE-RAM e imagen de BIOS (256 KB) |

El mapper se borra en cada reset (unos 0,1 s): si no, MSX-DOS 2 no vuelve a
arrancar sobre la RAM de la sesión anterior. La MegaRAM solo se borra al
encender, para que un cartucho cargado sobreviva al reset.

### Slots

| Slot | Contenido |
|---|---|
| 0-0 | BIOS principal |
| 0-2 | FM-BIOS |
| 1 | Vacío |
| 2 | MegaRAM / ESE-SCC (y MegaRAM brasileña por el puerto 8Eh) |
| 3-0 | Mapper |
| 3-1 | SUB-ROM (página 0) y Kanji BASIC (páginas 1-2) |
| 3-2 | MegaSD |
| 3-3 | IPL-ROM |

## Arranque

1. Con el MSX en reset, el top saca la flash SPI del modo de bajo consumo
   (comando 0xAB) y espera a que la PSRAM esté lista.
2. La IPL-ROM busca la imagen de BIOS en la SD (FAT16; el primer sector de
   datos debe empezar por "AB") y, si no está, la lee de la flash externa desde
   0x000000.
3. La copia a la ESE-RAM y salta a la BIOS principal.

La IPL-ROM original leía la flash desde 0x040000; está parcheada.

## MegaRAM brasileña

El slot 2 es una ESE-SCC (SCC+). Los discos para la MegaRAM brasileña (ACVS)
la controlan por el puerto de E/S 8Eh: `IN` habilita escribir la RAM, `OUT` vuelve
al modo ROM, donde escribir en 4000h, 6000h, 8000h o A000h elige el banco de 8 KB
de esa ventana. El primer acceso a 8Eh pone el slot en ese modo hasta el reset.
El SCC sigue en 9800h con el banco 3Fh en 8000h, como en un cartucho Konami.
SofaRun usa el puerto 8Eh para detectar dispositivos aunque luego cargue en la
ESE-SCC: escribir en 7FFEh o BFFEh (modo del SCC+) en modo de bancos devuelve el
slot a ESE-SCC. `sim/mk_acvs_test.py` lo prueba en la simulación del sistema.

## VDP y latencia de VRAM

El VDP original exige el dato de VRAM unos 93 ns después de la dirección, y la
PSRAM no llega. El VDP está retemporizado para capturar un dot más tarde: 6
clk21m, unos 280 ns. El análisis está en
[fase2-hallazgos.md](fase2-hallazgos.md).

## Z80 y PSRAM: por qué no hay esperas

Una versión intermedia insertaba un ciclo de espera en los accesos a PSRAM. No
hacía falta y rompía software: el bucle con el que Space Manbow espera el bit
HR de S#2 pasaba de 37 a 38 T. Como 228 / 38 = 6 exacto, el bucle quedaba
sincronizado con la línea y casi nunca veía el pulso, de 33 T. Se colgaba al
empezar la partida.

**No añadas esperas al Z80 sin repasar este caso.** Sin ellas el margen mínimo
medido en simulación es de unos 249 ns (primeros 9 ms de arranque), y los
juegos probados funcionan en la placa. `sim/mk_hr_test.py` reproduce el bucle.

## HDMI

Una línea VGA del VDP (684 clk21m) dura exactamente 855 píxeles de 27 MHz, así
que el raster HDMI (855 x 524 totales, 60,27 Hz) queda enganchado al VDP con un
búfer de dos líneas, sin memoria de cuadro. PAL y entrelazado no se tratan.

`hdmi_tx` añade los InfoFrames (VIC 2, 4:3) y el audio PCM de 48 kHz; la guía general es
[09-HDMI-COMPLETO.md](09-HDMI-COMPLETO.md). Lo propio de este proyecto:

- El barrido es de 855 x 524 en vez de 858 x 525 (genéricos `H_TOT` y `V_TOT`).
  No es el 480p exacto de la norma: la CPU y el VDP no se pueden detener sin
  alterar sus tiempos.
- Los contadores salen de `vdp2hdmi` 2 ciclos antes que la imagen.
- La muestra de audio es la media de la mezcla durante cada periodo de 48 kHz
  (450 clk21m), tomada antes del PWM. El PWM sigue saliendo por los pines 77 y 76.
- Al audio HDMI se le quita la continua (30 Hz) y se le aplica x4 (+12 dB) con
  saturación; el PWM no cambia.
- `HDMI_FULL = false` en `tn9k_top` vuelve a DVI (solo imagen).
- Para que quepa: tabla de paquetes y seno del OPLL en BSRAM, codificador TMDS
  reducido, y memorias de fase, realimentación y salida del OPLL sin borrado en el reset.

## Diferencias con el núcleo original

- Sin bus de slots externo, turbo, OSD, salida TV/RGB, USB ni casete.
- Los interruptores DIP son genéricos de `emsx_core` (`CFG_*`).
- `ENABLE_OPLL`, `ENABLE_SCC`, `ENABLE_RTC` y `ENABLE_KANJI` activan bloques
  (todos salvo KANJI por defecto).
- La SDRAM se sustituye por la PSRAM.
- Bugs del original corregidos: ver [fase1-nucleo.md](fase1-nucleo.md).
