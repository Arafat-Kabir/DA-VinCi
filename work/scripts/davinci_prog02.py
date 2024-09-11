# An assembly program for DA-VinCi
# Written for DavinciAsm v0.x for testing.
import math
import numpy as np
import sys

from davinci_assembler import *
davinci_as.printCopyright()


# Assembler parameters and compatability checks
assert davinci_as.v_major == 0
davinci_as.setupParams(mvBlockDim=(16,4), fracWidth=8, maxLevel=1,
                       mvRegCnt=60, mvResvRegCnt=4)  # 0-59 are user regs, 60-63 are reserved
print('DA-VinCi Assembler Parameters:')
davinci_as.printParams()
print('')


# Script parameters
outfile   = 'davinci_prog02.bin'
outCfile  = 'davinci_prog02.c'
cprogname = 'prog02'
regWidth  = davinci_as.picaso_as.regWidth
# davinci dimensions
picRowCnt = 16   # no. of PiCaSO block rows
picColCnt = 4    # no. of PiCaSO block columns
peRowCnt  = picRowCnt
peColCnt  = picColCnt*16    # 16 PEs per block column
maxLevel  = math.ceil(math.log(picColCnt, 2)) - 1   # max level for accumRow()


# ---- Assembly program
# MV-Engine instructions
mv_nop(comment='This is a mv_NOP')
mv_mov(rd=5, rs=3)
mv_add(rd=1, rs1=2, rs2=3)
mv_sub(rd=1, rs1=2, rs2=3)
mv_movOffset(offset=8, rd=4, rs=5)

mv_selectBlk(1,1)
mv_selectRow(1)
mv_selectCol(2)
mv_selectAll()

mv_write(123,123) 
mv_blockFold(2, 3, 4, comment='Another comment') 
mv_accumRow(1, 4) 
mv_updatepp(1, 3, 4, 5)

# VV-Engine instructions
vv_serialEn() 
vv_parallelEn() 
vv_shiftOff()
vv_nop()

vv_write(addr=300, data=1234)
vv_selectBlk(10)
vv_selectAll()

vv_mov(rd=VVREG.S, rs=VVREG.O)
vv_mov(rd=VVREG.S, rs=11)
vv_mov(rd=14, rs=VVREG.S)
vv_mov(rd=12, rs=VVREG.O)
vv_mov(rd=VVREG.O, rs=10)
vv_mov(rd=VVREG.ACT, rs=VVREG.O)
vv_mov(rd=VVREG.ACT, rs=19)

vv_add(15, 10)
vv_add(15, VVREG.S)
vv_sub(15, 10)
vv_sub(15, VVREG.S)
vv_mult(15, 10)
vv_mult(15, VVREG.S)

vv_activ(ACTCODE.RELU)
vv_activ(ACTCODE.SIGM)
vv_activ(ACTCODE.TANH)


# Export the binary for verilog $readmemb()
davinci_as.export_verilogBin(outfile)
davinci_as.export_CprogHex(cprogname, outCfile)

