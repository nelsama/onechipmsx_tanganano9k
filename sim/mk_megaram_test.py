#!/usr/bin/env python3
"""Z80 self test of the MegaRAM (ESE-SCC) as a fake main BIOS, for sim/tb_sys.vhd
(FASTBOOT=1). Results are written to RAM: C000h.. = one byte per stage, errors:
  C000 64 banks written through 4000h (mode A bit 4), read through 4000h
  C001 read through 6000h   C002 read through 8000h (banks 0-62)
  C003 read through A000h   C004 SCC wave RAM 9800h (bank 3Fh)
  C005 ROM write protected  C00F = A5 when finished"""
import sys
code=bytearray(); fix=[]; lab={}
def b(*x): code.extend(x)
def L(n): lab[n]=len(code)
def jr(op,n): b(op,0); fix.append((len(code)-1,n))
def lda(n): b(0x3E,n)
def sta(a): b(0x32,a&255,a>>8)
def ldam(a): b(0x3A,a&255,a>>8)
b(0xF3,0x31,0x00,0xF0); lda(0xE8); b(0xD3,0xA8)          # DI, SP=F000, slots 0/2/2/3
b(0x0E,0x00)                                             # write: C = bank
L('w'); b(0xAF); sta(0x7FFE); b(0x79); sta(0x5000); lda(0x10); sta(0x7FFE)
b(0x79,0xEE,0xA5); sta(0x4000); b(0x2F); sta(0x5FFF)
b(0xAF); sta(0x7FFE); b(0x0C,0x79,0xFE,0x40); jr(0x20,'w')
def rd(reg,page,n,res,last=0x40):
    b(0x0E,0x00,0x16,0x00); L('r%d'%n); b(0x79); sta(reg); b(0x79,0xEE,0xA5,0x47)
    ldam(page); b(0xB8); jr(0x28,'o%d'%n); b(0x14); L('o%d'%n)
    b(0x78,0x2F,0x47); ldam(page+0x1FFF); b(0xB8); jr(0x28,'p%d'%n); b(0x14); L('p%d'%n)
    b(0x0C,0x79,0xFE,last); jr(0x20,'r%d'%n); b(0x7A); sta(res)
rd(0x5000,0x4000,1,0xC000); rd(0x7000,0x6000,2,0xC001,)
rd(0x9000,0x8000,3,0xC002,0x3F); rd(0xB000,0xA000,4,0xC003)
lda(0x3F); sta(0x9000); b(0x16,0)                         # SCC wave RAM
for i in range(8): lda(0x31+i*9); sta(0x9800+i)
for i in range(8):
    ldam(0x9800+i); b(0xFE,0x31+i*9); jr(0x28,'s%d'%i); b(0x14); L('s%d'%i)
b(0x7A); sta(0xC004)
b(0xAF); sta(0x5000); lda(0x77); sta(0x4000); ldam(0x4000); b(0xD6,0xA5); sta(0xC005)
lda(0xA5); sta(0xC00F); b(0x18,0xFE)
for p,n in fix:
    d=lab[n]-(p+1); assert -128<=d<128; code[p]=d&255
img=bytearray(b'\xff'*0x40000); img[0:2]=b'AB'; img[0x10000:0x10000+len(code)]=code
open(sys.argv[1],'wb').write(img); print(len(code),'bytes of code')
