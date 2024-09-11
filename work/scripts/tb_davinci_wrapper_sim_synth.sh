# Author: MD Arafat Kabir
# NOTE: This script is supposed to be run under work/sim directory

topdir=../..
synthdir=../synth
impldir=../impl
scriptdir=../scripts

# File paths
simLogFile=xsim_simulation.log
topname=tb_davinci_wrapper


# parse arugments and select the synthesized netlist
usageExit() {
  echo "Script to run functional simulation on davinci_wrapper"
  echo "Usage: $(basename $0)  -m <synth|routed>  -p <program-file>  -e <expect-file>"
  exit 1
}

while getopts 'm:p:e:' opt; do
  case "$opt" in
    p) progfile=$OPTARG;;
    e) expfile=$OPTARG;;
    m) mode=$OPTARG;;
    ?) usageExit;;
  esac
done

if [ -z "$progfile" ] || [ -z "$expfile" ] || [ -z "$mode" ]; then
  usageExit
  exit 1
fi

if [ "$mode" = "synth" ]; then
  synth_netlist=$synthdir/davinci_wrapper_synth_netlist_func.v
elif [ "$mode" = "routed" ]; then
  synth_netlist=$impldir/davinci_wrapper_routed_netlist_func.v
else
  usageExit
fi

echo "AK-INFO: Using $synth_netlist for simulation"



# Command arguments
vfiles="$topdir/tb/xil_ip/fifo_generator_0/sim/fifo_generator_0.v \
        $synth_netlist"
svfiles="$topdir/tb/tb_davinci_wrapper_synth.sv"
simscript="$scriptdir/xsim_cfg.tcl"         # simulation script for xsim

flags_xvlog="-d PROG_FILE=$progfile  -d EXP_FILE=$expfile"


echo -e "\n\nAK-INFO: Running xvlog on Verilog files ..."
xvlog  $vfiles  $flags_xvlog \
      -i $topdir/lib  \
      -i $topdir/tb   \
      -i $topdir/DA-VinCi \
      -i $topdir/vvengine \
      || exit


echo -e "\n\nAK-INFO: Running xvlog on SystemVerilog files ..."
xvlog -sv $svfiles $flags_xvlog \
      -i $topdir/lib  \
      -i $topdir/tb   \
      -i $topdir/DA-VinCi \
      -i $topdir/vvengine \
      || exit


echo -e "\n\nAK-INFO: Running xelab ..."
xelab              \
  -debug typical   \
  -top $topname    \
  -L fifo_generator_v13_2_7 \
  -L unisims_ver glbl \
  -snapshot $topname.snap \
  || exit


echo -e "\n\nAK-INFO: Running xsim ..."
echo -e "AK-INFO: Simulation log will be saved in $simLogFile"
xsim $topname.snap --tclbatch $simscript > $simLogFile || exit
tail $simLogFile    # show the last few lines
