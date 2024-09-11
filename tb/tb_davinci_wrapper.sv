`timescale 1ns/100ps
`include "ak_macros.v"


module tb_davinci_wrapper; 

  `include "davinci_interface.svh"
  `include "vecshift_reg.svh"
  `include "vvcontroller.svh"
  `include "picaso_instruction_decoder.inc.v"


  localparam PERIOD_PROC = 10,              // processor-side clock
             // PERIOD_IMG  = PERIOD_PROC/2,   // davinci-side clock
             PERIOD_IMG  = PERIOD_PROC,   // davinci-side clock
             SIG_DELAY = 1;     // signal change delay after posedge

  localparam  DEBUG = 0,
              DATAOUT_WIDTH = 16,   // data-output from davinci-interface/vvengine-register
              DATA_ATTRIB_WIDTH = VECREG_STATUS_WIDTH,
              GEMVARR_INSTR_WIDTH  = PICASO_INSTR_WORD_WIDTH,
              GEMVARR_BLK_ROW_CNT  = 16,  // No. of PiCaSO rows in the entire array
              GEMVARR_BLK_COL_CNT  =  4,  // No. of PiCaSO columns in the entire array
              GEMVARR_TILE_ROW_CNT =  4,  // No. of PiCaSO rows in a tile
              GEMVARR_TILE_COL_CNT =  2;  // No. of PiCaSO columns in a tile

  localparam SUBMODULE_CODE_WIDTH = DAVINCI_SUBMODULE_CODE_WIDTH;
  localparam [SUBMODULE_CODE_WIDTH-1:0]
             GEMVARR_SELECT = DAVINCI_SUBMODULE_GEMVARR_SELECT,
             VVENG_SELECT = DAVINCI_SUBMODULE_VVENG_SELECT;


  var  clk_proc = '0;
  var  clk_dav  = '0;


  // -- davinci_interface IO
  wire [DAVINCI_INSTR_WIDTH-1:0]  davInt_instruction;
  wire                            davInt_instructionValid;
  wire                            davInt_instructionNext;
  wire   [DATAOUT_WIDTH-1:0]      davInt_dataout;
  wire   [DATA_ATTRIB_WIDTH-1:0]  davInt_dataAttrib;
  wire                            davInt_dataoutValid;
  wire                            davInt_eovInterrupt;
  reg                             davInt_clearEOV = 0;   // will be used by test tasks
  
  wire [GEMVARR_INSTR_WIDTH-1:0]     davInt_gemvarr_instruction;
  wire                               davInt_gemvarr_inputValid;
  wire [VVENG_INSTRUCTION_WIDTH-1:0] davInt_shreg_instruction;
  wire                               davInt_shreg_inputValid;

  reg  [DATAOUT_WIDTH-1:0]        davInt_shreg_parallelOut = 0;
  reg  [DATA_ATTRIB_WIDTH-1:0]    davInt_shreg_statusOut = 0;


  (* keep_hierarchy = "yes" *)
  davinci_wrapper #(
      .DEBUG(DEBUG),
      .BLK_ROW_CNT(GEMVARR_BLK_ROW_CNT),
      .BLK_COL_CNT(GEMVARR_BLK_COL_CNT),
      .TILE_ROW_CNT(GEMVARR_TILE_ROW_CNT),
      .TILE_COL_CNT(GEMVARR_TILE_COL_CNT),
      .DATAOUT_WIDTH(DATAOUT_WIDTH))
    davinciTop (
			.clk(clk_dav),
			// FIFO-in interface
			.instruction(davInt_instruction),
			.instructionValid(davInt_instructionValid),
			.instructionNext(davInt_instructionNext),
			// FIFO-out interface
			.dataout(davInt_dataout),
      .dataAttrib(davInt_dataAttrib),
			.dataoutValid(davInt_dataoutValid),
			// status signals
			.eovInterrupt(davInt_eovInterrupt),
      .clearEOV(davInt_clearEOV),

      // // interface to submodule: GEMV array 
      // .gemvarr_instruction(davInt_gemvarr_instruction),
      // .gemvarr_inputValid(davInt_gemvarr_inputValid),

      // // interface to submodule: vector shift register column
      // .shreg_instruction(davInt_shreg_instruction),
      // .shreg_inputValid(davInt_shreg_inputValid),
      // .shreg_parallelOut(davInt_shreg_parallelOut),    // inputs connected to parallel output from the shift register column
      // .shreg_statusOut(davInt_shreg_statusOut),      // inputs connected output status bits to the shift register column

			// Debug probes
			.dbg_clk_enable(1'b1)
    );



  // Instantiate the FIFO-in
  localparam FIFOIN_DWIDTH = 32;

  logic                      fifoin_srst = 0;
  logic [FIFOIN_DWIDTH-1:0]  fifoin_din = 0;
  logic                      fifoin_wr_en = 0;
  wire                       fifoin_rd_en;
  wire [FIFOIN_DWIDTH-1:0]   fifoin_dout;
  wire                       fifoin_full;
  wire                       fifoin_wr_ack;
  wire                       fifoin_overflow;
  wire                       fifoin_empty;
  wire                       fifoin_valid;
  wire                       fifoin_underflow;
  wire                       fifoin_wr_rst_busy;
  wire                       fifoin_rd_rst_busy;


  fifo_generator_0 fifoIn (
    .srst(fifoin_srst),                // input wire srst
    .wr_clk(clk_proc),                 // input wire wr_clk, write from processor
    .rd_clk(clk_dav),                  // input wire rd_clk, read from davinci
    .din(fifoin_din),                  // input wire [31 : 0] din
    .wr_en(fifoin_wr_en),              // input wire wr_en
    .rd_en(fifoin_rd_en),              // input wire rd_en
    .dout(fifoin_dout),                // output wire [31 : 0] dout
    .full(fifoin_full),                // output wire full
    .wr_ack(fifoin_wr_ack),            // output wire wr_ack
    .overflow(fifoin_overflow),        // output wire overflow
    .empty(fifoin_empty),              // output wire empty
    .valid(fifoin_valid),              // output wire valid
    .underflow(fifoin_underflow),      // output wire underflow
    .wr_rst_busy(fifoin_wr_rst_busy),  // output wire wr_rst_busy
    .rd_rst_busy(fifoin_rd_rst_busy)   // output wire rd_rst_busy
  );


  // Instantiate the FIFO-in
  localparam FIFOUT_DWIDTH = 32;      // data and attributes

  reg                      fifoout_srst = 0;
  wire [FIFOUT_DWIDTH-1:0] fifoout_din;
  reg                      fifoout_rd_en = 0;
  wire                     fifoout_wr_en;
  wire [FIFOUT_DWIDTH-1:0] fifoout_dout;
  wire                     fifoout_full;
  wire                     fifoout_wr_ack;
  wire                     fifoout_overflow;
  wire                     fifoout_empty;
  wire                     fifoout_valid;
  wire                     fifoout_underflow;
  wire                     fifoout_wr_rst_busy;
  wire                     fifoout_rd_rst_busy;


  fifo_generator_0 fifoOut (
    .srst(fifoout_srst),                // input wire srst
    .wr_clk(clk_dav),                   // input wire wr_clk, write from davinci
    .rd_clk(clk_proc),                  // input wire rd_clk, read from processor
    .din(fifoout_din),                  // input wire [31 : 0] din
    .wr_en(fifoout_wr_en),              // input wire wr_en
    .rd_en(fifoout_rd_en),              // input wire rd_en
    .dout(fifoout_dout),                // output wire [31 : 0] dout
    .full(fifoout_full),                // output wire full
    .wr_ack(fifoout_wr_ack),            // output wire wr_ack
    .overflow(fifoout_overflow),        // output wire overflow
    .empty(fifoout_empty),              // output wire empty
    .valid(fifoout_valid),              // output wire valid
    .underflow(fifoout_underflow),      // output wire underflow
    .wr_rst_busy(fifoout_wr_rst_busy),  // output wire wr_rst_busy
    .rd_rst_busy(fifoout_rd_rst_busy)   // output wire rd_rst_busy
  );


  // -- local interconnect
  // davinci-interface and FIFO-in connections
  assign davInt_instruction = fifoin_dout,
         davInt_instructionValid = fifoin_valid,
         fifoin_rd_en = davInt_instructionNext;

  // davinci-interface and FIFO-out connections
  localparam BIT_ISDATA = 24,   // 24th bit is the isData bit
             BIT_ISLAST = 25;   // next bit is the isLast bit
  wire [FIFOUT_DWIDTH-1:0] dataOutPacket;
  assign dataOutPacket[0 +: DATAOUT_WIDTH] = davInt_dataout;   // lower 16-bits holds the data
  assign dataOutPacket[24 +: 8] = {'0, davInt_dataAttrib};     // upper 8-bits holds the data attributes
  assign dataOutPacket[23:DATAOUT_WIDTH] = '0;                 // other bits are 0s

  assign fifoout_din = dataOutPacket,
         fifoout_wr_en = davInt_dataoutValid;

         
  

`ifndef XIL_ELAB      // set XIL_ELAB to remove following code in elaboration

  localparam TEST_INSTR_SIZE = 6096,   // size of the intstruction buffer
             FIFOUT_BUF_SIZE = 1024;   // size of the FIFO-out read buffer

  logic [DAVINCI_INSTR_WIDTH-1:0] test_instr_arr[TEST_INSTR_SIZE];
  logic [FIFOUT_DWIDTH-1:0]       fifout_buffer[FIFOUT_BUF_SIZE],     // FIFO-output will be stored here
                                  expOut_buffer[FIFOUT_BUF_SIZE];    // expected output will be loaded here

  // Remove scope prefix
  localparam SEG0_WIDTH = PICASO_INSTR_SEG0_WIDTH,
             SEG1_WIDTH = PICASO_INSTR_SEG1_WIDTH,
             SEG2_WIDTH = PICASO_INSTR_SEG2_WIDTH;


  // clock generators
  always #(PERIOD_IMG/2)  clk_dav = ~clk_dav;
  always #(PERIOD_PROC/2) clk_proc = ~clk_proc;


  // Hardware counter
  int hwCounter = 0;
  always@(posedge clk_dav) begin
    hwCounter <= hwCounter+1;
  end


  // Writes input to FIFO-in, consumes at least 2 cycles
  task automatic write_fifoIn;
    input logic [FIFOIN_DWIDTH-1:0] data;
    `ifdef FAST_SIM  
      $write("."); // short message for faster simulation
    `else
      $display("INFO: Writing %x to FIFO-in (%0t)", data, $time); // elaborate message for debugging
    `endif
    // check and wait until fifo ready for input
    while(fifoin_full) begin
      $display("INFO: FIFO-in full, waiting ... (%0t)", $time);
      @(posedge clk_proc); #SIG_DELAY;
    end
    // write the input
    fifoin_din = data;
    fifoin_wr_en = '1;
    @(posedge clk_proc); #SIG_DELAY;
    fifoin_din = '0;
    fifoin_wr_en = '0;
    @(posedge clk_proc); #SIG_DELAY;
  endtask


  // Reads the current output from FIFO-out, consumes at least 2 cycles
  task automatic read_fifoOut;
    output logic [FIFOUT_DWIDTH-1:0] data;
    $display("INFO: Reading from FIFO-out (%0t)", $time);
    // check and wait until fifo ready for readout
    while(!fifoout_valid) begin
      $display("INFO: FIFO-out data not valid, waiting ... (%0t)", $time);
      @(posedge clk_proc); #SIG_DELAY;
    end
    // read the fifo output
    data = fifoout_dout;
    fifoout_rd_en = '1;   // consume current dout
    @(posedge clk_proc); #SIG_DELAY;
    fifoout_rd_en = '0;
    @(posedge clk_proc); #SIG_DELAY;
    $display("INFO: FIFO-out read data %x (%0t)", data, $time);
  endtask


  // top-level variables for keeping track of simulation states
  int err_count = 0;

  // Emulates the front-end processor
  task automatic run_processor;
    input int instr_cnt;   // how many instructions to push
    // internal variables
    int dataCount;
    logic [FIFOUT_DWIDTH-1:0] data;
    $display("INFO: Starting processor run task at %0t", $time);

    // follow FIFO interface protocol and push the instructions
    $display("INFO: Processor pushing instructions into FIFO-in (%0t)", $time);
    for(int i=0; i<instr_cnt; ++i) begin
      @(posedge clk_proc); #SIG_DELAY;
      write_fifoIn(test_instr_arr[i]);
    end
    `ifdef FAST_SIM
      $display("");   // add a new lines after progress dots in FAST_SIM mode
    `endif
    $display("INFO: Processor finished pushing instructions (%0t)", $time);

    // wait for end-of-vector interrupt
    @(posedge clk_proc); #SIG_DELAY;
    while(!davInt_eovInterrupt) begin
      $display("INFO: Processor waiting for end-of-vector interrupt (%0t)", $time);
      repeat(10) @(posedge clk_proc); #SIG_DELAY;  // wait for multiple cycles
    end

    // end-of-vector interrupt received; clear interrupt before reading FIFO-out
    $display("INFO: Processor received end-of-vector interrupt(%0t)", $time);
    @(posedge clk_proc); #SIG_DELAY;
    davInt_clearEOV = '1;
    @(posedge clk_proc); #SIG_DELAY;
    davInt_clearEOV = '0;

    // pull out FIFO-out data (FIFO-out may not yet be ready to be read)
    while(!fifoout_valid) @(posedge clk_proc);    // wait for fifoout to be valid
    dataCount = 0;
    $display("");   // log separator
    while(fifoout_valid) begin
      @(posedge clk_proc); #SIG_DELAY;
      read_fifoOut(data);
      fifout_buffer[dataCount++] = data;    // save into buffer
      if(dataCount == FIFOUT_BUF_SIZE) begin
        $display("INFO: FIFO-out has more data than read buffer size, skipping remaining (%0t)", $time);
        break;
      end
    end
    $display("");   // log separator

    // print the FIFO-out data read
    $display("INFO: Finished reading FIFO-out, %0d data read (%0t)", dataCount, $time);
    for(int i=0; i<dataCount; ++i) begin
      printFifoOutData(i, fifout_buffer[i], "  ");
    end

    // test the output
    $display("INFO: Testing FIFO-out data (%0t)", $time);
    for(int i=0; i<dataCount; ++i) begin
      if(fifout_buffer[i] !== expOut_buffer[i]) begin
        ++err_count;
        $display("EROR: Output mismatch at %0d; exp: %0b, got: %0b", i, expOut_buffer[i], fifout_buffer[i]);
      end
    end

    $display("INFO: Exiting run_processor task (%0t)", $time);
  endtask


  // This task computes the latency between specified events
  int recStart = 0, recEnd = 0;
  task automatic recordLatency;
    logic [31:0] startInst = 32'h52000000;   // VV_DISABLE_SHIFT
    // logic [31:0] startInst = 32'h54000000;   // VV_SERIAL_EN
    // logic [31:0] startInst = 32'h20000000;
    logic [31:0] endInst   = 32'h56000000;   // VV_PARALLEL_EN
    for(int i=0; i<100000; ++i) begin
      @(negedge clk_dav); #SIG_DELAY;
      if(davInt_instruction == startInst) begin
        //$display("RECD: davInt_instruction: %x, hwCounter: %d, (%0t)", davInt_instruction, hwCounter, $time);
        if(recStart != 0) $display("WARN: Duplicate startInst(%x) at hwCounter: %0d, last seen hwCounter: %0d", startInst, hwCounter, recStart);
        else recStart = hwCounter;
      end else if(davInt_instruction == endInst) begin
        //$display("RECD: davInt_instruction: %x, hwCounter: %d, (%0t)", davInt_instruction, hwCounter, $time);
        if(recEnd != 0) $display("WARN: Duplicate endInst(%x) at hwCounter: %0d, last seen hwCounter: %0d", endInst, hwCounter, recEnd);
        else recEnd = hwCounter;
      end
      // loop-break condition
      if(recStart != 0 && recEnd != 0) break;
    end
  endtask


  // prints the FIFO-out data in an easy-to-read format
  task automatic printFifoOutData;
    input int index;
    input logic [FIFOUT_DWIDTH-1:0] value;
    input string indent;
    // internal variables
    logic [DATAOUT_WIDTH-1:0]               dataBits;
    logic [FIFOUT_DWIDTH-DATAOUT_WIDTH-1:0] attrBits;

    // separate the data and attribute bits
    dataBits = value[0 +: DATAOUT_WIDTH];    // data output of davinci data are put in lower bits
    attrBits = value[FIFOUT_DWIDTH-1 : DATAOUT_WIDTH]; // upper bits may contain some data attributes
    // print the formatted data output
    $display("%s%d: %b_%b (%d)", indent, index, attrBits, dataBits, $signed(dataBits));
  endtask


  initial begin: Main
    int instr_cnt, data_cnt;
    logic [SEG0_WIDTH-1:0] seg0;
    logic [SEG1_WIDTH-1:0] seg1;
    logic [SEG2_WIDTH-1:0] seg2;
    logic [DAVINCI_SUBMODULE_CODE_WIDTH-1:0] subm;

    `ifndef FAST_SIM  // don't record waveform for faster simulation
      $dumpfile("tb_davinci_wrapper.vcd");
      $dumpvars;
    `endif
    $timeformat(-9, 1, " ns", 10);      // 1ns, 3 decimal point (1ps), ns suffix, 10 char wide
    $display("INFO: Running tb_davinci_wrapper");
    
    // initialize variables
    err_count = 0;

    dumpGemvArrRF("gemvImage_start.data");
    // dumpVecArr("vecImage_start.data");
    loadProgram(`STRINGIFY(`PROG_FILE), instr_cnt);   // `PROG_FILE macro needs to be defined in the commandline of the simulator
    loadExpOut(`STRINGIFY(`EXP_FILE), data_cnt);      // `EXP_FILE macro needs to be defined in the commandline of the simulator
    // print the program for debugging
    `ifndef FAST_SIM  // dont' print the instructions for faster simulation
      $display("INFO: test program loaded");
      for(int i=0; test_instr_arr[i] != '1; ++i) begin
        // separate the instruction segments
        seg0 = test_instr_arr[i][0 +: SEG0_WIDTH];
        seg1 = test_instr_arr[i][SEG0_WIDTH +: SEG1_WIDTH];
        seg2 = test_instr_arr[i][SEG0_WIDTH+SEG1_WIDTH +: SEG2_WIDTH];
        subm = test_instr_arr[i][DAVINCI_INSTR_WIDTH-1 -: DAVINCI_SUBMODULE_CODE_WIDTH];
        $display("  test_instr_arr[%2d]: %x %x %x %x (%x)", i, subm, seg2, seg1, seg0, test_instr_arr[i]);
      end
    `endif

    // Run the program
    #(10*PERIOD_PROC);
    fork
      run_processor(instr_cnt);
      recordLatency;
    join
    // #(instr_cnt*4*PERIOD_IMG);    // Wait for davinci to execute the instructions

    // Finish simulation
    #(10*PERIOD_PROC);
    if(err_count == 0) $display("INFO: All tests passed!");
    else $display("EROR: %0d tests failed", err_count);

    // Print recorded times
    $display("INFO: recStart: %0d, recEnd: %0d, interval: %0d", recStart, recEnd, recEnd-recStart);

    // Dump post-simulation BRAM images
    dumpGemvArrRF("gemvImage_end.data");
    // dumpVecArr("vecImage_end.data");
    
    $display("INFO: Ending simulation");
    $display("PROG: Finished!");
    $finish;
  end


  // Given a filename, loads the instructions into instruction array
  task automatic loadProgram;
    input string filepath;
    output int _instr_cnt;

    logic [DAVINCI_INSTR_WIDTH-1:0] _word;

    // load the program
    $display("INFO: Loading instructions from %s", filepath);
    $readmemb(filepath, test_instr_arr);

    // count and show all valid instructions
    _instr_cnt = 0;
    for(int i = 0; i < TEST_INSTR_SIZE; ++i) begin
      _word = test_instr_arr[i];
      if(_word[0] !== 1'bx) begin
        _instr_cnt += 1;
        `ifndef FAST_SIM  // don't print the instructions for fast simulation
          $display("  instr[%0d]: %b", i, _word);
        `endif
      end else begin
        break;
      end
    end
    $display("INFO: %0d instructions loaded", _instr_cnt);
  endtask


  // Given a filename, loads the instructions into instruction array
  task automatic loadExpOut;
    input string filepath;
    output int _data_cnt;

    logic [FIFOUT_DWIDTH-1:0] _word;

    // load the program
    $display("INFO: Loading expected output from %s", filepath);
    $readmemb(filepath, expOut_buffer);

    // count and show all valid data
    _data_cnt = 0;
    for(int i = 0; i < FIFOUT_BUF_SIZE; ++i) begin
      _word = expOut_buffer[i];
      if(_word[0] !== 1'bx) begin
        _data_cnt += 1;
        $display("  expOut_buffer[%2d]: %b", i, _word);
      end else begin
        break;
      end
    end
    $display("INFO: %0d data loaded", _data_cnt);
  endtask


  // -- Dumps the registerfile of picaso array blocks as an array image
  // AK-NOTE: Change the following parameters when you change the dimensions of
  //          the GEMV array in DA-VinCi.
  localparam  RF_WIDTH = 16,
              RF_DEPTH = 1024,
              ARR_ROW_CNT = GEMVARR_BLK_ROW_CNT,
              ARR_COL_CNT = GEMVARR_BLK_COL_CNT;
              
  logic [RF_WIDTH-1:0]        gemvRF_image[ARR_ROW_CNT][ARR_COL_CNT][RF_DEPTH-1:0];    // image data will be loaded here from the file
  logic [DATAOUT_WIDTH-1:0]   vecReg_image[ARR_ROW_CNT];     // to store contents of the registers
  logic [1:0]                 vecConf_image[ARR_ROW_CNT];    // to store the internal configuration bits (shiftParallelEn, shiftSerialEn)
  bit move_gemvRF2img=0;    // trigger for copying gemv-registerfile to image array
  bit move_vvReg2img=0;     // trigger for copying vecshift-reg to image arrays


  task automatic dumpGemvArrRF;
    input string filepath;
    int fd;

    // copy registerfile contents into image array
    $display("INFO: Preparing GEMV registerfile array image (%0t) ...", $time);
    move_gemvRF2img = 0; move_gemvRF2img = 1;   // generate posedge
    #0;   // zero-delay event bubble to finish copying
    move_gemvRF2img = 0;

    // write image array into file
    $display("INFO: Writing GEMV array image into %s ...", filepath);
    fd = $fopen(filepath, "w");
    // write block-by-block
    for(int row=0; row < ARR_ROW_CNT; ++row) begin
      for(int col=0; col < ARR_COL_CNT; ++col) begin
        $fdisplay(fd, "// row:%0d, col:%0d", row, col);
        for(int addr=0; addr<RF_DEPTH; ++addr) begin
          //$fdisplay(fd, "%4d:%b", addr, gemvRF_image[row][col][addr]);
          $fdisplay(fd, "%b", gemvRF_image[row][col][addr]);
        end
        $fdisplay(fd, "");
      end
    end
    $fclose(fd);
    $display("INFO: Done GEMV writing array image (%0t)", $time);
  endtask


  task automatic dumpVecArr;
    input string filepath;
    int fd;

    // copy register contents into image array
    $display("INFO: Preparing vecshift-reg registerfile array image (%0t) ...", $time);
    move_vvReg2img = 0; move_vvReg2img = 1;   // generate posedge
    #0;   // zero-delay event bubble to finish copying
    move_vvReg2img = 0;

    // write vecshift-reg image array into file
    $display("INFO: Writing vecshift-reg array image into %s ...", filepath);
    fd = $fopen(filepath, "w");
    for(int row=0; row < ARR_ROW_CNT; ++row) begin
      $fdisplay(fd, "%b_%b (%0d)", vecConf_image[row], vecReg_image[row], vecReg_image[row]);
    end
    $fclose(fd);
    $display("INFO: Done writing vecshift-reg array image (%0t)", $time);
  endtask


  // AK-NOTE: Following processes are triggered by tasks to
  // copy data between the registerfiles and the export image (gemvRF_image).
  // The generate block is needed because hierarchical reference
  // (block_col[col]) requires a compile-time constant (genvar/parameter/localparam/literal).
  localparam GEMVARR_START_ROW_ID = 0,
             GEMVARR_START_COL_ID = 0,
             ROW_ID_MAX = GEMVARR_START_ROW_ID + ARR_ROW_CNT - 1,
             COL_ID_MAX = GEMVARR_START_COL_ID + ARR_COL_CNT - 1;
  localparam VEC_TILE_HEIGHT = GEMVARR_TILE_ROW_CNT;

  generate
    genvar g_row, g_col;
    // Handles GEMV blockram contents
    for(g_row = GEMVARR_START_ROW_ID; g_row <= ROW_ID_MAX; g_row = g_row+1)  begin: copy_blockrow
      for(g_col = GEMVARR_START_COL_ID; g_col <= COL_ID_MAX; g_col = g_col+1)  begin: copy_blockcol

        // process to copy registerfiles into rf_image
        always@(posedge move_gemvRF2img) begin: rf2img_always
          //$display("rf2img: (%3d,%3d)", g_row, g_col);
          for(int addr=0; addr < RF_DEPTH; ++addr) begin
            gemvRF_image[g_row][g_col][addr] = davinciTop.gemvArr.tile_row[g_row/GEMVARR_TILE_ROW_CNT].tile_col[g_col/GEMVARR_TILE_COL_CNT].tile_inst.picaso_arr2D.block_row[g_row].block_col[g_col].block.regfile.ram[addr]; // AK-NOTE: the naming and indexing scheme was looked up from vivado RTL elaborated netlist
            // gemvRF_image[g_row][g_col][addr] = davinciTop.gemvArr.tile_row[g_row/GEMVARR_TILE_ROW_CNT].tile_col[g_col/GEMVARR_TILE_COL_CNT].tile_inst.picaso_arr2D.block_row[g_row].block_col[g_col].block.regfile.ram[addr];
          end
        end

      end
    end
    // Handles vecshift-reg contents
    for(g_row=0; g_row<ARR_ROW_CNT; ++g_row)  begin: copy_vectile

      // process to copy registers into image array
      always@(posedge move_vvReg2img) begin: vec2img_always
        //$display("vec2img: row: %3d", g_row);
        // vecReg_image[g_row] = davinciTop.vecArr.tile[g_row/VEC_TILE_HEIGHT].vectile.shreg_array.reginst[g_row%VEC_TILE_HEIGHT].vecreg.shreg.data_reg;     // path collected from vivado RTL elaboration
        // vecConf_image[g_row][0] = davinciTop.vecArr.tile[g_row/VEC_TILE_HEIGHT].vectile.shreg_array.reginst[g_row%VEC_TILE_HEIGHT].vecreg.shiftSerialEn;
        // vecConf_image[g_row][1] = davinciTop.vecArr.tile[g_row/VEC_TILE_HEIGHT].vectile.shreg_array.reginst[g_row%VEC_TILE_HEIGHT].vecreg.shiftParallelEn;
      end

    end
  endgenerate



`endif // XIL_ELAB


endmodule

