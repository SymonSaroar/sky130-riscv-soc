MEMORY { sdram (rwx) : ORIGIN = 0x80000000, LENGTH = 32M
         sram  (rw)  : ORIGIN = 0x400, LENGTH = 0x300 }
SECTIONS {
  .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > sdram
  .data : { *(.data*) *(.sdata*) } > sdram
  .bss  : { _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _bss_end = .; } > sram
}
