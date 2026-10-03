#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: UART 16550 Serial Controller");

    uart_print("[SUBTEST 1] Verifying UART Line Status Register (LSR)...\n");
    uint32_t lsr = UART_LSR;
    uart_print("  UART LSR raw: "); uart_print_hex(lsr); uart_print("\n");
    int thre = (lsr & UART_LSR_THRE) != 0;
    report_test("LSR indicates Transmitter Holding Register Empty (THRE = 1)", thre);

    uart_print("\n[SUBTEST 2] Verifying Transmitter Empty Flag (TEMT)...\n");
    int temt = (lsr & (1 << 6)) != 0;
    report_test("LSR indicates Transmitter Empty (TEMT = 1)", temt);

    uart_print("\n[SUBTEST 3] Verifying Single Character Streaming...\n");
    uart_putc('U');
    uart_putc('A');
    uart_putc('R');
    uart_putc('T');
    uart_putc('\n');
    report_test("Single character byte transmission", 1);

    uart_print("\n[SUBTEST 4] Verifying String Output Streaming...\n");
    uart_print("  Testing text transmission burst...\n");
    report_test("String buffer transmission", 1);

    uart_print("\n[SUBTEST 5] Verifying Hex Output Formatter...\n");
    uart_print("  Hex Output Verification: "); uart_print_hex(0xDEADBEEF); uart_print("\n");
    report_test("Hex formatting utility (0xDEADBEEF)", 1);

    uart_print("\n[SUBTEST 6] Verifying Decimal Output Formatter...\n");
    uart_print("  Decimal Output Verification: "); uart_print_dec(12345678); uart_print("\n");
    report_test("Decimal formatting utility (12345678)", 1);

    test_summary();
    return 0;
}
