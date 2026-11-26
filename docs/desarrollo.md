# Desarrollo

## Compilación

`tools/synth.sh [nombre] [9k|18k]` desde Git Bash. Salida en `build/<nombre>`.

| Variable | Efecto |
|---|---|
| `TOP` | Entidad superior (por defecto `emsx_core`; la placa es `tn9k_top`) |
| `PNR=1` | Place & route y bitstream |
| `PLACE_OPT`, `ROUTE_OPT` | Opciones de Gowin; cambian el resultado de timing |
| `GENERICS` | Genéricos de `emsx_core` |
| `TOPGENERICS` | Genéricos de `tn9k_top` |
| `CST`, `SDC` | Otros archivos de restricciones |
| `GW_SH` | Ruta de `gw_sh.exe` |

Con la FPGA al 99 %, revisa siempre setup y hold en el informe de timing. Si
algo queda negativo, prueba otro `PLACE_OPT` (en una compilación de depuración
corrigió un hold de -0,138 ns).

Tras añadir o quitar fuentes: `python tools/make_gprj.py`.

## Depuración en la placa

Traza por UART (pines 17 y 32, 115200 8N1). Requiere quitar el OPLL para que
quepa; S2 congela la traza:

```sh
TOP=tn9k_top PNR=1 PLACE_OPT=1 GENERICS="ENABLE_OPLL=false" TOPGENERICS="DBG_TRACE=true" bash tools/synth.sh tn9k_dbg 9k
```

`TOPGENERICS="UART_REPORT=true"` da solo el informe corto. Los campos se
describen en la cabecera de [tn9k_top.vhd](../src/board/tn9k_top.vhd).

En `src/test` hay pruebas independientes: `psram_test_top` y `flash_dump_top`,
cada una con su `.cst` y `.sdc`.

Carga en SRAM desde la línea de comandos, con `programmer_cli` de Gowin:

```
programmer_cli.exe --device GW1NR-9C --run 2 --fsFile ONECHIP_MSX.fs
```

A veces termina sin error pero la FPGA no toma el bitstream: verifica y repite.
Si está definida `PYTHONIOENCODING`, quítala.

## Simulación (GHDL)

Los scripts esperan GHDL en `C:\msys64\ucrt64\bin`.

**VDP.** Compara con volcados de referencia del VDP original (etiqueta de git
`vdp-golden`):

```sh
bash sim/make_golden.sh
bash sim/run_vdp.sh build/sim/golden_src build/sim/golden 5 0   # referencia
bash sim/run_vdp.sh src build/sim/work 5 4                      # VDP actual
```

Los números son la pantalla y la latencia de VRAM en flancos de clk21m. `LT=1`
activa la prueba de interrupción de línea y scroll; `MEM=1` usa el controlador
PSRAM. `sim/check_vdp.sh` recorre todos los modos.

**HDMI.** `bash sim/run_vdp2hdmi.sh` compara la salida píxel a píxel; necesita
antes el volcado de referencia de la pantalla 5.

`bash sim/hdmi/run.sh` decodifica los símbolos TMDS (imagen, paquetes y audio) con un
receptor aparte, en Node; tarda unos 2 minutos. Debe dar `errores {}`, `malos 0` y `bad: 0`.

**Sistema completo.** El segundo argumento es el tiempo simulado en ms:

```sh
bash sim/run_sys.sh build/bios/OCM-BIOS.DAT 30
CLEARTEST=1 bash sim/run_sys.sh build/bios/OCM-BIOS.DAT 300   # borrado de RAM
```

`FASTBOOT=1` precarga la imagen y salta la copia desde la flash. Autopruebas
Z80 (el generador escribe una imagen que hace de BIOS):

```sh
mkdir -p build/sim
python sim/mk_megaram_test.py build/sim/megaram_test.bin
FASTBOOT=1 bash sim/run_sys.sh build/sim/megaram_test.bin 20

python sim/mk_hr_test.py build/sim/hr_test.bin
FASTBOOT=1 PCTIME=22 bash sim/run_sys.sh build/sim/hr_test.bin 9
```

La primera debe dar 00 en C000-C005 y A5 en C00F. `sim/mk_acvs_test.py` (MegaRAM
brasileña) se usa igual y debe dar 00 en C000-C007. En la segunda el bucle debe
durar 222 clk21m (37 T).

## Convenciones

- VHDL-93. Comentarios en inglés en el código; documentación en español.
- `build/` no se versiona: ahí van BIOS, ROMs, contenido de la SD y bitstreams.
  **No subas material con copyright.**
