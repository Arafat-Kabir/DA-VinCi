#===================================================================================#
#   Copyright (c) 2024, Computer Systems Design Lab, University of Arkansas         #
#                                                                                   #
#   All rights reserved.                                                            #
#                                                                                   #
#   Permission is hereby granted, free of charge, to any person obtaining a copy    #
#   of this software and associated documentation files (the "Software"), to deal   #
#   in the Software without restriction, including without limitation the rights    #
#   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell       #
#   copies of the Software, and to permit persons to whom the Software is           #
#   furnished to do so, subject to the following conditions:                        #
#                                                                                   #
#   The above copyright notice and this permission notice shall be included in all  #
#   copies or substantial portions of the Software.                                 #
#                                                                                   #
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR      #
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,        #
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE     #
#   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER          #
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,   #
#   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE   #
#   SOFTWARE.                                                                       #
#===================================================================================#

#================================================================================#
#                                                                                #
#   Author : MD Arafat Kabir                                                     #
#   Email  : arafat.sun@gmail.com                                                #
#   Date   : Fri, Jun 07, 12:39 PM CST 2024
#   Version: v0.1                                                                #
#                                                                                #
#   Description:                                                                 #
#   This is a python module that implements a basic assembler for VVBlock        #
#   controller instruction-set.  Because this is a python module, the assembly   #
#   programs can be written as a python script. As a result, you get some        #
#   convenient features directly from python, like macros (functions), use of    #
#   external modules, complicated computation within the assembly program        #
#   (python script), etc.                                                        #
#                                                                                #
#================================================================================#


