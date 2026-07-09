#define REG(a) (*(volatile unsigned *)(a))
#define UART  0x10000000
#define GPIO  0x10001000
#define SPI   0x10002000
#define TIMER 0x10003000
#define INTC  0x10004000

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

static void done(int ok) { REG(GPIO) = 0xa500 | ok; for (;;); }

int main(void) {
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
  spi_xfer(3); spi_xfer(0); spi_xfer(0); spi_xfer(0);
  int b = spi_xfer(0);
  REG(SPI) = 1;
  if (b != _start[0]) { puts("spi fail\n"); done(0); }
  puts("spi ok\n");

  puts("PASS\n");
  done(1);
}
