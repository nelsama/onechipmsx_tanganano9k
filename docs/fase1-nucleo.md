# Fase 1 — Núcleo `emsx_core` sin bus externo (2026-11-20)

> Documento histórico del port. El estado actual está en [arquitectura.md](arquitectura.md).

## Qué cambió

- `src/emsx_top.vhd` → `src/emsx_core.vhd` (entidad `emsx_core`): sin pines de slot, sin PLL.
  - Bus del Z80 interno (`Bus*`): `t80a` tiene ahora `DI`/`DO`/`DOE` en vez de `D` inout. El dato de
    lectura se resuelve con un mux (`BusDat`); lectura de slot 1/2 vacío = FFh.
  - Z80 a 3,58 MHz con `cpuclk` interno. Turbo eliminado (`clksel` constante "00").
  - Reset: puerto `reset_n` (lo genera el top de placa: power-on + botón).
  - DIP switches → generics `CFG_MEGTYPE`, `CFG_MMC`, `CFG_KMAP_US`.
  - Bloques opcionales por generic: `ENABLE_OPLL`, `ENABLE_SCC`, `ENABLE_RTC`, `ENABLE_KANJI`.
  - SD en modo SPI (`pSd_Ck/Cm/Cs/Do`), flash del BIOS por la antigua interfaz EPCS (`pEpc_*`).
  - Vídeo fijo VGA 31 kHz 6+6+6 bits; audio = 1 pin PWM (`pAudio`).
  - El controlador SDRAM sigue igual (puertos `pMem*`): se sustituye en la Fase 3.
- Eliminados: `ntsc`, `pal`, `vencode`, `osd` (+`font0406`, `osdnametable`), ventana de depuración y
  `registerRam` del VDP, texto de prueba del OSD, selector TV/RGB/VGA, CMT, escáner DIP/LED, USB,
  `pll4x` de Altera y el stub de Xilinx.
- `psg`: joysticks solo entrada; las salidas open-collector de los pines 6/7 se modelan al leer.

## Bugs del original corregidos

- `CFG_MEGTYPE`: el comentario de `emsx_top` decía `"0-"`=SCC+, pero `megaram` usa bit0=0 → SCC.
  Por defecto ahora `"10"` (SCC+).
- `text12`: el generador de parpadeo de TEXT2 estaba fuera del flanco de reloj (latches + lazo
  combinacional) y `blinkPeriodCount` nunca se incrementaba.
- `eseps2`: `Fkeys` y `Scro` generaban latches.
- Resultado: **0 latches** en el netlist.

## Recursos (GW1NR-9, `tools/synth.sh`)

| Configuración | Lógica / 8640 |
|---|---:|
| Fase 0 (original) | 8880 (103 %) |
| Fase 1 completo (OPLL+SCC+RTC+Kanji) | 8211 (95 %) |
| sin Kanji | ~8060 |
| sin RTC | ~7840 |
| sin SCC | ~7730 |
| sin RTC ni Kanji | ~7810 (90 %) |
| sin RTC, Kanji ni SCC | ~7270 (84 %) |
| sin OPLL | ~6230 (72 %) |

(Las filas con ~ se midieron antes del arreglo de `text12`, que suma ~50.)

BSRAM 14/26. Registros 3304/6693.

Medir otra combinación:

    GENERICS="ENABLE_RTC=false ENABLE_KANJI=false" bash tools/synth.sh nombre 9k

## Pendiente para la Fase 2+

- Falta el top de placa (`tn9k_top`): PLL desde 27 MHz, reset power-on + S1, pines.
- Presupuesto: PSRAM (~300-500) + HDMI (~150-250) → con todo activado no cabe con margen.
  Opciones: quitar RTC+Kanji (≈90 % antes de PSRAM/HDMI), o pasar SSRAM a BSRAM (79 SSRAM = 474).
- Sin simulador instalado (GHDL): aún no hay verificación funcional, solo síntesis.
