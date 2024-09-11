// Defines the parameters and datatypes for the davinci_interface module.
// This is not supposed to be reusable. This should be implemented as a package
// in the future. Include this file within a module.

localparam DAVINCI_INSTR_WIDTH = 32;

// AK-NOTE: instruction format is defined in the _davinciIntf_fetchDispatch module

// Submodule selection codes
localparam DAVINCI_SUBMODULE_CODE_WIDTH = 2;
localparam [DAVINCI_SUBMODULE_CODE_WIDTH-1:0] 
  DAVINCI_SUBMODULE_GEMVARR_SELECT  = 0,     // submodule selection code
  DAVINCI_SUBMODULE_VVENG_SELECT = 1;        // submodule selection code
