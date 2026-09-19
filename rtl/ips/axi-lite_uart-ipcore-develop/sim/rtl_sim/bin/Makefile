all:	sim
SHELL = /bin/sh
MS="-s"

##########################################################################
#
# DUT Sources
#
##########################################################################
DUT_SRC_DIR=../../../src/rtl
INC_DIR=../../../src/include

_TARGETS_=	$(DUT_SRC_DIR)/uart_parity_bit_compute.v	\
		$(DUT_SRC_DIR)/uart_transmitter.v		\
		$(DUT_SRC_DIR)/uart_receiver.v			\
		$(DUT_SRC_DIR)/uart_controller.v		\
		$(DUT_SRC_DIR)/axi_internal_fifo.v		\
		$(DUT_SRC_DIR)/axi_uart_top.v


##########################################################################
#
# Test Bench Sources
#
##########################################################################
TB_SRC_DIR=../../../bench/verilog
_TB_=		$(TB_SRC_DIR)/tb_axi_uart.v

##########################################################################
#
# Misc Variables
#
##########################################################################

INCDIR=+incdir+$(INC_DIR) +incdir+$(DUT_SRC_DIR) +incdir+$(TB_SRC_DIR)
LOGF=-l .nclog
VCS_BUILD=../../../sim/vcs
VCS_LOG=$(VCS_BUILD)/log

##########################################################################
#
# Make Targets
#
##########################################################################

simw:
	@$(MAKE) -s sim ACCESS="+access+r " WAVES="+define+WAVES"

sim:
	mkdir -p $(VCS_BUILD)/log
	vcs -full64 -sverilog \
		-debug_access+all -debug_region+cell -kdb \
		-timescale=1ns/1ps \
		$(INCDIR) $(WAVES) $(ACCESS) \
		-top tb_axi_uart \
		-o $(VCS_BUILD)/simv \
		$(_TARGETS_) $(_TB_) \
		-l $(VCS_BUILD)/log/compile.log
	cd $(VCS_BUILD) && ./simv +vcs+fsdbon -l log/sim.log

ivl:
	/usr/local/bin/iverilog -g2012 -DFPGA_FULL=0 \
		$(_TARGETS_) $(_TB_) \
		$(foreach d,$(INC_DIR) $(DUT_SRC_DIR) $(TB_SRC_DIR),-I$(d)) \
		-s tb_axi_uart -o tb_axi_uart.vvp
	vvp tb_axi_uart.vvp
	rm -f tb_axi_uart.vvp

verdi:
	verdi \
		-dbdir $(VCS_BUILD)/simv.daidir \
		-ssf   $(VCS_BUILD)/wave.fsdb &

clean:
	rm -rf $(VCS_BUILD)
	rm -f  .nclog
	rm -f  ucli.key
	rm -f  *.vvp

##########################################################################
