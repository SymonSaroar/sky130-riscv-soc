export PDK_ROOT ?= $(HOME)/.volare
SRAM_V := $(PDK_ROOT)/sky130A/libs.ref/sky130_sram_macros/verilog/sky130_sram_2kbyte_1rw1r_32x512_8.v
IO_V   := $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_io/verilog
RTL    := $(wildcard rtl/*.v)
CROSS  := riscv64-unknown-elf-
B      := build

.PHONY: fw sim lint clean

# ---------------- firmware and simulation ----------------
fw: $(B)/fw/fw.hex

FW_CC := $(CROSS)gcc -march=rv32im_zicsr -mabi=ilp32 -Os -nostdlib -ffreestanding -Wl,--no-warn-rwx-segments

# flash image: stage 1 loader in the first 2 KB, then the program length and the program
$(B)/fw/fw.hex: $(wildcard tb/fw/*.S tb/fw/*.c tb/fw/*.ld)
	@mkdir -p $(@D)
	$(FW_CC) -T tb/fw/link_sram.ld -o $(B)/fw/loader.elf tb/fw/start.S tb/fw/loader.c
	$(FW_CC) -T tb/fw/link_sdram.ld -o $(B)/fw/fw.elf tb/fw/start.S tb/fw/isa.S tb/fw/main.c
	$(CROSS)objdump -d $(B)/fw/fw.elf > $(B)/fw/fw.lst
	$(CROSS)size $(B)/fw/loader.elf $(B)/fw/fw.elf
	$(CROSS)objcopy -O binary $(B)/fw/loader.elf $(B)/fw/loader.bin
	$(CROSS)objcopy -O binary -j .text -j .data $(B)/fw/fw.elf $(B)/fw/fw.bin
	python3 -c "import struct, sys; a = open(sys.argv[1], 'rb').read().ljust(2048, b'\xff'); \
	  b = open(sys.argv[2], 'rb').read(); b += bytes(-len(b) % 4); \
	  open(sys.argv[3], 'w').write('\n'.join('%02x' % x for x in a + struct.pack('<I', len(b)) + b))" \
	  $(B)/fw/loader.bin $(B)/fw/fw.bin $@

sim: fw
	iverilog -g2012 -Itb -s tb_soc -DUSE_POWER_PINS -DFUNCTIONAL -o $(B)/tb_soc \
	  tb/tb_soc.v tb/spi_flash.v tb/sram_model.v tb/sdram_model.v tb/pcie_phy.v tb/pcie_lane.v tb/pcie_dev.v $(RTL) \
	  $(IO_V)/sky130_ef_io.v $(IO_V)/sky130_fd_io.v
	vvp -n $(B)/tb_soc $(SIMARGS)

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
	  --top-module soc_top $(filter-out rtl/chip_top.v,$(RTL)) $(SRAM_V) 2>&1 | grep -v sky130_sram || true

clean:
	rm -rf $(B)

# ---------------- implementation ----------------
RUN ?= dev
OUT := $(B)/$(RUN)
REP := reports/$(RUN)
export OUT REP RUN

# timing copies of the gpiov2 pad liberty and SRAM liberties for the slow and fast corners
LIB_IO   := $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_io/lib/sky130_ef_io__gpiov2_pad_wrapped
LIB_SRAM := $(PDK_ROOT)/sky130A/libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib
CORNER_LIBS := $(addprefix $(OUT)/,gpiov2_tt.lib gpiov2_ss.lib gpiov2_ff.lib sram_ss.lib sram_ff.lib)
$(OUT)/gpiov2_tt.lib: PAD := tt_tt_025C_1v80_3v30
$(OUT)/gpiov2_ss.lib: PAD := ss_ss_100C_1v60_3v00
$(OUT)/gpiov2_ff.lib: PAD := ff_ff_n40C_1v95_5v50
$(OUT)/gpiov2_%.lib: sta/pad_lib.py
	@mkdir -p $(OUT)
	python3 sta/pad_lib.py $(LIB_IO)_$(PAD).lib $@
$(OUT)/sram_%.lib: sta/sram_lib.py
	@mkdir -p $(OUT)
	python3 sta/sram_lib.py $(LIB_SRAM) $* $@
# PCIe PHY placeholder views from one pin table
PHY_VIEWS := $(addprefix $(OUT)/pcie_phy,.lef .gds .v .spice _tt.lib _ss.lib _ff.lib)
$(PHY_VIEWS) &: macros/pcie_phy.py
	@mkdir -p $(OUT)
	klayout -b -r macros/pcie_phy.py -rd out=$(OUT)
floorplan place cts route rcx sta ir: $(CORNER_LIBS) $(PHY_VIEWS)
synth: $(PHY_VIEWS)

.PHONY: synth
synth:
	@mkdir -p $(OUT) $(REP)
	yosys -q -l $(OUT)/synth.log -c synthesis/synth.tcl

.PHONY: floorplan
floorplan:
	openroad -no_init -exit -log $(OUT)/floorplan.log floorplan/floorplan.tcl > /dev/null

.PHONY: place cts
place:
	openroad -no_init -exit -log $(OUT)/place.log placement/place.tcl > /dev/null
cts:
	openroad -no_init -exit -log $(OUT)/cts.log cts/cts.tcl > /dev/null

.PHONY: route
route:
	openroad -no_init -threads max -exit -log $(OUT)/grt.log routing/grt.tcl > /dev/null
	for c in ff ss; do CORNER=$$c openroad -no_init -threads max -exit -log $(OUT)/grt_$$c.log routing/corner.tcl \
	  > /dev/null || exit 1; done
	openroad -no_init -threads max -exit -log $(OUT)/route.log routing/route.tcl > /dev/null
	openroad -no_init -threads max -exit -log $(OUT)/finish.log routing/finish.tcl > /dev/null

MAGIC := magic -dnull -noconsole -rcfile $(PDK_ROOT)/sky130A/libs.tech/magic/sky130A.magicrc

.PHONY: rcx sta ir em gds pads render magic klayout_drc density lvs lec signoff
rcx:
	openroad -no_init -exit -log $(OUT)/rcx.log extraction/rcx.tcl > /dev/null
sta:
	for c in tt ss ff; do CORNER=$$c sta -no_init -exit sta/sta.tcl > $(OUT)/sta_$$c.log || exit 1; done
ir:
	openroad -no_init -threads max -exit -log $(OUT)/ir.log power/ir.tcl > /dev/null
	grep -A6 'Supply voltage' $(OUT)/ir.log > $(REP)/ir.rpt
em:
	klayout -b -r power/em.py > $(OUT)/em.log
gds:
	klayout -b -r signoff/def2gds.py > $(OUT)/gds.log
	klayout -b -r signoff/fill.py >> $(OUT)/gds.log
pads:
	klayout -b -r signoff/pads.py > $(OUT)/pads.log
render:
	klayout -b -r signoff/render.py
magic:
	ulimit -n 1024 && $(MAGIC) signoff/magic.tcl > $(OUT)/magic.log
klayout_drc:
	klayout -b -r $(PDK_ROOT)/sky130A/libs.tech/klayout/drc/sky130A_mr.drc \
	  -rd input=$(CURDIR)/$(OUT)/chip_top.gds -rd top_cell=chip_top -rd report=$(CURDIR)/$(REP)/drc_klayout.xml \
	  -rd feol=true -rd beol=true -rd offgrid=true -rd seal=true > $(OUT)/drc_klayout.log
density:
	klayout -b -r $(PDK_ROOT)/sky130A/libs.tech/klayout/drc/met_min_ca_density.lydrc \
	  -rd input=$(CURDIR)/$(OUT)/chip_top.gds -rd top_cell=chip_top -rd report=$(CURDIR)/$(REP)/density.xml > $(OUT)/density.log
	grep "density is" $(OUT)/density.log > $(REP)/density.rpt
lvs: magic
	netgen -batch source signoff/lvs.tcl > $(OUT)/lvs.log
	{ sed -n "$$(grep -n 'Subcircuit summary' $(REP)/lvs.rpt | tail -1 | cut -d: -f1),\$$p" $(REP)/lvs.rpt | head -80; \
	  grep -A1 '^Final result' $(REP)/lvs.rpt; } > $(REP)/lvs.summary
lec:
	yosys -q -l $(OUT)/lec.log -c signoff/lec.tcl > /dev/null 2>&1
	yosys-abc -c "read_aiger $(OUT)/lec.aig; print_stats; iprove" | sed 's/\x1b\[[0-9;]*m//g' > $(REP)/lec.rpt
	grep -q UNSATISFIABLE $(REP)/lec.rpt
signoff: rcx sta ir gds em pads render lvs klayout_drc density lec

.PHONY: metrics all
metrics:
	python3 metrics.py $(RUN)
all: synth floorplan place cts route signoff metrics

SC_V := $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog
.PRECIOUS: $(OUT)/primitives_%.v
# simulation copies: every flop starts at 0 or at 1 under constant supplies, and the gpiov2 wrapper without supply
# pins and with per-instance pad delays
$(OUT)/primitives_%.v: tb/primitives_gls.py
	python3 tb/primitives_gls.py $(SC_V)/primitives.v $* $@
$(OUT)/sky130_ef_io_gls.v: tb/pad_gls.py
	python3 tb/pad_gls.py $(IO_V)/sky130_ef_io.v $@

# the synthesized netlist with functional cell models, flops starting at 0 (gls0) and at 1 (gls1)
.PHONY: gls gls0 gls1
gls: gls0 gls1
gls0 gls1: gls%: fw $(OUT)/primitives_%.v $(OUT)/sky130_ef_io_gls.v
	iverilog -g2012 -Itb -s tb_soc -DGLS -DFUNCTIONAL -DUNIT_DELAY=#1 -o $(OUT)/tb_$@ \
	  tb/tb_soc.v tb/spi_flash.v tb/sram_model.v tb/sdram_model.v tb/pcie_phy.v tb/pcie_lane.v tb/pcie_dev.v \
	  $(OUT)/primitives_$*.v $(SC_V)/sky130_fd_sc_hd.v $(OUT)/chip_top.v \
	  $(OUT)/sky130_ef_io_gls.v $(IO_V)/sky130_fd_io.v
	vvp -n $(OUT)/tb_$@ +progress=$(OUT)/$@.time | sed 's/^/$@: /'

# the routed netlist with the cell timing models and the delays from signoff STA, pads included. CORNER=ss runs the
# slow corner at its 50 MHz clk and 62.5 MHz mclk, CORNER=ff the fast corner; the SRAM read window scales as in
# sta/sram_lib.py, the PHY macro's timing as in its liberty.
CORNER ?= tt
GS := $(if $(filter tt,$(CORNER)),,_$(CORNER))
GLS_ss := -Ptb_soc.CLK_HALF=10 -Ptb_soc.MCLK_HALF=8 -DSRAM_K=2.1 -DPHY_K=2.1
GLS_ff := -DSRAM_K=0.64 -DPHY_K=0.64
.PHONY: gls_sdf
gls_sdf: fw $(OUT)/primitives_0.v $(OUT)/sky130_ef_io_gls.v
	python3 sta/sdf_iverilog.py $(OUT)/chip_top$(GS).sdf $(OUT)/chip_top.final.v $(OUT)/chip_top_iverilog$(GS).sdf \
	  $(OUT)/chip_top_pads$(GS).v
	iverilog -g2012 -Itb -gspecify -ginterconnect -s tb_soc -s sdf_pads -DGLS -DSDF='"$(OUT)/chip_top_iverilog$(GS).sdf"' \
	  $(GLS_$(CORNER)) -o $(OUT)/tb_gls_sdf$(GS) tb/tb_soc.v tb/spi_flash.v tb/sram_model.v tb/sdram_model.v \
	  tb/pcie_phy.v tb/pcie_lane.v tb/pcie_dev.v \
	  $(OUT)/primitives_0.v $(SC_V)/sky130_fd_sc_hd.v $(OUT)/chip_top.final.v \
	  $(OUT)/sky130_ef_io_gls.v $(IO_V)/sky130_fd_io.v $(OUT)/chip_top_pads$(GS).v
	vvp -n $(OUT)/tb_gls_sdf$(GS) +progress=$(OUT)/gls_sdf$(GS).time
