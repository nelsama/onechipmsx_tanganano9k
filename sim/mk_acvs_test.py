#!/usr/bin/env python3
"""Z80 self test of the Brazilian (ACVS) MegaRAM mode of slot 2 (port 8Eh), as a
fake main BIOS for sim/tb_sys.vhd (FASTBOOT=1). Results in RAM, errors per stage:
  C000 64 banks written through 4000h in write mode (IN 8Eh), read back
       through 4000h in ROM mode (OUT 8Eh), bank selected by a write to 4000h
  C001 read through 6000h   C002 read through 8000h (banks 0-62: 3Fh puts
       the SCC at 9800h)   C003 read through A000h
  C004 a write in ROM mode does not reach the RAM
  C005 slot 2 looks like the loaders check: AC / CA round trip
  C006 SCC in MegaRAM mode: bank 3Fh at 9000h, wave RAM 9800h written / read,
       the bank of 8000h stays 3Fh
  C007 a write to 7FFEh (SCC+ mode) goes back to ESE-SCC: bank register at
       5000h, ROM at 4000h read only (no RAM write enable)
  C00F = A5 when finished"""
import sys
code=bytearray(); fix=[]; lab={}
def b(*x): code.extend(x)
def L(n): lab[n]=len(code)
def jr(op,n): b(op,0); fix.append((len(code)-1,n))
def lda(n): b(0x3E,n)
def sta(a): b(0x32,a&255,a>>8)
def ldam(a): b(0x3A,a&255,a>>8)
def rom(): b(0xD3,0x8E)          # OUT (8Eh),A: ROM mode (bank select)
def wrm(): b(0xDB,0x8E)          # IN A,(8Eh): write mode
b(0xF3,0x31,0x00,0xF0); lda(0xE8); b(0xD3,0xA8)          # DI, SP=F000, slots 0/2/2/3
b(0x0E,0x00)                                             # C = bank
L('w'); rom(); b(0x79); sta(0x4000); wrm()               # select bank, write mode
b(0x79,0xEE,0xA5); sta(0x4000); b(0x2F); sta(0x5FFF)
b(0x0C,0x79,0xFE,0x40); jr(0x20,'w')
rom()
def rd(page,n,res,last=0x40):
    b(0x0E,0x00,0x16,0x00); L('r%d'%n); b(0x79); sta(page); b(0x79,0xEE,0xA5,0x47)
    ldam(page); b(0xB8); jr(0x28,'o%d'%n); b(0x14); L('o%d'%n)
    b(0x78,0x2F,0x47); ldam(page+0x1FFF); b(0xB8); jr(0x28,'p%d'%n); b(0x14); L('p%d'%n)
    b(0x0C,0x79,0xFE,last); jr(0x20,'r%d'%n); b(0x7A); sta(res)
rd(0x4000,1,0xC000); rd(0x6000,2,0xC001); rd(0x8000,3,0xC002,0x3F); rd(0xA000,4,0xC003)
# ROM mode: a write to 4123h selects bank 07 and must not change the data
lda(0x07); sta(0x4123); ldam(0x4000); b(0xD6,0x07^0xA5); sta(0xC004)
# the 1942 loader check, as it does it (4000h): ROM mode, bank 0, write mode,
# write AC, ROM mode, bank 0, read AC back; the same with CA
b(0x16,0)
for v,k in ((0xAC,'k1'),(0xCA,'k2')):
    rom(); b(0xAF); sta(0x4000); wrm(); lda(v); sta(0x4000); rom(); b(0xAF); sta(0x4000)
    ldam(0x4000); b(0xFE,v); jr(0x28,k); b(0x14); L(k)
b(0x7A); sta(0xC005)
# SCC in MegaRAM mode
b(0x16,0); rom(); lda(0x3F); sta(0x9000)
for i in range(8): lda(0x31+i*9); sta(0x9800+i)
for i in range(8):
    ldam(0x9800+i); b(0xFE,0x31+i*9); jr(0x28,'s%d'%i); b(0x14); L('s%d'%i)
lda(0x3F^0xA5); b(0x47); ldam(0x8000); b(0xB8); jr(0x28,'s8'); b(0x14); L('s8')
b(0x7A); sta(0xC006)
# back to ESE-SCC: 7FFEh = 00 (mode A, no RAM write), bank 5 at 5000h, a write
# to 4000h must not change the RAM (bank 5 holds 05^A5)
b(0x16,0); b(0xAF); sta(0x7FFE); lda(0x05); sta(0x5000); lda(0x77); sta(0x4000)
ldam(0x4000); b(0xFE,0x05^0xA5); jr(0x28,'e1'); b(0x14); L('e1')
b(0x7A); sta(0xC007)
lda(0xA5); sta(0xC00F); b(0x18,0xFE)
for p,n in fix:
    d=lab[n]-(p+1); assert -128<=d<128; code[p]=d&255
img=bytearray(b'\xff'*0x40000); img[0:2]=b'AB'; img[0x10000:0x10000+len(code)]=code
open(sys.argv[1],'wb').write(img); print(len(code),'bytes of code')
