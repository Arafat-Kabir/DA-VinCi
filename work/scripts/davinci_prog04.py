# An assembly program for DA-VinCi
# Written for DavinciAsm v0.x for testing.
import math
import numpy as np
import sys
from activation import sigmoid
from activation import tblSigm, tblTanh     # pre-computed activation tables
from activation import float2fxp_round

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
outfile   = 'davinci_prog04.bin'
outCfile  = 'davinci_prog04.c'
cprogname = 'prog04'
expfile   = 'davinci_prog04_exp.bin'         # expected output in $readmemb() format
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
np.random.seed(8)       # fixed seed to keep tests predictable
M1 = np.random.uniform(-2, 2, (peRowCnt, peColCnt))
V1 = np.random.uniform(-1, 1, peColCnt)
B1 = np.random.uniform(-1, 1, peRowCnt)
M2 = np.random.uniform(-2, 2, (peRowCnt, peColCnt))
V2 = np.random.uniform(-1, 1, peColCnt)
B2 = np.random.uniform(-1, 1, peRowCnt)
D  = np.random.uniform(-1, 1, peRowCnt)


# result = sigmoid(M1@V1 + B1) * tanh(M2@V2 + B2) + D
fltA = sigmoid(M1 @ V1 + B1)
fltB = np.tanh(M2 @ V2 + B2)
fltE = fltA * fltB + D
result = fltE  # result at full-precision
print('INFO: Result at full-precision')
print(result)

# computes the M@V+B in fixed point for the given float matrix & vectors
def getLinFxp(M, V, B):
    Mfxp = (M*scaleFact).astype(int)
    Vfxp = (V*scaleFact).astype(int)
    Bfxp = (B*scaleFact).astype(int)
    prodFxp = (Mfxp*Vfxp) >> fracWidth  # simulate DA-VinCi multfxp operation
    acumFxp = np.sum(prodFxp, axis=1)   # accumulate along rows
    linFxp  = acumFxp + Bfxp            # result of M@V + B
    return linFxp

# Given an integer vector, computes the output of the VV-Engine activation()
# instruction on that vector.
def getActResult(vec, actfn):
    vec  = vec & ~(0xF)        # discard the lower 4-bits
    ovec = actfn(vec/256)      # compute activation of the fixed-point Q8.8
    # converts to fixed-point representation of the activation value (with rounding)
    for i in range(len(ovec)):
        ovec[i] = float2fxp_round(ovec[i], fracWidth=8)
    ovec = np.array(ovec, dtype=int)    # convert to integer array
    return ovec

# compute the expected output in fixed-point for automated testing
fxpA = getActResult(getLinFxp(M1, V1, B1), sigmoid)
fxpB = getActResult(getLinFxp(M2, V2, B2), np.tanh)
fxpD = (D*scaleFact).astype(int)
fxpE = ((fxpA * fxpB) >> fracWidth) + fxpD
expOut = fxpE


# compute the standard deviation between float and fxp results
print(f'INFO: Result at fixed-precision with fracWidth={fracWidth}')
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
# following assembly program loads the equivalent of the matrices and vectors
# and column vector B, then performs 
# result = sigmoid(M1@V1 + B1) * tanh(M2@V2 + B2) + D

# -- Register allocation
vregB1 = 1
vregB2 = 2
vregD  = 3
vregR1 = 4   # To store temporaries
vregR2 = 5
vregR3 = 6

mregM1 = 0
mregV1 = 1
mregM2 = 2
mregV2 = 3
mregProd = 4
mregAcum = 5

# -- Initialization
# clear out first few registers of MV-Engine
for reg in range(8): mv_CLRREG(reg, comment='initial clear')
as_addComment('Finished clearing out\n')

# Load the Activation tables in VV-Engine
addr_sigm = ACTCODE.SIGM << 8     # base address of sigmoid table
addr_tanh = ACTCODE.TANH << 8     # base address of tanh table
for i in range(1<<8):
    vv_write(addr_sigm+i, tblSigm[i])
    vv_write(addr_tanh+i, tblTanh[i])
as_addComment('Finished writing activation tables\n')


# -- Load the matrix and vector
mv_LOADMAT(reg=mregM1, matrix=M1); as_addComment('Finished writing M1\n')
mv_LOADMAT(reg=mregM2, matrix=M2); as_addComment('Finished writing M2\n')
mv_LOADVEC_ROW(reg=mregV1, vector=V1); as_addComment('Finished writing vector V1\n')
mv_LOADVEC_ROW(reg=mregV2, vector=V2); as_addComment('Finished writing vector V2\n')
vv_LOADVEC(reg=vregB1, vector=B1); as_addComment('Finished writing bias vector B1\n')
vv_LOADVEC(reg=vregB2, vector=B2); as_addComment('Finished writing bias vector B2\n')
vv_LOADVEC(reg=vregD, vector=D); as_addComment('Finished writing bias vector D\n')

# -- Perform MV-Engine computations
mv_MULTFXP(rd=mregProd, multiplicand=mregV1, multiplier=mregM1)

vv_serialEn()   # enable serial shifting before accumulation to collect M1@V1 into VV-Engine
mv_ALLACCUM(rd=mregAcum, rs=mregProd)   # Perform accumulation
mv_SYNC()       # Wait till the accumulation finishes
vv_shiftOff()   # disable all shifting before starting next MV-Operation

mv_MULTFXP(rd=mregProd, multiplicand=mregV2, multiplier=mregM2) # start next multiplication, while we process current vector

# -- Perform VV-Engine computations on M1@V1 (next multiplication in background)
vv_add(vregB1, VVREG.S)
# Apply Sigmoid
vv_mov(VVREG.ACT, VVREG.O)
vv_activ(ACTCODE.SIGM)
vv_mov(vregR1, VVREG.O)     # R1 = sigmoid(M1@V1 + B1)

# -- Capture the M2@V2 result
vv_serialEn()   # enable serial shifting before accumulation to collect M2@V2 into VV-Engine
mv_ALLACCUM(rd=mregAcum, rs=mregProd)   # Perform accumulation for M2@V2
mv_SYNC()       # Wait till the accumulation finishes
vv_shiftOff()   # disable all shifting before processing current vector

# -- Perform VV-Engine computations on M2@V2
vv_add(vregB2, VVREG.S)
# Apply Tanh
vv_mov(VVREG.ACT, VVREG.O)
vv_activ(ACTCODE.TANH)
vv_mov(vregR2, VVREG.O)     # R2 = tanh(M2@V2 + B2)

# -- Perform point-wise operations
vv_mult(vregR1, vregR2)
vv_mov(VVREG.S, VVREG.O)    # SREG = R1*R2
vv_add(vregD, VVREG.S)      # OREG = (R1*R2) + D

# -- Shift-out result
vv_mov(VVREG.S, VVREG.O)
vv_parallelEn()             # enable parallel shifting




# Export the binary for verilog $readmemb()
davinci_as.export_verilogBin(outfile)
davinci_as.export_CprogHex(cprogname, outCfile)

