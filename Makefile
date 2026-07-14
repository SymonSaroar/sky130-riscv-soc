export PDK_ROOT ?= $(HOME)/.volare
SRAM_V := $(PDK_ROOT)/sky130A/libs.ref/sky130_sram_macros/verilog/sky130_sram_2kbyte_1rw1r_32x512_8.v
RTL    := $(wildcard rtl/*.v)
CROSS  := riscv64-unknown-elf-
B      := build

.PHONY: fw sim lint clean

# ---------------- firmware and simulation ----------------
fw: $(B)/fw/fw.hex

$(B)/fw/fw.hex: tb/fw/start.S tb/fw/isa.S tb/fw/main.c tb/fw/link.ld
	@mkdir -p $(@D)
	$(CROSS)gcc -march=rv32i_zicsr -mabi=ilp32 -Os -nostdlib -ffreestanding -Wl,--no-warn-rwx-segments -T tb/fw/link.ld \
	  -o $(B)/fw/fw.elf tb/fw/start.S tb/fw/isa.S tb/fw/main.c
	$(CROSS)objdump -d $(B)/fw/fw.elf > $(B)/fw/fw.lst
	$(CROSS)size $(B)/fw/fw.elf
	$(CROSS)objcopy -O verilog $(B)/fw/fw.elf $@

sim: fw
	iverilog -g2012 -o $(B)/tb_soc \
	  tb/tb_soc.v tb/spi_flash.v tb/sram_model.v $(RTL)
	vvp -n $(B)/tb_soc $(SIMARGS)

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
	  --top-module soc_top $(RTL) $(SRAM_V) 2>&1 | grep -v sky130_sram || true

clean:
	rm -rf $(B)

# ---------------- implementation ----------------
RUN ?= dev
OUT := $(B)/$(RUN)
REP := reports/$(RUN)
export OUT REP RUN

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

MAGIC := magic -dnull -noconsole -rcfile $(PDK_ROOT)/sky130A/libs.tech/magic/sky130A.magicrc

.PHONY: rcx sta gds magic klayout_drc lvs signoff
rcx:
	openroad -no_init -exit -log $(OUT)/rcx.log extraction/rcx.tcl > /dev/null
sta:
	sta -no_init -exit sta/sta.tcl > $(OUT)/sta.log
gds:
	klayout -b -r signoff/def2gds.py > $(OUT)/gds.log
magic:
	ulimit -n 1024 && $(MAGIC) signoff/magic.tcl > $(OUT)/magic.log
klayout_drc:
	klayout -b -r $(PDK_ROOT)/sky130A/libs.tech/klayout/drc/sky130A_mr.drc \
	  -rd input=$(CURDIR)/$(OUT)/soc_top.gds -rd top_cell=soc_top -rd report=$(CURDIR)/$(REP)/drc_klayout.xml \
	  -rd feol=true -rd beol=true -rd offgrid=true > $(OUT)/drc_klayout.log
lvs: magic
	netgen -batch source signoff/lvs.tcl > $(OUT)/lvs.log
	{ sed -n "$$(grep -n 'Subcircuit summary' $(REP)/lvs.rpt | tail -1 | cut -d: -f1),\$$p" $(REP)/lvs.rpt | head -80; \
	  grep -A1 '^Final result' $(REP)/lvs.rpt; } > $(REP)/lvs.summary
signoff: rcx sta gds lvs klayout_drc

.PHONY: metrics all
metrics:
	python3 metrics.py $(RUN)
all: synth floorplan place cts route signoff metrics
