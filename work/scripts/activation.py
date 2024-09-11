#!python3
import numpy as np


# Given an integer and a bit-width, returns a python integer that
# represents the signed interpretation of the given integer (val)
# using those many bits.
def makeSigned(val, bitWidth):
    assert bitWidth > 0             # bitWidth must be a positive number
    mask = (1 << bitWidth) - 1      # mask = 0xFF, for bitWidth = 8
    if val & (1 << (bitWidth-1)):   # check sign-bit
        # it is a negative number
        outnum  = (-1 << bitWidth)  # set all higher bits to 1, and lower bits to 0
        outnum |= (val & mask)      # put the val bits in the lower bits of outnum
    else:
        outnum = val & mask         # make all upper bit zero
    return outnum


# Given a float, maps it to the fixed-point number with given no. 
# of fractional bits (truncates the fractional bits).
def float2fxp(val, fracWidth=8):
    val = int(val * 2**fracWidth)
    return val


# Given a fixed-point number and no. of fraction bits, maps it to the 
# corresponding floating point value.
def fxp2float(val, fracWidth=8):
    val = val / 2**fracWidth
    return val


# Given a float, maps it to the NEAREST fixed-point number (rounding).
def float2fxp_round(val, fracWidth=8):
    lfxp = float2fxp(val, fracWidth)    # get the truncated fixed-point (lower point)
    if val >= 0: ufxp = lfxp + 1        # get the next fixed-point (upper point)
    else: ufxp = lfxp - 1
    # get the actual values of the fixed-points
    lflt = fxp2float(lfxp, fracWidth)
    uflt = fxp2float(ufxp, fracWidth)
    # compare the difference and return the closest
    if abs(uflt - val) < abs(lflt - val): return ufxp
    return lfxp


# Given a floating point value, it returns another floating point
# number which corresponds to the fixed-point number using the 
# given fracWidth.
def fxptruncat(val, fracWidth):
    return fxp2float(float2fxp(val, fracWidth), fracWidth)


# Computes teh sigmoid function
def sigmoid(x):
    return 1/(1 + np.exp(-x))


