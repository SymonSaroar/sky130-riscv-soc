# RV32I self-test. Returns 0 in a0, or the number of the first failing check.
  .macro CHECK n, r, v
  li    a0, \n
  li    t6, \v
  bne   \r, t6, fail
  .endm

  .text
  .globl isa_test
isa_test:
  # ALU, register-immediate
  li    t0, 5
  addi  t1, t0, -7
  CHECK 1, t1, -2
  slti  t1, t1, -1
  CHECK 2, t1, 1
  sltiu t1, t0, -1
  CHECK 3, t1, 1
  xori  t1, t0, -1
  CHECK 4, t1, -6
  ori   t1, t0, 0x30
  CHECK 5, t1, 0x35
  andi  t1, t0, 6
  CHECK 6, t1, 4
  slli  t1, t0, 30
  CHECK 7, t1, 0x40000000
  li    t2, -64
  srli  t1, t2, 28
  CHECK 8, t1, 15
  srai  t1, t2, 4
  CHECK 9, t1, -4

  # ALU, register-register
  li    t2, -3
  add   t1, t0, t2
  CHECK 10, t1, 2
  sub   t1, t0, t2
  CHECK 11, t1, 8
  slt   t1, t2, t0
  CHECK 12, t1, 1
  sltu  t1, t2, t0
  CHECK 13, t1, 0
  xor   t1, t0, t2
  CHECK 14, t1, -8
  or    t1, t0, t2
  CHECK 15, t1, -3
  and   t1, t0, t2
  CHECK 16, t1, 5
  li    t3, 33
  sll   t1, t0, t3
  CHECK 17, t1, 10
  srl   t1, t2, t3
  CHECK 18, t1, 0x7ffffffe
  sra   t1, t2, t3
  CHECK 19, t1, -2
  addi  zero, t0, 1
  CHECK 20, zero, 0

  # upper immediates
  lui   t1, 0xabcde
  CHECK 21, t1, 0xabcde000
1:auipc t1, 0
  jal   t3, 2f
2:sub   t1, t3, t1
  CHECK 22, t1, 8

  # branches
  li    t1, 0
  beq   t0, t0, 3f
  li    t1, 1
3:bne   t0, t0, 4f
  blt   t2, t0, 5f
4:li    t1, 2
  j     7f
5:bge   t2, t0, 4b
  bltu  t0, t2, 6f
  li    t1, 3
6:bgeu  t2, t0, 7f
  li    t1, 4
7:CHECK 23, t1, 0

  # jumps
  la    t3, 8f
  jalr  t4, 0(t3)
  li    a0, 24
  j     fail
8:sub   t1, t3, t4
  CHECK 24, t1, 8

  # loads and stores
  addi  sp, sp, -16
  li    t1, 0x80402010
  sw    t1, 0(sp)
  lw    t3, 0(sp)
  CHECK 25, t3, 0x80402010
  lb    t3, 3(sp)
  CHECK 26, t3, -128
  lbu   t3, 3(sp)
  CHECK 27, t3, 0x80
  lh    t3, 2(sp)
  CHECK 28, t3, 0xffff8040
  lhu   t3, 0(sp)
  CHECK 29, t3, 0x2010
  li    t1, 0x55
  sb    t1, 1(sp)
  lw    t3, 0(sp)
  CHECK 30, t3, 0x80405510
  li    t1, 0x1234
  sh    t1, 2(sp)
  lw    t3, 0(sp)
  CHECK 31, t3, 0x12345510
  lw    t3, 0(sp)
  addi  t3, t3, 1
  CHECK 32, t3, 0x12345511
  li    a0, 33
  li    t6, 0x12345510
  lw    t3, 0(sp)
  bne   t3, t6, fail
  addi  sp, sp, 16

  # CSRs
  la    t1, isa_test
  csrw  mepc, t1
  csrr  t3, mepc
  li    a0, 34
  bne   t3, t1, fail
  csrrw t3, mtvec, t1
  csrrc t3, mtvec, t1
  li    a0, 35
  bne   t3, t1, fail
  csrr  t3, mtvec
  CHECK 36, t3, 0

  li    a0, 0
fail:
  ret
