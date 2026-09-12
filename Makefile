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
	iverilog -g2012 -s tb_soc -DUSE_POWER_PINS -DFUNCTIONAL -o $(B)/tb_soc \
	  tb/tb_soc.v tb/spi_flash.v tb/sram_model.v tb/sdram_model.v $(RTL) $(IO_V)/sky130_ef_io.v $(IO_V)/sky130_fd_io.v
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
floorplan place cts route rcx sta ir: $(CORNER_LIBS)

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
	openroad -no_init -threads max -exit -log $(OUT)/route.log routing/route.tcl > /dev/null
	openroad -no_init -threads max -exit -log $(OUT)/finish.log routing/finish.tcl > /dev/null

MAGIC := magic -dnull -noconsole -rcfile $(PDK_ROOT)/sky130A/libs.tech/magic/sky130A.magicrc

.PHONY: rcx sta ir gds render magic klayout_drc density lvs signoff
rcx:
	openroad -no_init -exit -log $(OUT)/rcx.log extraction/rcx.tcl > /dev/null
sta:
	for c in tt ss ff; do CORNER=$$c sta -no_init -exit sta/sta.tcl > $(OUT)/sta_$$c.log || exit 1; done
ir:
	openroad -no_init -threads max -exit -log $(OUT)/ir.log power/ir.tcl > /dev/null
	grep -A6 'Supply voltage' $(OUT)/ir.log > $(REP)/ir.rpt
gds:
	klayout -b -r signoff/def2gds.py > $(OUT)/gds.log
	klayout -b -r signoff/fill.py >> $(OUT)/gds.log
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
signoff: rcx sta ir gds render lvs klayout_drc density

.PHONY: metrics all
metrics:
	python3 metrics.py $(RUN)
all: synth floorplan place cts route signoff metrics

SC_V := $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog
.PRECIOUS: $(OUT)/primitives_%.v
# simulation copies: every flop starts at 0 or at 1, and the gpiov2 wrapper leaves off the supply pins
# the netlist does not have, so the pad model uses its own supplies
$(OUT)/primitives_%.v:
	sed "s/^\( *\)reg Q;/&\n\1initial Q = 1'b$*;/" $(SC_V)/primitives.v > $@
$(OUT)/sky130_ef_io_gls.v:
	sed -e '/^module sky130_ef_io__gpiov2_pad_wrapped/,/^endmodule/{/^ *\.\(VSSA\|VDDA\|VSWITCH\|VDDIO_Q\|VCCHIB\|VDDIO\|VCCD\|VSSIO\|VSSD\|VSSIO_Q\)(/d' \
	    -e 's/\.AMUXBUS_B(AMUXBUS_B),/.AMUXBUS_B(AMUXBUS_B)/}' $(IO_V)/sky130_ef_io.v > $@

# the synthesized netlist with functional cell models, flops starting at 0 (gls0) and at 1 (gls1)
.PHONY: gls gls0 gls1
gls: gls0 gls1
gls0 gls1: gls%: fw $(OUT)/primitives_%.v $(OUT)/sky130_ef_io_gls.v
	iverilog -g2012 -s tb_soc -DGLS -DFUNCTIONAL -DUNIT_DELAY=#1 -o $(OUT)/tb_$@ \
	  tb/tb_soc.v tb/spi_flash.v tb/sram_model.v tb/sdram_model.v \
	  $(OUT)/primitives_$*.v $(SC_V)/sky130_fd_sc_hd.v $(OUT)/chip_top.v \
	  $(OUT)/sky130_ef_io_gls.v $(IO_V)/sky130_fd_io.v
	vvp -n $(OUT)/tb_$@ | sed 's/^/$@: /'

