OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  /* 8KB AXI ROM mapped at 0x8000_0000 */
  rom (rx)  : ORIGIN = 0x80000000, LENGTH = 8K
  /* 64KB DCCM (Data RAM) internally mapped at 0xF004_0000 */
  ram (rwx) : ORIGIN = 0xF0040000, LENGTH = 64K
}

SECTIONS
{
  .text : {
    *(.text.init)
    *(.text*)
    *(.rodata*)
  } > rom

  .data : {
    . = ALIGN(4);
    *(.data*)
    *(.sdata*)
  } > ram AT > rom

  .bss : {
    . = ALIGN(4);
    *(.bss*)
    *(.sbss*)
    *(COMMON)
  } > ram
}