# Object to emulate VV-engine algorithms
class VVBram:
    def __init__(self, depth=2**10):
        self.data = np.zeros(depth, dtype=np.int16)     # Memory array holding 16-bit signed integers


    # Basic read from the memory array
    def memRead(self, addr):
        assert addr >= 0, 'Address needs to be an unsigned number'
        return self.data[addr]


    # Dumps the data array into a text file
    def dumpData(self, fpath):
        addr = 0
        with open(fpath, 'w') as fout:
            for d in self.data:
                fout.write(f'{addr:>4}: {d}\n')
                addr += 1
        print(f'INFO: {addr} rows written to {fpath}')


    # Given a register number, returns its content
    def getReg(self, reg):
        assert reg>=0 and reg<256, 'Valid registers: 0 ... 255'   # VV-Engine block has only 256 register
        return self.data[reg]


    # Given a Q8.8 fixed-point number, maps it to the activation table 
    # entry address (8-bit unsigned val). This function represents
    # the Act-Lookup module in the hardware that takes a 16-bit value from the
    # ACT register then generates the address in the activation table.
    def mapACT2Addr(self, val, dbg=False):
        # Checks
        valSize = 16    # 16-bit unsigned number representing a signed fixed-point value
        valMin  = 0
        valMax  = 2**(valSize) - 1
        assert val >= valMin and val <= valMax, f'val={val} out of range ({valMin}, {valMax})'
        # Activation table row address algorithm for Q8.8 fixed-point number
        #  - Check 5 Msb's to determine the value range: non-linear, +ve
        #    saturation, -ve saturation.
        #  - If saturation, generate saturation address
        #  - else, middle 8-bits are used as the lookup address
        # compute the value range 
        val = val & 0xFFFF          # make 16-bit unsigned value
        msb5 = (val >> 11) & 0x1F   # extract the bits at bit-positions 11-15
        if msb5 == 0 or msb5 == 0x1F: rng = 'nl'   # non-linear range
        elif msb5 >> 4: rng = 'ns'   # -ve saturation (sign-bit set)
        else: rng = 'ps'             # +ve saturation
        if dbg: print(f'rng : {rng}')    # DEBUG
        # compute lookup address
        ps_addr = 2**7 - 1     # address of +ve saturation value; max 8-bit 2's complement number (+ve)
        ns_addr = 2**7         # address of -ve saturation value; min 8-bit 2's complement number (-ve)
        if   rng == 'nl': addr = (val >> 4) & 0xFF    # middle 8-bits
        elif rng == 'ps': addr = ps_addr
        elif rng == 'ns': addr = ns_addr
        if dbg: print(f'addr: {addr} ({makeSigned(addr, 8)})')
        return addr


    # Given an activation function, builds the activation lookup table 
    # for Q4.4 fixed-point values. The output of the activation function
    # is encoded as Q8.8 signed fixed-point values.
    # The table can be written to a contiguous segment of the BRAM to be used
    # in conjunction with the mapACT2Addr() function.
    # @param actFn  The activation function
    # @param psat   +ve saturation value
    # @param nsat   -ve saturation value
    # @return activation table as numpy array
    def makeActTable(self, actFn, psat, nsat):
        inValSize = 8       # 8-bit unsigned number (address) representing a signed fixed-point value
        inFracWidth = 4     # No. of fraction bits of the fixed-point number for the activation input
        outFracWidth = 8    # No. of fraction bits of the fixed-point number for the activation table (output)
        depth = 2**inValSize  # No. of rows in the table
        table = np.zeros(depth, dtype=np.int16)
        # Populate the table with activation values
        for addr in range(depth):
            signedVal = makeSigned(addr, inValSize)     # Treat the address as a signed int (fixed-point)
            fltVal = fxp2float(signedVal, inFracWidth)  # convert the fixed-point to its float value
            actVal = actFn(fltVal)                      # compute the activation output
            # actFxp = float2fxp(actVal, outFracWidth)    # convert the float output to its fixed-point value
            actFxp = float2fxp_round(actVal, outFracWidth)    # convert the float output to its fixed-point value (rounding has better accuracy)
            table[addr] = actFxp    # save in the table
        # save the saturation values
        ps_addr = 2**(inValSize-1) - 1
        ns_addr = ps_addr + 1
        table[ps_addr] = float2fxp(psat, outFracWidth)
        table[ns_addr] = float2fxp(nsat, outFracWidth)
        return table

    
    # Given an activation table and its activation code,
    # it writes the activation table to the BRAM.
    def loadActTable(self, table, actCode):
        # Checks
        validCode = {1,2,3}
        validDepth = 2**8       # valid depth of the table
        assert actCode in validCode, f'actCode: {actCode} is not valid {validCode}'
        assert len(table) == validDepth, f'Activation table needs {validDepth} entries'
        startAddr = actCode << 8
        endAddr   = startAddr + validDepth
        self.data[startAddr:endAddr] = table

    
    # This function simulations the lookup process in the VV-Engine block.
    # Given a 16-bit Q8.8 fixed-point value, it returns the activation
    # output in Q8.8 fixed-point format.
    def lookupACT(self, actVal, actCode):
        # Checks
        validCode = {1,2,3}
        assert actCode in validCode, f'actCode: {actCode} is not valid {validCode}'
        # Lookup the activation value
        tblAddr  = self.mapACT2Addr(actVal)   # get the address in the activation table
        bramAddr = (actCode << 8) + tblAddr   # prepend activation code to get the BRAM address
        actFxp   = self.memRead(bramAddr)
        return actFxp



# ---- Main ----
import matplotlib.pyplot as plt


bram = VVBram()

# build the activation tables
SIGM = 1
TANH = 2
tblSigm = bram.makeActTable(sigmoid, 1, 0)
tblTanh = bram.makeActTable(np.tanh, 1, -1)

# load the activation tables
bram.loadActTable(tblSigm, SIGM)
bram.loadActTable(tblTanh, TANH)


# Given a floating point value, applies the activation function
# from the VVBram() instance objBram. By default, uses the 
# global object name bram.
def applyBramActivation(val, actCode, objBram=bram):
    # Checks
    valSize = 16    # 16-bit unsigned number representing a signed fixed-point value
    fracWidth = 8   # fixed-point fraction bits
    fxpScale = 1 << fracWidth
    valMin   = (-2**(valSize-1)) / fxpScale
    valMax   = (2**(valSize-1) - 1) / fxpScale
    assert val >= valMin and val <= valMax, f'val={val} out of range ({valMin}, {valMax})'
    # Activation table row address algorithm for Q8.8 fixed-point number
    valACT = float2fxp(val, fracWidth) & 0xFFFF   # convert to Q8.8 fixed-point value for ACT register
    actFxp = objBram.lookupACT(valACT, actCode)
    actVal = fxp2float(actFxp, fracWidth)         # convert to floating-point value
    return actVal


