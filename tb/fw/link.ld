MEMORY { sram (rwx) : ORIGIN = 0, LENGTH = 2K }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > sram
  .data : { *(.data*) *(.sdata*) } > sram
  .bss  : { _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _bss_end = .; } > sram
}
