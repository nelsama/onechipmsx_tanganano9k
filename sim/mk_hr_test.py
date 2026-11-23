#!/usr/bin/env python3
"""Z80 test: the HR (S#2 bit 5) wait loop of Space Manbow (42A4h), as a fake
main BIOS for sim/tb_sys.vhd (FASTBOOT=1). C000h counts the HR pulses seen."""
import sys
c=bytes.fromhex('F3 3EE0 D3A8 3100F0 AF 3200C0 3E02 D399 3E8F D399 0E99'.replace(' ',''))
loop=len(c)
c+=bytes.fromhex('ED78CB6F28FA'+'ED78CB6F20FA'+'3A00C03C3200C0'); c+=bytes([0x18,(loop-(len(c)+2))&255])
img=bytearray(b'\xff'*0x40000); img[0:2]=b'AB'; img[0x10000:0x10000+len(c)]=c
open(sys.argv[1],'wb').write(img); print('loop at %04X, %d bytes'%(loop,len(c)))
