// defines the parameters of vvtile module

// Structure of all control signals
typedef struct packed {
  logic                  extDataSave;
  logic  [RF_WIDTH-1:0]  extDataIn; 

  logic    intRegSave;
  logic    intRegSel;

  logic  [RF_ADDR_WIDTH-1:0] addrA;
  logic  [RF_ADDR_WIDTH-1:0] addrB;

  logic  [ACTCODE_WIDTH-1:0] actCode;
  logic                      actlookupEn;
  logic                      actregInsel;
  logic                      actregEn;

  logic  [ID_WIDTH-1:0]      selID;
  logic                      selAll;
  logic                      selEn;
  logic                      selOp;

  logic [ALUOP_WIDTH-1:0]    aluOp;
  logic                      oregEn;

  logic [VECREG_CONFIG_WIDTH-1:0] vecregConf;
  logic                           vecregLoadSel;
  logic                           vecregLoadEn;
} ctrlsigs_t;
