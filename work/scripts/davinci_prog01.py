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
outfile   = 'davinci_prog01.bin'
outCfile  = 'davinci_prog01.c'
cprogname = 'prog01'
expfile   = 'davinci_prog01_exp.bin'         # expected output in $readmemb() format
regWidth  = davinci_as.picaso_as.regWidth
fracWidth = davinci_as.fracWidth
scaleFact = 1 << fracWidth          # fixed-point scaling factor
# davinci dimensions
picRowCnt = 16   # no. of PiCaSO block rows
picColCnt = 4    # no. of PiCaSO block columns
peRowCnt  = picRowCnt
peColCnt  = picColCnt*16    # 16 PEs per block column
maxLevel  = math.ceil(math.log(picColCnt, 2)) - 1   # max level for accumRow()


# ---- Test input/output generation
# Generate random test case
np.random.seed(2)       # fixed seed to keep tests predictable
M = np.random.uniform(0, 2, (peRowCnt, peColCnt))
V = np.random.uniform(0, 1, peColCnt)
prod = M @ V      # dot-product with full-precision
print('INFO: M@V product at full-precision')
print(prod)

# compute the expected output in fixed-point for automated testing
Mfxp = (M*scaleFact).astype(int)
Vfxp = (V*scaleFact).astype(int)
prodFxp = (Mfxp*Vfxp) >> fracWidth  # simulate DA-VinCi multfxp operation
acumFxp = np.sum(prodFxp, axis=1)   # accumulate along rows
expOut  = acumFxp

# compute the standard deviation between float and fxp results
print(f'INFO: M@V product at fixed-precision with fracWidth={fracWidth}')
print(expOut/scaleFact)
stdDev = np.sum((prod - (expOut/scaleFact))**2)
stdDev = np.sqrt(stdDev/prod.size)
print(f'INFO: Standard deviation between float and fxp: {stdDev:.6}')

# Export the expected output array file
regMask = (1 << regWidth) - 1
with open(expfile, 'w') as fexp:
    ftext = []
    dataPrefix = 0x0100     # high 16-bits of data rows
    lastPrefix = 0x0300     # high 16-bit of last data row
    for i,e in enumerate(expOut): 
        if i == len(expOut)-1: prefix = lastPrefix
        else: prefix = dataPrefix
        ftext.append(f'{prefix:016b}_{e&regMask:016b}    // data: {e:6} ({e/scaleFact})\n')
    fexp.writelines(ftext)
print(f'INFO: Expected outputs written to {expfile}')




# ---- Assembly program
# following assembly program loads the equivalent of the matrix M and
# vector V, then performs M @ V on them.


# clear out first few registers of GEMV array
for reg in range(8):
    mv_CLRREG(reg, comment='initial clear')
as_addComment('Finished clearing out\n')


# load the matrix and vector
mv_LOADMAT(reg=0, matrix=M); as_addComment('Finished writing matrix\n')
mv_LOADVEC_ROW(reg=1, vector=V); as_addComment('Finished writing vector rows\n')


# Perform block-level MAC
# mv_MULT(rd=2, multiplicand=1, multiplier=0) # performs integer multiplication
# mv_movOffset(fracWidth, rd=4, rs=2)         # get the fixed-point mult output
mv_MULTFXP(rd=4, multiplicand=1, multiplier=0)

# enable serial shifting before accumulation
vv_serialEn()

# Perform accumulation
# mv_RNGACCUM(colCnt=64, rd=5, rs=4)
mv_ALLACCUM(rd=5, rs=4)


# Wait till the accumulation finishes, then start parallel shifting
mv_SYNC()
vv_parallelEn()




# Export the binary for verilog $readmemb()
davinci_as.export_verilogBin(outfile)
davinci_as.export_CprogHex(cprogname, outCfile)

