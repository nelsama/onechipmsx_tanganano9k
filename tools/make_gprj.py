#!/usr/bin/env python3
"""Generate the Gowin IDE project (ONECHIP_MSX.gprj + its process config).

Same sources and options as tools/synth.sh PNR=1: every src/**/*.vhd,
src/board/tn9k.cst / tn9k.sdc, top tn9k_top, VHDL-93, MSPI pins as GPIO
(the SPI flash is on the MSPI pins 59-62).

Run it again after adding or removing source files:
    python tools/make_gprj.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "ONECHIP_MSX"
TOP = "tn9k_top"

files = []
for d, _, fs in os.walk(os.path.join(ROOT, "src")):
    for f in fs:
        if f.endswith(".vhd"):
            files.append(os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/"))
files.sort()

lines = [
    '<?xml version="1" encoding="UTF-8"?>',
    "<!DOCTYPE gowin-fpga-project>",
    "<Project>",
    "    <Template>FPGA</Template>",
    "    <Version>5</Version>",
    '    <Device name="GW1NR-9C" pn="GW1NR-LV9QN88PC6/I5">gw1nr9c-004</Device>',
    "    <FileList>",
]
lines += ['        <File path="%s" type="file.vhdl" enable="1"/>' % f for f in files]
lines += [
    '        <File path="src/board/tn9k.cst" type="file.cst" enable="1"/>',
    '        <File path="src/board/tn9k.sdc" type="file.sdc" enable="1"/>',
    "    </FileList>",
    "</Project>",
    "",
]
with open(os.path.join(ROOT, NAME + ".gprj"), "w", newline="\r\n") as f:
    f.write("\n".join(lines))

# Process configuration (Gowin IDE "Configuration" dialog), Gowin 1.9.12
cfg = {
    "BACKGROUND_PROGRAMMING": "off", "COMPRESS": False, "CPU": False, "CRC_CHECK": True,
    "Clock_Route_Order": 0, "Co-Place_IO_Registers": False,
    "Convert_SDP32_36_to_SDP16_18": True, "Correct_Hold_Violation": True, "DONE": False,
    "DOWNLOAD_SPEED": "default", "DSP_Style": "Auto", "Disable_Insert_Pad": False,
    "ENABLE_CTP": False, "ENABLE_MERGE_MODE": False, "ENCRYPTION_KEY": False,
    "ENCRYPTION_KEY_TEXT": "00000000000000000000000000000000",
    "ERROR_DECTION_AND_CORRECTION": False, "ERROR_DECTION_ONLY": False,
    "ERROR_INJECTION": False, "EXTERNAL_MASTER_CONFIG_CLOCK": False, "Enable_DSRM": False,
    "FORMAT": "binary", "FREQUENCY_DIVIDER": "1",
    "Generate_Constraint_File_of_Ports": False, "Generate_IBIS_File": False,
    "Generate_Plain_Text_Timing_Report": False,
    "Generate_Post_PNR_Simulation_Model_File": False, "Generate_Post_Place_File": False,
    "Generate_SDF_File": False, "Generate_VHDL_Post_PNR_Simulation_Model_File": False,
    "Global_Freq": "default", "GwSyn_Loop_Limit": 2000, "HOTBOOT": False, "I2C": False,
    "I2C_SLAVE_ADDR": "00", "INCREMENTAL_PLACE_AND_ROUTING": "0",
    "INCREMENTAL_PLACE_ONLY": "0", "IncludePath": [], "Incremental_Compile": "",
    "Initialize_Primitives": False, "JTAG": False, "MODE_IO": False,
    "MSPI": True,                                   # flash pins 59-62 as GPIO
    "MSPI_JUMP": False, "MULTIBOOT_ADDRESS_WIDTH": "24", "MULTIBOOT_MODE": "Single",
    "MULTIBOOT_SPI_FLASH_ADDRESS": "00000000", "MULTIJUMP_ADDRESS_WIDTH": "24",
    "MULTIJUMP_MODE": "Single", "MULTIJUMP_SPI_FLASH_ADDRESS": "000000",
    "Map_Option": "1", "Max_Fanout": 1000, "Multi_Boot": True, "Netlist_Hierarchy": True,
    "OUTPUT_BASE_NAME": TOP, "Optimization_Goal": "Auto", "POWER_ON_RESET_MONITOR": True,
    "PRINT_BSRAM_MODE": "Default Mode", "PRINT_BSRAM_VALUE": True,
    "PROGRAM_DONE_BYPASS": False, "PlaceInRegToIob": True, "PlaceIoRegToIob": True,
    "PlaceOutRegToIob": True, "Place_Option": "0", "Process_Configuration_Verion": "1.0",
    "Promote_Physical_Constraint_Warning_to_Error": True, "RAM_Style": "Auto",
    "READY": False, "RECONFIG_N": False, "ROM_Style": "Auto", "Ram_RW_Check": False,
    "Replicate_Resources": False, "Report_Auto-Placed_Io_Information": False,
    "Route_Maxfan": "23", "Route_Option": "0", "Run_Timing_Driven": True,
    "SECURE_MODE": False, "SECURITY_BIT": True, "SEU_HANDLER": False,
    "SEU_HANDLER_CHECKSUM": False, "SEU_HANDLER_MODE": "auto", "SSPI": False,
    "STOP_SEU_HANDLER": False, "SerDes_retiming": False, "Shift_Registers_Style": "Auto",
    "Show_All_Warnings": False, "Synthesize_tool": "GowinSyn", "TclPre": "",
    "TopModule": TOP, "USERCODE": "default",
    "Unused_Pin": "As_input_tri_stated_with_pull_up", "VCC": "1.2", "VCCAUX": "3.3",
    "VCCX": "3.3", "VHDL_Standard": "VHDL_Std_1993", "Verilog_Standard": "Vlg_Std_2001",
    "WAKE_UP": "0", "show_all_warnings": False, "turn_off_bg": False,
}
os.makedirs(os.path.join(ROOT, "impl"), exist_ok=True)
with open(os.path.join(ROOT, "impl", NAME + "_process_config.json"), "w", newline="\r\n") as f:
    json.dump(cfg, f, indent=4)
    f.write("\n")

print("%s.gprj: %d VHDL files + cst + sdc, top %s" % (NAME, len(files), TOP))