# Given an activation function (with saturation values), computes the
# activation values using the original function and the BRAM object for all
# 16-bit Q8.8 fixed-point values. It returns a tuple as follows, 
# (xvals, accAct, bramAct). These arrays can be used to compare the
# bram-computed activation values with the accurate values.
def get16bActVals(actFn, psat, nsat):
    fracWidth = 8
    xvals = []      # will hold the x-values
    bramAct = []    # will hold the activation values computed using the BRAM
    accAct = []     # will hold the accurate activation values
    # Set up the bram unit
    lbram = VVBram()    # a local instance of the BRAM object
    actTable = lbram.makeActTable(actFn, psat, nsat)
    actCode =  1        # any valid code would work
    lbram.loadActTable(actTable, actCode)
    # loop through all 16-bit numbers and compute the activation values
    for num in range(-2**15, 2**15):    # loops upto and including (2**15 - 1)
        # compute the x-value
        fxpNum = makeSigned(num, 16)            # make it a signed 16-bit value
        fltNum = fxp2float(fxpNum, fracWidth)   # convert to corresponding float
        xvals.append(fltNum)
        # compute the activation values
        accAct.append(actFn(fltNum))
        bramAct.append(applyBramActivation(fltNum, actCode, lbram))
    return xvals, accAct, bramAct


# Same as get16bActVals() but for 8-bit Q4.4 values (orignal mapping)
def get8bActVals(actFn, psat, nsat):
    fracWidth = 4
    xvals = []      # will hold the x-values
    bramAct = []    # will hold the activation values computed using the BRAM
    accAct = []     # will hold the accurate activation values
    # Set up the bram unit
    lbram = VVBram()    # a local instance of the BRAM object
    actTable = lbram.makeActTable(actFn, psat, nsat)
    actCode =  1        # any valid code would work
    lbram.loadActTable(actTable, actCode)
    # loop through all 16-bit numbers and compute the activation values
    for num in range(-2**7, 2**7):
        # compute the x-value
        fxpNum = makeSigned(num, 8)             # make it a signed 8-bit value
        fltNum = fxp2float(fxpNum, fracWidth)   # convert to corresponding float
        xvals.append(fltNum)
        # compute the activation values
        accAct.append(actFn(fltNum))
        bramAct.append(applyBramActivation(fltNum, actCode, lbram))
    return xvals, accAct, bramAct


# Plots the activation values for Q8.8 fixed-point numbers
def plot16bActivationTable(actFn, psat, nsat):
    xvals, accAct, bramAct = get16bActVals(actFn, psat, nsat)
    # Plot them
    plt.figure()
    plt.plot(xvals, accAct, 'ro-', markersize=3) 
    plt.plot(xvals, bramAct, 'gx-', markersize=3) 
    plt.show()


# Plots the activation values for Q8.8 fixed-point numbers
def plot8bActivationTable(actFn, psat, nsat):
    xvals, accAct, bramAct = get8bActVals(actFn, psat, nsat)
    # Plot them
    plt.figure()
    plt.plot(xvals, accAct, 'ro-', markersize=3) 
    plt.plot(xvals, bramAct, 'gx-', markersize=3) 
    plt.show()


# Computes the mean-square-error between the bram-computed
# activation values with the accurate values.
def getActMSE(actFn, psat, nsat):
    xvals, accAct, bramAct = get8bActVals(actFn, psat, nsat)    # uses the Q4.4 values, the original mapping
    accAct   = np.array(accAct)
    bramAddr = np.array(bramAct)
    err = accAct - bramAct
    mse = np.square(err).mean()
    return mse


# Computes the mean-absolute-error between the bram-computed
# activation values with the accurate values.
def getActMAE(actFn, psat, nsat):
    xvals, accAct, bramAct = get8bActVals(actFn, psat, nsat)    # uses the Q4.4 values, the original mapping
    accAct   = np.array(accAct)
    bramAddr = np.array(bramAct)
    err = accAct - bramAct
    mae = np.abs(err).mean()
    return mae


