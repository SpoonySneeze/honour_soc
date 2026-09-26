.section .text.init
.global _start

_start:
    # Disable interrupts globally for now
    csrw mstatus, zero
    csrw mie, zero

    # Configure MRAC (CSR 0x7c0): Region 0 (0x0002_xxxx) marked as Device / Side-Effect memory
    li t0, 0x00000002
    csrw 0x7c0, t0

    # Initialize Stack Pointer to top of DCCM (64KB at 0xF0040000)
    li sp, 0xF0050000

    # Zero out .bss section
    la t0, _sbss
    la t1, _ebss
bss_loop:
    bge t0, t1, bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_loop
bss_done:

    # Call main
    call main

1:
    # Infinite loop if main returns
    j 1b
