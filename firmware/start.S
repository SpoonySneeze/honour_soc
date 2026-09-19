.section .text.init
.global _start

_start:
    # Disable interrupts globally for now
    csrw mstatus, zero
    csrw mie, zero

    # Initialize Stack Pointer to top of DCCM (64KB at 0xF0040000)
    li sp, 0xF0050000

    # Call main
    call main

1:
    # Infinite loop if main returns
    j 1b