class VVBlockAsm:
    # Module information
    v_major = 0
    v_minor = 1
    author  = 'MD Arafat Kabir (arafat.sun@gmail.com, makabir@uark.edu)'
    cpright = 'Copyright (c) 2024, Computer Systems Design Lab, University of Arkansas'

    # build and print invocation header
    invoc_header = [
        f'VVBlock Tile Assember (VVBlockAsm) version {v_major}.{v_minor}',
        f'Author: {author}',
        cpright,
        ''
    ]


    # Tables for machine-code generation
    tbl_opcode = {
      'nop'          : 0,
      'add_xy'       : 1,
      'sub_xy'       : 2,
      'mult_xy'      : 3,
      'add_xsreg'    : 4,
      'sub_xsreg'    : 5,
      'mult_xsreg'   : 6,
      'relu'         : 7,
      'actlookup'    : 8,
      'shiftoff'     : 9,
      'serial_en'    : 10,
      'parallel_en'  : 11,
      'selectblk'    : 12,
      'mov_o2sreg'   : 13,
      'mov_y2sreg'   : 14,
      'mov_sreg2r'   : 15,
      'mov_oreg2r'   : 16,
      'mov_y2oreg'   : 17,
      'mov_oreg2act' : 18,
      'mov_x2act'    : 19,
      'selectall'    : 20,
      'write0'       : 30,   # both 30 and 31 is for WRITE
      'write1'       : 31,   # due to overlap with ADDR field
    }


    tbl_field_width = {
        'opcode' : 5,   # width of the OpCode field
        'addr'   : 10,  # width of the write addresses
        'data'   : 16,  # width of the DATA field
        'reg'    : 8,   # width of the register addresses
        'id'     : 8,   # width of VVBlock IDs
        'actcode': 2    # width of activation table selection codes
    }
    # composite field widths
    tbl_field_width['seg2'] = tbl_field_width['opcode']
    tbl_field_width['seg1'] = tbl_field_width['addr'] - 1   # The MSb of the address will come from LSb of opcode
    tbl_field_width['seg0'] = tbl_field_width['data']


    # A constant-group class
    class _const:
        class ConstError(TypeError): pass
        def __setattr__(self, name, value):
            if name in self.__dict__:
                raise self.ConstError(f'Cannot rebind const({name})')
            self.__dict__[name] = value


    # Special registers as negative values
    REG = _const()
    REG.S = -1
    REG.O = -2
    REG.ACT = -3

    # Activation table selection codes
    ACTCODE = _const()
    ACTCODE.RELU = 0    # does not use a table
    ACTCODE.SIGM = 1
    ACTCODE.TANH = 2
    

    # Class implementation
    def __init__(self):
        self.instructions = []      # will contain internal representation of each instruction
        self.isAssembled = False    # state flag, set to True after assemble
        self.setupParams()          # setup default parameter values


    # Resets the internal state for a fresh new program, preserving the assembler parameters
    def reset(self):
        self.instructions = []
        self.isAssembled = False


    # ---- Development utils: following functions are used in the development of this module

    # Prints a message when an instruction is called which is not implemented yet
    def _instrNotImpl(self, name):
        print(f"WARN: {name} is not implemented yet, skipping")


    def printCopyright(self):
        for line in self.invoc_header: print(line)


    def printParams(self, indent=''):
        print(f'{indent}regCnt  : {self.regCnt}')
        print(f'{indent}regWidth: {self.regWidth}')
        print(f'{indent}idWidth : {self.idWidth}')
        print(f'{indent}actCount: {self.actCount}')


    # Given an assembled instruction, returns a binary text for exporting it to output program
    def makeExportBinText(self, instr, addCmt, addSrc, sep):
        # build machine code for the instruction
        binword = self.makeBinWord(instr['word'], sep=sep)
        # build inline comment
        inlnCmt = []
        if addSrc: inlnCmt.append(instr['src'])        # add source instruction if requested
        if addCmt and instr['comment']: inlnCmt.append(instr['comment'])   # add user comments if requested
        if inlnCmt:
            inlnCmt = self.makeComment('; '.join(inlnCmt))   # build the comment string if comments exist
        else:
            inlnCmt = ''
        # return the text for exporting
        if inlnCmt: text = '  '.join([binword, inlnCmt])
        else: text = binword
        return text


    # converts the provided text into inline comment for exporting
    def makeComment(self, text):
        return f'// {text}'


    # Given a word dictionary with segments, returns the binary representation
    # of the instruction word as a string (with separators)
    def makeBinWord(self, wordDict, sep=''):
        w_seg0 = self.tbl_field_width['seg0']
        w_seg1 = self.tbl_field_width['seg1']
        w_seg2 = self.tbl_field_width['seg2']
        seg2, seg1, seg0 = wordDict['seg2'], wordDict['seg1'], wordDict['seg0']
        # format the instruction word in binary format, with separator {seg:0wb}
        binword = f"{seg2:0{w_seg2}b}{sep}{seg1:0{w_seg1}b}{sep}{seg0:0{w_seg0}b}"
        return binword


    # Given a word dictionary with segments, returns the numeric representation
    # of the instruction word.
    def makeNumWord(self, wordDict):
        w_seg0 = self.tbl_field_width['seg0']
        w_seg1 = self.tbl_field_width['seg1']
        w_seg2 = self.tbl_field_width['seg2']
        word = (wordDict['seg2'] << w_seg1) | wordDict['seg1']
        word = (word << w_seg0) | wordDict['seg0']
        return word


    # Given a register number, returns its address in the VV-Engine BRAM
    def makeRegAddr(self, reg):
        return reg  # VV-Engine has one-to-one mapping for register addresses


    # Given an instruction dictionary (internal representation), Returns the
    # machine code as a dictionary of instruction-word segements (wordDict)
    def genMachineCode(self, instrDict):
        # shorthands for field widths
        w_reg  = self.tbl_field_width['reg']
        w_addr = self.tbl_field_width['addr']
        w_data = self.tbl_field_width['data']
        # get the opcode name and machine code
        opcode = instrDict['opcode']
        opnum  = self.tbl_opcode[opcode]
        # Encode instructions
        if opcode in {'nop', 'relu', 'shiftoff', 'serial_en', 'parallel_en',
                      'selectall', 'mov_o2sreg', 'mov_oreg2act'}:
            # [ opcode ] [ 0 ] [ 0 ]
            seg2 = opnum
            seg1 = 0
            seg0 = 0
        elif opcode in {'add_xy',  'sub_xy', 'mult_xy'}:
            # [ opcode ] [ 0 ] [ RS2, RS1 ]
            rs1, rs2 = instrDict['rs1'], instrDict['rs2']
            seg2 = opnum
            seg1 = 0
            seg0 = (rs2 << w_reg) | rs1
        elif opcode in {'add_xsreg',  'sub_xsreg', 'mult_xsreg', 'mov_x2act'}:
            # [ opcode ] [ 0 ] [ RS2, 0 ]
            rs2 = instrDict['rs2']
            seg2 = opnum
            seg1 = 0
            seg0 = (rs2 << w_reg)
        elif opcode == 'actlookup':
            # [ opcode ] [ 0 ] [ actCode ]
            actCode = instrDict['actcode']
            seg2 = opnum
            seg1 = 0
            seg0 = actCode
        elif opcode == 'selectblk':
            # [ opcode ] [ 0 ] [ blkID, <RS1:0> ]
            blkID = instrDict['id']
            seg2 = opnum
            seg1 = 0
            seg0 = (blkID << w_reg)
        elif opcode in {'mov_y2sreg', 'mov_sreg2r', 'mov_oreg2r', 'mov_y2oreg'}:
            # [ opcode ] [ 0 ] [ 0, RS1 ]
            rs1 = instrDict['rs1']
            seg2 = opnum
            seg1 = 0
            seg0 = rs1
        elif opcode == 'write0':
            # [ opcode ] [ addr:9-bit ] [ data ]
            addr, data = instrDict['addr'], instrDict['data']
            addrMsb = addr >> (w_addr-1)
            addrMask = (1 << (w_addr - 1)) - 1  # to remove the Msb
            dataMask = (1 << w_data) - 1        # to extract unsigned bit pattern
            assert addrMsb == 0 or addrMsb == 1, f'Unexpected value for addrMsb: {addrMsb}'
            if addrMsb == 1: opnum = self.tbl_opcode['write1']
            else: opnum = self.tbl_opcode['write0']
            seg2 = opnum
            seg1 = addr & addrMask
            seg0 = data & dataMask
        else:
            if opcode in self.tbl_opcode:
                assert 0, f"Instruction not implemented yet, opcode: {opcode}"
            else:
                assert 0, f"Invalid opcode: {opcode}"
        # build the word dictionary and return
        w_seg1 = self.tbl_field_width['seg1']
        assert seg1 >= 0 and seg1 < (1 << w_seg1), f'Segment-1 is outside valid range: {w_seg1:X}'      # there is a chance seg1 may be miscalculated
        wordDict = {'seg0' : seg0, 'seg1' : seg1, 'seg2': seg2}
        return wordDict


    # Instruction parameter validation utilities
    def validateReg(self, reg, msg=None):
        if msg==None: msg=f'invalid register: {reg}'
        assert reg >= 0 and reg < self.regCnt, msg

    def validateID(self, blkID, msg=None):
        if msg==None: msg=f'invalid Block ID: {blkID}'
        maxID = 2**self.idWidth - 1
        assert blkID <= maxID and blkID >= 0, msg

    def validateAddress(self, addr, msg=None):
        if msg==None: msg=f'invalid address: {addr}'
        maxAddr = 2**self.tbl_field_width['addr'] - 1
        assert addr <= maxAddr and addr >= 0, msg

    def validateData(self, data, msg=None):
        # all data are signed numbers
        dataWidth = self.tbl_field_width['data']
        minData = -2**(dataWidth-1)
        maxData = -minData - 1
        if msg==None: msg=f'invalid data: {data}, range ({minData}, {maxData})'
        assert data <= maxData and data >= minData, msg

    def validateActCode(self, actCode, msg=None):
        if msg==None: msg=f'invalid actCode: {actCode}'
        minCode = 1
        maxCode = 2**self.tbl_field_width['actcode'] - 1
        assert actCode <= maxCode and actCode >= minCode, msg


    # ---- Assembler directives

    # Sets up assembler parameters
    def setupParams(self, regCnt=256, regWidth=16,  idWidth=8, actCount=3):
        self.regCnt   = regCnt     # maximum no. of registers
        self.regWidth = regWidth   # width of vector registers
        self.idWidth  = idWidth    # width of block IDs
        self.actCount = actCount   # no. of total activation tables
        # only following values are supported for now
        assert regCnt==256
        assert regWidth==16
        assert idWidth==8
        assert actCount==3


    # Compiles the instructions into machine code for exporting
    def assemble(self, verbose=False):
        if verbose: print("INFO: Encoding instructions ...")
        for instr in self.instructions:
            if verbose: print(f"instr: {instr['src']}")
            word = self.genMachineCode(instr)
            instr['word'] = word
        print(f"INFO: {len(self.instructions)} instructions assembled")
        self.isAssembled = True


    # Exports the compiled instructions as program image for Verilog readmemb
    # Options:
    #    filename : path of the output file, prints to stdout if None
    #    comment  : if true, appends user-comments as inline comment
    #    source   : if true, appends the source instruction mnemonics as inline comment
    #    separator: Separator between instruction segments for easy reading
    def export_verilogBin(self, filename=None, comment=True, source=True, separator='_'):
        # Run assembler if not already
        if not self.isAssembled:
            print("WARN: Export invoked before the code is assembled")
            print("INFO: Running assembler ...")
            self.assemble()
        # build output string, always outputs in binary format
        outprog = []
        for instr in self.instructions:
            outxt = self.makeExportBinText(instr, addCmt=comment, addSrc=source, sep=separator)  # build the instruction text
            outprog.append(outxt)   # save the instruction text for writing
        # write the output
        if filename:
            with open(filename, 'w') as fout:
                for txt in outprog: fout.write(txt+'\n')
            print(f"INFO: assembled program written to {filename}")
        else:
            print("---- Assembled Program ----")
            for txt in outprog: print(txt)
            print("---- End of Program ----")



    # ---- Instruction mnemonic functions: when called with parameters, encodes
    #   the instruction into internal representation (self.instructions).
    #
    #   Internal represenstation notes:
    #     - The internal representation is more close to the machine compared
    #       to the mnemonic funtions.
    #     - It is basically a dictionary of instruction-word fields, with their
    #       conceptual values.
    #     - The compilation step takes this internal format then converts it
    #       into machine code based on assembler parameters and any other
    #       directives specified
    #     - The comment field can be used to pass (debugging) information into
    #       the assembled output if needed.


    # generates NOP
    def instNop(self, *, comment=None):
        src = 'NOP'
        instr = {'opcode' : 'nop', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = rx + ry
    def instAddXY(self, rx, ry, *, comment=None):
        # argument validation
        self.validateReg(rx)
        self.validateReg(ry)
        # Ecoding
        src = f'ADD_XY rx={rx}, ry={ry}'
        instr = {
            'opcode' : 'add_xy', 'rs1' : ry, 'rs2' : rx,    # rs2 + rs1
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = rx - ry
    def instSubXY(self, rx, ry, *, comment=None):
        # argument validation
        self.validateReg(rx)
        self.validateReg(ry)
        # Ecoding
        src = f'SUB_XY rx={rx}, ry={ry}'
        instr = {
            'opcode' : 'sub_xy', 'rs1' : ry, 'rs2' : rx,    # rs2 - rs1
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = rx * ry
    def instMultXY(self, rx, ry, *, comment=None):
        # argument validation
        self.validateReg(rx)
        self.validateReg(ry)
        # Ecoding
        src = f'MULT_XY rx={rx}, ry={ry}'
        instr = {
            'opcode' : 'mult_xy', 'rs1' : ry, 'rs2' : rx,    # rs2 * rs1
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = rx + sreg
    def instAddXSREG(self, rx, *, comment=None):
        # argument validation
        self.validateReg(rx)
        # Ecoding
        src = f'ADD_XSREG rx={rx}'
        instr = {
            'opcode' : 'add_xsreg', 'rs2' : rx,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = rx - sreg
    def instSubXSREG(self, rx, *, comment=None):
        # argument validation
        self.validateReg(rx)
        # Ecoding
        src = f'SUB_XSREG rx={rx}'
        instr = {
            'opcode' : 'sub_xsreg', 'rs2' : rx,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = rx * sreg
    def instMultXSREG(self, rx, *, comment=None):
        # argument validation
        self.validateReg(rx)
        # Ecoding
        src = f'MULT_XSREG rx={rx}'
        instr = {
            'opcode' : 'mult_xsreg', 'rs2' : rx,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = relu(ACT-reg)
    def instRelu(self, *, comment=None):
        src = 'RELU'
        instr = {'opcode' : 'relu', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = activation-table(ACT-reg)
    def instActLookup(self, actCode, *, comment=None):
        # argument validation
        self.validateActCode(actCode)
        # Ecoding
        src = f'ACTLOOKUP actCode={actCode}'
        instr = {
            'opcode' : 'actlookup', 'actcode' : actCode,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # disables serial/parallel shifting in vector-shift registers
    def instShiftOff(self, *, comment=None):
        src = 'SHIFTOFF'
        instr = {'opcode' : 'shiftoff', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # enables serial shifting in vector-shift registers
    def instSerialEn(self, *, comment=None):
        src = 'SERIAL_EN'
        instr = {'opcode' : 'serial_en', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # enables parallel shifting in vector-shift registers
    def instParallelEn(self, *, comment=None):
        src = 'PARALLEL_EN'
        instr = {'opcode' : 'parallel_en', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # Sets the selection bit of the block with the given ID
    def instSelectBlk(self, blkID, *, comment=None):
        # argument validation
        self.validateID(blkID, f'invalid blkID: {blkID}')
        # Ecoding
        src = f'SELECTBLK blkID={blkID}'
        instr = {
            'opcode' : 'selectblk', 'id' : blkID,
            'comment' : comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # Sets the selection bit of all blocks
    def instSelectAll(self, *, comment=None):
        src = 'SELECTALL'
        instr = {
            'opcode' : 'selectall',
            'comment' : comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # sreg = oreg
    def instMovO2Sreg(self, *, comment=None):
        src = 'MOV_O2SREG'
        instr = {'opcode' : 'mov_o2sreg', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # sreg = ry
    def instMovY2Sreg(self, ry, *, comment=None):
        # argument validation
        self.validateReg(ry)
        # Ecoding
        src = f'MOV_Y2SREG ry={ry}'
        instr = {
            'opcode' : 'mov_y2sreg', 'rs1' : ry,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # rd = sreg
    def instMovSreg2R(self, rd, *, comment=None):
        # argument validation
        self.validateReg(rd)
        # Ecoding
        src = f'MOV_SREG2R rd={rd}'
        instr = {
            'opcode' : 'mov_sreg2r', 'rs1' : rd,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # rd = oreg
    def instMovOreg2R(self, rd, *, comment=None):
        # argument validation
        self.validateReg(rd)
        # Ecoding
        src = f'MOV_OREG2R rd={rd}'
        instr = {
            'opcode' : 'mov_oreg2r', 'rs1' : rd,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # oreg = ry
    def instMovY2Oreg(self, ry, *, comment=None):
        # argument validation
        self.validateReg(ry)
        # Ecoding
        src = f'MOV_Y2OREG ry={ry}'
        instr = {
            'opcode' : 'mov_y2oreg', 'rs1' : ry,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # ACT-reg = oreg
    def instMovOreg2Act(self, *, comment=None):
        src = 'MOV_OREG2ACT'
        instr = {'opcode' : 'mov_oreg2act', 'comment': comment, 'src' : src}
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # ACT-reg = rx
    def instMovX2Act(self, rx, *, comment=None):
        # argument validation
        self.validateReg(rx)
        # Ecoding
        src = f'MOV_X2ACT rx={rx}'
        instr = {
            'opcode' : 'mov_x2act', 'rs2' : rx,
            'comment': comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # write the given data in the BRAM at the given address
    def instWrite(self, addr, data, *, comment=None):
        # argument validation
        self.validateAddress(addr)
        self.validateData(data)
        # Ecoding
        src = f'WRITE addr={addr}, data={data}'
        instr = {
            'opcode' : 'write0', 'addr' : addr, 'data' : data,
            'comment' : comment, 'src' : src
        }
        self.instructions.append(instr)
        self.isAssembled = False        # un-assembled instruction added
        return instr


    # ---- Multiplexing instructions built on top of built-in instructions

    # A multiplexing function for different MOV variants
    def muxMov(self, rd, rs, *, comment=None):
        if rs == self.REG.O and rd == self.REG.S     : instr = self.instMovO2Sreg(comment=comment)
        elif rs >= 0 and rd == self.REG.S            : instr = self.instMovY2Sreg(rs, comment=comment)
        elif rs == self.REG.S and rd >= 0            : instr = self.instMovSreg2R(rd, comment=comment)
        elif rs == self.REG.O and rd >= 0            : instr = self.instMovOreg2R(rd, comment=comment)
        elif rs >= 0 and rd == self.REG.O            : instr = self.instMovY2Oreg(rs, comment=comment)
        elif rs == self.REG.O and rd == self.REG.ACT : instr = self.instMovOreg2Act(comment=comment)
        elif rs >= 0 and rd == self.REG.ACT          : instr = self.instMovX2Act(rs, comment=comment)
        else: assert 0, f'Register combination not valid: rd={rd}, rs={rs}'
        return instr
        

    # A multiplexing function for different ADD variants
    def muxAdd(self, opl, opr, *, comment=None):
        if opl >= 0 and opr >= 0           : instr = self.instAddXY(opl, opr, comment=comment)
        elif opl >= 0 and opr == self.REG.S: instr = self.instAddXSREG(opl, comment=comment) 
        else: assert 0, f'Register arguments not valid: opl={opl} opr={opr}'
        return instr


    # A multiplexing function for different SUB variants
    def muxSub(self, opl, opr, *, comment=None):
        if opl > 0 and opr > 0            : instr = self.instSubXY(opl, opr, comment=comment)
        elif opl > 0 and opr == self.REG.S: instr = self.instSubXSREG(opl, comment=comment) 
        else: assert 0, f'Register arguments not valid: opl={opl} opr={opr}'
        return instr


    # A multiplexing function for different MULT variants
    def muxMult(self, opl, opr, *, comment=None):
        if opl > 0 and opr > 0            : instr = self.instMultXY(opl, opr, comment=comment)
        elif opl > 0 and opr == self.REG.S: instr = self.instMultXSREG(opl, comment=comment) 
        else: assert 0, f'Register arguments not valid: opl={opl} opr={opr}'
        return instr


    # A multiplexing function for different activation variants
    def muxActivation(self, actCode, *, comment=None):
        if actCode == self.ACTCODE.RELU: instr = self.instRelu(comment=comment)
        else: instr = self.instActLookup(actCode, comment=comment)
        return instr




# Scripting interface. Use it as follows,
#   from picaso_assembler import *
#
#   vvblock_as.setupParams(...)
#
#   add(rd, rs1, rs2)
#   sub(rd, rs1, rs2)
#     .
#     .
#     .
#   vvblock_as.assemble(flags...)
#   vvblock_as.export_verilogBin(filename, flags...)


# Assembler object
vvblock_as = VVBlockAsm()

REG = vvblock_as.REG
ACTCODE = vvblock_as.ACTCODE

# simpler interface to instruction mnemonic functions for scripting
nop = vvblock_as.instNop
shiftOff = vvblock_as.instShiftOff
serialEn = vvblock_as.instSerialEn
parallelEn = vvblock_as.instParallelEn
selectBlk = vvblock_as.instSelectBlk
selectAll = vvblock_as.instSelectAll
write = vvblock_as.instWrite

# following multiplexer instruction multiplexes all these instructions
#   instMovO2Sreg
#   instMovY2Sreg
#   instMovSreg2R
#   instMovOreg2R
#   instMovY2Oreg
#   instMovOreg2Act
#   instMovX2Act
mov = vvblock_as.muxMov

# Multiplexer for following instructions
#   instAddXY
#   instAddXSREG
add = vvblock_as.muxAdd

# Multiplexer for following instructions
#   instSubXY
#   instSubXSREG
sub = vvblock_as.muxSub

# Multiplexer for following instructions
#   instMultXY
#   instMultXSREG
mult = vvblock_as.muxMult


# Multiplexer for following instructions
#   instRelu
#   instActLookup
activation = vvblock_as.muxActivation
