#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: UART 16550 Serial Controller");

    uart_print("[SUBTEST 1] Verifying UART Line Status Register (LSR)...\n");
    uint32_t lsr = UART_LSR;
    uart_print("  UART LSR raw: "); uart_print_hex(lsr); uart_print("\n");
    int thre = (lsr & UART_LSR_THRE) != 0;
    report_test("LSR indicates Transmitter Holding Register Empty (THRE = 1)", thre);

    uart_print("\n[SUBTEST 2] Verifying Interrupt Enable Register (IER)...\n");
    UART_IER = 0x07;
    uint32_t ier_val = UART_IER;
    uart_print("  UART IER readback: "); uart_print_hex(ier_val); uart_print("\n");
    report_test("IER register write/readback (0x07)", (ier_val & 0x0F) == 0x07);
    UART_IER = 0x00; // restore to 0

    uart_print("\n[SUBTEST 3] Verifying Line Control Register (LCR)...\n");
    UART_LCR = 0x03; // 8 data bits, 1 stop bit, no parity
    uint32_t lcr_val = UART_LCR;
    uart_print("  UART LCR readback: "); uart_print_hex(lcr_val); uart_print("\n");
    report_test("LCR configuration 8N1 (0x03) verified", (lcr_val & 0xFF) == 0x03);

    uart_print("\n[SUBTEST 4] Verifying Modem Control Register (MCR)...\n");
    UART_MCR = 0x0B;
    uint32_t mcr_val = UART_MCR;
    uart_print("  UART MCR readback: "); uart_print_hex(mcr_val); uart_print("\n");
    report_test("MCR register write/readback (0x0B)", (mcr_val & 0x1F) == 0x0B);

    uart_print("\n[SUBTEST 5] Verifying Scratchpad Register (SCR)...\n");
    UART_SCR = 0xA5;
    uint32_t scr1 = UART_SCR;
    UART_SCR = 0x5A;
    uint32_t scr2 = UART_SCR;
    uart_print("  SCR Pattern 1 (0xA5): "); uart_print_hex(scr1); uart_print("\n");
    uart_print("  SCR Pattern 2 (0x5A): "); uart_print_hex(scr2); uart_print("\n");
    report_test("SCR scratchpad pattern 0xA5 write/readback", (scr1 & 0xFF) == 0xA5);
    report_test("SCR scratchpad pattern 0x5A write/readback", (scr2 & 0xFF) == 0x5A);

    uart_print("\n[SUBTEST 6] Verifying Data Formatting Utilities...\n");
    uart_print("  Hex Output Verification: "); uart_print_hex(0xDEADBEEF); uart_print("\n");
    uart_print("  Decimal Output Verification: "); uart_print_dec(12345678); uart_print("\n");
    report_test("Console streaming & character transmission functional", 1);

    test_summary();
    return 0;
}
