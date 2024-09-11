# Author: MD Arafat Kabir
# NOTE: This script is supposed to be run under work/sim directory

topdir=../..
scriptdir=../scripts


# Script parameter parsing
printUsage() {
  echo "Usage: $(basename $0) -p <program-file> -e <expect-file> [-f] [-n]"
  echo "Options:"
  echo "  -f   Enable fast simulation. This option"
  echo "       disables vcd generation"
  echo "  -n   Skip elaboration, simply run the program."

}

extflags=""   # optional flags will be accumulated in extflags
skipElab=0
while getopts 'p:e:fn' opt; do
  case "$opt" in
    p) progfile=$OPTARG;;
    e) expfile=$OPTARG;;
    f) extflags="$extflags -d FAST_SIM";;  # for fast simulation
    n) skipElab=1;;  # will skip elaboration of the design
    ?) printUsage
       exit 1;;
  esac
done

if [ -z "$progfile" ] || [ -z "$expfile" ]; then
  printUsage
  exit 1
fi


# File paths
simLogFile=xsim_simulation.log
topname=tb_davinci_wrapper
alu_sources="$topdir/lib/alu_serial_ff.v  $topdir/lib/alu_serial_unit.v  $topdir/lib/boothR2_serial_alu.v"
datanet_sources="$topdir/lib/datanet_node.v  $topdir/lib/datanet_txMux.v"
picasoff_sources="$topdir/lib/picaso_ff.v  \
                  $topdir/lib/bram_wrfirst_ff.v  \
                  $topdir/lib/opmux_ff.v  \
                  $alu_sources \
                  $datanet_sources"
vvtilearr_sources="$topdir/vvengine/vvblock.sv  \
                   $topdir/vvengine/vvalu.sv \
                   $topdir/vvengine/vecshift_reg.sv \
                   $topdir/vvengine/shiftReg.sv \
                   $topdir/vvengine/vvcontroller.sv  \
                   $topdir/vvengine/vvctrl_blkSignalGen.sv \
                   $topdir/vvengine/vvtile.sv  \
                   $topdir/vvengine/vvtile_array.sv"
picasoCtrl_sources="$topdir/lib/picaso_controller.v \
                    $topdir/lib/srFlop.v \
                    $topdir/lib/picaso_fsm_vars.v \
                    $topdir/lib/picaso_singlecycle_driver.v \
                    $topdir/lib/picaso_multicycle_driver.v \
                    $topdir/lib/picaso_instruction_fsm.v \
                    $topdir/lib/picaso_algorithm_fsm.v \
                    $topdir/lib/loop_counter.v \
                    $topdir/lib/up_counter.v \
                    $topdir/lib/picaso_algorithm_decoder.v \
                    $topdir/lib/picaso_instruction_decoder.v \
                    $topdir/lib/transition_aluop.v \
                    $topdir/lib/transition_updatepp.v \
                    $topdir/lib/transition_stream.v \
                    $topdir/lib/transition_accumrow.v"
gemvArr_sources="$topdir/DA-VinCi/gemv_picaso_array.sv \
                 $topdir/DA-VinCi/gemvtile.sv \
                 $topdir/DA-VinCi/gemvtile_array.sv"

# Command arguments
vfiles="$topdir/tb/xil_ip/fifo_generator_0/sim/fifo_generator_0.v \
        $picasoCtrl_sources \
        $picasoff_sources"
svfiles="$topdir/tb/tb_davinci_wrapper.sv \
         $topdir/DA-VinCi/davinci_wrapper.sv \
         $topdir/DA-VinCi/davinci_interface.sv \
         $vvtilearr_sources \
         $gemvArr_sources "
simscript="$scriptdir/xsim_cfg.tcl"         # simulation script for xsim

flags_xvlog="-d PROG_FILE=$progfile  -d EXP_FILE=$expfile  $extflags"


# Elaborate the design
if [ $skipElab -eq 0 ]; then
  echo -e "\n\nAK-INFO: Running xvlog on Verilog files ..."
  xvlog  $vfiles  $flags_xvlog \
        -i $topdir/lib  \
        -i $topdir/tb   \
        -i $topdir/DA-VinCi \
        -i $topdir/vvengine \
        || exit


  echo -e "\n\nAK-INFO: Running xvlog on SystemVerilog files ..."
  xvlog -sv $svfiles $flags_xvlog \
         -i $topdir/lib   \
         -i $topdir/tb    \
         -i $topdir/DA-VinCi \
         -i $topdir/vvengine \
         || exit


  echo -e "\n\nAK-INFO: Running xelab ..."
  xelab              \
    -debug typical   \
    -top $topname    \
    -L fifo_generator_v13_2_7 \
    -snapshot $topname.snap \
    || exit
fi


# Run simulation
echo -e "\n\nAK-INFO: Running xsim ..."
echo -e "AK-INFO: Simulation log will be saved in $simLogFile"
xsim $topname.snap --tclbatch $simscript > $simLogFile || exit
tail -n20 $simLogFile    # show the last few lines
