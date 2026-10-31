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
    uint32_t wd3 = WATCHDOG_TIMEOUT;
    while ((UART_LSR & UART_LSR_TEMT) == 0 && --wd3);
    report_test("Single character byte transmission", (wd3 > 0) && ((UART_LSR & UART_LSR_TEMT) != 0));

    uart_print("\n[SUBTEST 4] Verifying String Output Streaming...\n");
    uart_print("  Testing text transmission burst...\n");
    uint32_t wd4 = WATCHDOG_TIMEOUT;
    while ((UART_LSR & UART_LSR_TEMT) == 0 && --wd4);
    report_test("String buffer transmission", (wd4 > 0) && ((UART_LSR & UART_LSR_TEMT) != 0));

    uart_print("\n[SUBTEST 5] Verifying Hex Output Formatter...\n");
    char hex_buf[16];
    format_hex(hex_buf, 0xDEADBEEF);
    uart_print("  Hex Output Verification: "); uart_print(hex_buf); uart_print("\n");
    report_test("Hex formatting utility (0xDEADBEEF)", str_equals(hex_buf, "0xDEADBEEF"));

    uart_print("\n[SUBTEST 6] Verifying Decimal Output Formatter...\n");
    char dec_buf[16];
    format_dec(dec_buf, 12345678);
    uart_print("  Decimal Output Verification: "); uart_print(dec_buf); uart_print("\n");
    report_test("Decimal formatting utility (12345678)", str_equals(dec_buf, "12345678"));

    test_summary();
    return 0;
}
