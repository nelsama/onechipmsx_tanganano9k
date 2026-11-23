# Fase 0 — Recursos del diseño original (2026-11-20)

> Documento histórico del port. El estado actual está en [arquitectura.md](arquitectura.md).

GowinSynthesis 1.9.12.03, `tools/synth.sh`. Diseño sin recortes, PLL stub (`xil_pll4x.vhd`).

## Total en GW1NR-9 (Tang Nano 9K)

**8880 / 8640 lógica (103 %)** = 7690 LUT + 716 ALU + 79 SSRAM×6 → no cabe por 240.
BSRAM 17 / 26. Registros 3656 / 6693.

Nota: cada SSRAM (RAM distribuida) cuesta 6 de lógica → 79 SSRAM = 474. Pasarlas a BSRAM (quedan 9 libres) ahorra lógica.

## Desglose por módulo (lógica = LUT + ALU + 6×SSRAM, medido en GW2AR-18)

| Inst. | Módulo | Lógica | BSRAM | Grupo |
|---|---|---:|---:|---|
| U20 | vdp (total) | 2570 | 8 | D |
| ↳ | vdp propio (cmd engine, regs, timing, debug window) | 1647 | 1 | D/A |
| ↳ | sprite | 432 | 2 | D |
| ↳ | text12 / graphic123M / graphic4567 | 156 / 69 / 86 | 0/0/1 | D |
| ↳ | vga (+doublebuf) | 61 | 2 | D |
| ↳ | osd | 58 | 2 | **A** |
| ↳ | ntsc / pal | 27 / 15 | 0 | **A** |
| U01 | t80a | 1855 | 1 | D |
| U32 | eseopll (vm2413) | 1732 | 4 | C |
| — | emsx_top (lógica propia: slot, SDRAM ctrl, mezcla audio, vídeo, OSD test, DIP) | 1108 | 0 | A parcial |
| U31 | megaram + SCC | 407 | 1 | C |
| U30 | psg | 345 | 0 | D |
| U07 | rtc | 257 | 0 | C |
| U21 | vencode | 229 (+5 MULT9X9) | 0 | **A** |
| U06 | eseps2 (+keymap) | 212 | 2 | D |
| U33 | esepwm + esefir5 | 62 | 0 | B |
| U03 | megasd | 61 | 0 | D |
| U05 | mapper | 34 | 0 | D |
| U08 | kanji | 27 | 0 | B |
| U02 | iplrom | 0 | 1 | D |

## Presupuesto estimado para la 9K

- Se va: grupo A (~330 medibles + parte de los 1108 de emsx_top + debug window del VDP) y el controlador SDRAM.
- Entra: controlador PSRAM (~300-500) y encoder HDMI/TMDS (~150-250).
- Objetivo realista tras PnR: ≤ ~7800 (≈ 90 %).

## Avisos a limpiar en Fase 1

- Latches: `text12.vhd:389` (blink), `vdp.vhd:961, 2443, 2542`, `eseps2.vhd:417`, `psg.vhd:162`, `rtc.vhd:272`,
  `vm2413/Controller.vhd:466`, `EnvelopeGenerator.vhd:257`, `PhaseGenerator.vhd:174`.
- Listas de sensibilidad incompletas en `text12.vhd`.

## Cambios hechos para poder sintetizar

- `emsx_top.vhd`: el "AL FIX for XST" había cambiado `case (DispMode + DispSel)` por una concatenación de 4 bits
  (rompía la semántica y no compila en Gowin). Restaurada la suma de 2 bits con una variable `DispSum`.
