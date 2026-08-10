// Stage 1, runs from SRAM: copy the program at flash 0x800 into SDRAM and jump to it.
// Flash at 0x800 holds the program length in bytes, then the program.
#define REG(a) (*(volatile unsigned *)(a))
#define SPI   0x10002000
#define SDRAM 0x80000000

static unsigned xfer(unsigned b) { REG(SPI + 4) = b; while (REG(SPI + 8)); return REG(SPI + 4); }
static unsigned word(void) { unsigned w = 0; for (int i = 0; i < 32; i += 8) w |= xfer(0) << i; return w; }

int main(void) {
  REG(SPI) = 0;
  xfer(3); xfer(0); xfer(8); xfer(0);
  unsigned n = word();
  for (unsigned a = SDRAM; a < SDRAM + n; a += 4) REG(a) = word();
  REG(SPI) = 1;
  ((void (*)(void))SDRAM)();
  return 0;
}
