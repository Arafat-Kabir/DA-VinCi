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
outfile   = 'davinci_prog03.bin'
outCfile  = 'davinci_prog03.c'
cprogname = 'prog03'
expfile   = 'davinci_prog03_exp.bin'         # expected output in $readmemb() format
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
M = np.random.uniform(-2, 2, (peRowCnt, peColCnt))
V = np.random.uniform(-1, 1, peColCnt)
B = np.random.uniform(-1, 1, peRowCnt)
# B = np.arange(1, peRowCnt+1)
result = np.maximum((M @ V + B), 0)  # result at full-precision: ReLU(M@V+B)
print('INFO: ReLU(M@V+B) at full-precision')
print(result)

# compute the expected output in fixed-point for automated testing
Mfxp = (M*scaleFact).astype(int)
Vfxp = (V*scaleFact).astype(int)
Bfxp = (B*scaleFact).astype(int)
prodFxp = (Mfxp*Vfxp) >> fracWidth  # simulate DA-VinCi multfxp operation
acumFxp = np.sum(prodFxp, axis=1)   # accumulate along rows
linFxp  = acumFxp + Bfxp            # result of M@V + B
expOut  = np.maximum(linFxp, 0)     # apply ReLU

# compute the standard deviation between float and fxp results
print(f'INFO: ReLU(M@V+B) at fixed-precision with fracWidth={fracWidth}')
print(expOut/scaleFact)
stdDev = np.sum((result - (expOut/scaleFact))**2)
stdDev = np.sqrt(stdDev/result.size)
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
# following assembly program loads the equivalent of the matrix M,
# row vector V, and column vector B, then performs ReLU(M@V +B) on them.

# Register allocation
vregB = 1       # VV-Engine register to load the column-vector
mregM = 0       # MV-Engine register to load the matrix
mregV = 1       # MV-Engine register to load the row-vector
mregProd = 4    # MV-Engine register to store the intermediate product
mregAcum = 5    # MV-Engine register to store the intermediate accumulation result

# clear out first few registers of GEMV array
for reg in range(8): mv_CLRREG(reg, comment='initial clear')
as_addComment('Finished clearing out\n')

# -- Load the matrix and vector
mv_LOADMAT(reg=mregM, matrix=M); as_addComment('Finished writing matrix\n')
mv_LOADVEC_ROW(reg=mregV, vector=V); as_addComment('Finished writing vector rows\n')
vv_LOADVEC(reg=vregB, vector=B); as_addComment('Finished writing bias vector\n')

# -- Perform MV-Engine computations
mv_MULTFXP(rd=mregProd, multiplicand=mregV, multiplier=mregM)
vv_serialEn()   # enable serial shifting before accumulation
mv_ALLACCUM(rd=mregAcum, rs=mregProd)   # Perform accumulation
mv_SYNC()       # Wait till the accumulation finishes, then start parallel shifting

# -- Perform VV-Engine computations
vv_shiftOff()               # disable all shifting
vv_add(vregB, VVREG.S)      # Add bias-vector
# Apply ReLU
vv_mov(VVREG.ACT, VVREG.O)  # copy last result to activation input register
vv_activ(ACTCODE.RELU)      # apply RELU activation
# Shift-out result
vv_mov(VVREG.S, VVREG.O)    # copy activation result to shift-regs
vv_parallelEn()             # enable parallel shifting




# Export the binary for verilog $readmemb()
davinci_as.export_verilogBin(outfile)
davinci_as.export_CprogHex(cprogname, outCfile)

