# Fase 2 — Hallazgos de placa y el problema de latencia de VRAM (2026-11-20)

> Documento histórico del port. El estado actual está en [arquitectura.md](arquitectura.md).

## Pines Tang Nano 9K (GW1NR-LV9QN88PC6/I5) confirmados

Fuentes: sipeed/TangNano-9K-example (led, hdmi, uart, picotiny, lcd_led, spi_lcd),
hi631/tang-nano-9K (NES_TN9.cst), lfantoniosi/tn_vdp (v9958.cst).

| Función | Pin(es) | IO_TYPE |
|---|---|---|
| Reloj 27 MHz | 52 | LVCMOS33 |
| S1 (Reset_Button) / S2 (User_Button), activos a 0 | 4 / 3 | LVCMOS18 (banco 1,8 V) |
| LED[0..5] (activos a 0) | 10, 11, 13, 14, 15, 16 | LVCMOS18 |
| HDMI clk / d0 / d1 / d2 (P,N) | 69,68 / 71,70 / 73,72 / 75,74 | LVCMOS33D (+ ELVDS_OBUF) |
| microSD SCK / CMD(MOSI) / CS(DAT3) / DAT0(MISO) | 36 / 37 / 38 / 39 | LVCMOS33 |
| Flash SPI CS / CLK / MOSI / MISO | 60 / 59 / 61 / 62 | LVCMOS33 |
| UART TX / RX (USB-UART) | 17 / 18 | LVCMOS33 |
| PS/2 clk / dat (5 V con adaptador de niveles) | 51 / 53 | LVCMOS33, pull-up |
| Audio PWM L / R (mono en ambos, como en pengo_arcade) | 77 / 76 | LVCMOS33 |
| Joystick arriba / abajo / izq. / der. / fuego (como en pengo_arcade) | 30 / 33 / 34 / 40 / 29 | LVCMOS33, pull-up |
| Botón 2 (disparo B) / botón 3 (tecla ESPACIO) | 35 / 42 | LVCMOS33, pull-up |
| Otros 1,8 V | 83-86 | LVCMOS18 |

PSRAM integrada: puertos del top con nombres fijos, **sin** entradas en el .cst:
`O_psram_ck[1:0]`, `O_psram_ck_n[1:0]`, `IO_psram_rwds[1:0]`, `IO_psram_dq[15:0]`,
`O_psram_reset_n[1:0]`, `O_psram_cs_n[1:0]` (2 canales de 4 MB, 8 bits cada uno).

## El problema: el VDP exige el dato de VRAM en ~93 ns

En `vdp.vhd` (árbitro de VRAM) la dirección se registra al final de `dotState="10"` y **todos**
los consumidores (text12, graphic123M, graphic4567, sprite, lectura CPU, comandos VDP) capturan
`pRamDat` al final de `dotState="01"`: 2 ciclos de 21,48 MHz = **93 ns** desde la dirección.
El controlador SDRAM original entregaba el dato a los ~58 ns.

La PSRAM (W955D8MBYA, latencia fija 2×) necesita ~140-150 ns por acceso a 86-107 MHz, incluso con
un die dedicado a la VRAM. Con latencia variable bajaría a ~100 ns, pero un choque con el refresco
interno la duplica → píxeles corruptos. A 166 MHz (máximo del chip) serían ~114 ns, aún > 93 ns.

Referencias revisadas:
- lfantoniosi/tn_vdp (V9958 en Tang Nano 9K, BSD-3): **no** usa PSRAM; VRAM de 32 KB en BSRAM,
  VDP a 27 MHz, HDMI 720x480p con pixel clock 27 MHz.
- hi631/tang-nano-9K (NES): PSRAM con el IP HS de Gowin a ~160-173 MHz; el NES tolera latencia alta.

BSRAM no alcanza: 26 bloques × 2 KB = 52 KB en total (14 ya usados); el BIOS MSX2 exige ≥ 64 KB de VRAM.

## Opciones

1. **Retemporizar el VDP**: que las lecturas de VRAM tengan un "dot" (4 ciclos) más de latencia
   → 6 ciclos ≈ 280 ns de margen. Hay que desplazar una posición de `eightDotState` las capturas de
   text12 / graphic123M / graphic4567 / sprite y ajustar las lecturas de CPU/comando y el offset
   horizontal. Verificable en simulación comparando la imagen contra el VDP original con VRAM ideal.
   Necesita GHDL.
2. **Plan B MSX1** (TMS9918, 16 KB VRAM en BSRAM; PSRAM solo para la CPU).
3. **Tang Nano 20K** (SDRAM integrada; el controlador original casi sirve tal cual).
