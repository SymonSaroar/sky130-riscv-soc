#define REG(a) (*(volatile unsigned *)(a))
#define UART  0x10000000
#define GPIO  0x10001000
#define SPI   0x10002000
#define TIMER 0x10003000
#define INTC  0x10004000
#define SDRAM 0x80000000
#define PCIE  0x40000000
#define PCIE_ST 0x10005000
#define CLK_HZ 100000000

int isa_test(void);
extern volatile unsigned char _start[];

static volatile int ticks, rx;

static void putc(int c) { while (REG(UART + 4) & 1); REG(UART) = c; }
static void puts(const char *s) { while (*s) putc(*s++); }
static void puthex(unsigned v) { for (int i = 28; i >= 0; i -= 4) putc("0123456789abcdef"[(v >> i) & 15]); }

static int spi_xfer(int b) { REG(SPI + 4) = b; while (REG(SPI + 8)); return REG(SPI + 4); }

__attribute__((interrupt("machine"))) static void trap(void) {
  unsigned cause;
  asm volatile("csrr %0, mcause" : "=r"(cause));
  if (cause == 0x80000007) {
    ticks++;
    REG(TIMER + 4) = REG(TIMER) + 1000;
  } else if (REG(INTC) & 1) {
    rx = REG(UART);
  }
}

static unsigned pat(unsigned a) { return a ^ (a << 13) ^ (a >> 7) ^ 0xa5a5a5a5; }

// 16 words each in row 16 of banks 0 and 1, row 256 and the last row, then byte and halfword stores
static int sdram_test(void) {
  static const unsigned base[] = {0x10000, 0x10400, 0x100000, 0x1fffc00};
  int err = 0;
  for (int pass = 0; pass < 2; pass++)
    for (int b = 0; b < 4; b++)
      for (unsigned a = SDRAM + base[b]; a < SDRAM + base[b] + 64; a += 4)
        if (pass == 0) REG(a) = pat(a);
        else if (REG(a) != pat(a)) err++;
  *(volatile unsigned char *)(SDRAM + 0x10001) = 0x5a;
  *(volatile unsigned short *)(SDRAM + 0x10002) = 0x1234;
  if (REG(SDRAM + 0x10000) != (0x12345a00 | (pat(SDRAM + 0x10000) & 0xff))) err++;
  return err;
}

// wait for the link, then 8 words and a byte store to the endpoint's memory
static int pcie_test(void) {
  for (int t = 0; !(REG(PCIE_ST) & 1); t++) if (t > 100000) return -1;
  int err = 0;
  for (int i = 0; i < 8; i++) REG(PCIE + 0x100 + i * 4) = pat(i);
  for (int i = 0; i < 8; i++) if (REG(PCIE + 0x100 + i * 4) != pat(i)) err++;
  *(volatile unsigned char *)(PCIE + 0x101) = 0x5a;
  if (REG(PCIE + 0x100) != ((pat(0) & 0xffff00ff) | 0x5a00)) err++;
  if (REG(PCIE_ST) & 0xff0) err++;  // replays
  return err;
}

static short ma[8][8], mb[8][8];
static int mc[8][8];

static unsigned smul(unsigned a, unsigned b) { unsigned r = 0; for (; b; b >>= 1, a <<= 1) if (b & 1) r += a; return r; }

// 8x8 matrix multiply with divides; cycles, or 0 if a product differs from shift-and-add
static unsigned bench(void) {
  unsigned t = REG(TIMER), sum = 0;
  for (int i = 0; i < 8; i++)
    for (int j = 0; j < 8; j++) {
      int c = 0;
      for (int k = 0; k < 8; k++) c += ma[i][k] * mb[k][j];
      mc[i][j] = c;
      sum += c / (j + 1) + c % (i + 3);
    }
  t = REG(TIMER) - t;
  for (int i = 0; i < 8; i++)
    for (int j = 0; j < 8; j++) {
      unsigned c = 0;
      for (int k = 0; k < 8; k++) c += smul(ma[i][k], mb[k][j]);
      if (c != (unsigned)mc[i][j]) return 0;
    }
  return sum ? t : 0;
}

static void done(int ok) { REG(GPIO) = 0xa500 | ok; for (;;); }

int main(void) {
  REG(UART + 8) = CLK_HZ / 115200;
  int e = isa_test();
  puts("boot\n");
  if (e) { puts("isa fail "); puthex(e); putc('\n'); done(0); }
  puts("isa ok\n");

  // timer interrupt
  asm volatile("csrw mtvec, %0" :: "r"(trap));
  REG(TIMER + 4) = REG(TIMER) + 1000;
  asm volatile("csrs mie, %0" :: "r"(1 << 7));
  asm volatile("csrs mstatus, 8");
  while (ticks < 3);
  asm volatile("csrc mie, %0" :: "r"(1 << 7));
  puts("timer ok\n");

  // UART receive interrupt through INTC
  REG(INTC + 4) = 1;
  asm volatile("csrs mie, %0" :: "r"(1 << 11));
  REG(GPIO) = 0xa0;
  while (!rx);
  if (rx != 'Z') { puts("rx fail\n"); done(0); }
  puts("rx ok\n");

  // SPI flash read back of byte 0
  REG(SPI) = 0;
  spi_xfer(3); spi_xfer(0); spi_xfer(8); spi_xfer(4);
  int b = spi_xfer(0);
  REG(SPI) = 1;
  if (b != _start[0]) { puts("spi fail\n"); done(0); }
  puts("spi ok\n");

  if (sdram_test()) { puts("sdram fail\n"); done(0); }
  puts("sdram ok\n");

  if (pcie_test()) { puts("pcie fail\n"); done(0); }
  puts("pcie ok "); puthex(REG(PCIE_ST)); putc('\n');

  for (int i = 0; i < 64; i++) {
    ma[i / 8][i % 8] = (short)(pat(i) & 0x7fff) - 0x4000;
    mb[i / 8][i % 8] = (short)(pat(i + 64) & 0x7fff) - 0x4000;
  }
  unsigned cold = bench(), warm = bench();
  if (!cold || !warm) { puts("bench fail\n"); done(0); }
  puts("bench cycles "); puthex(cold); putc(' '); puthex(warm); putc('\n');

  puts("PASS\n");
  done(1);
}
