#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: Standard 8-bit Bidirectional GPIO Peripheral");

    // ------------------------------------------------------------------------
    // Subtest 1: Direction Register (GPIO_DIR) Default & Configuration
    // ------------------------------------------------------------------------
    uart_print("[SUBTEST 1] Verifying GPIO Direction Register (GPIO_DIR)...\n");
    uint32_t dir_reset = GPIO_DIR;
    uart_print("  GPIO_DIR reset value: "); uart_print_hex(dir_reset); uart_print("\n");
    report_test("GPIO_DIR defaults to 0x00 (all pins input mode)", (dir_reset & 0xFF) == 0x00);

    // Configure pins [7:0] as outputs
    GPIO_DIR = 0x000000FF;
    uint32_t dir_out = GPIO_DIR;
    report_test("GPIO_DIR configured to 0xFF (all pins output mode)", (dir_out & 0xFF) == 0xFF);

    // ------------------------------------------------------------------------
    // Subtest 2: Data Output Register (GPIO_DATA) Drive & Loopback
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 2] Writing and Reading GPIO Output Data (GPIO_DATA)...\n");
    GPIO_DATA = 0x0000005A;
    uint32_t data_5a = GPIO_DATA;
    uart_print("  Wrote 0x5A, read back: "); uart_print_hex(data_5a); uart_print("\n");
    report_test("GPIO_DATA outputs and loopbacks pattern 0x5A", (data_5a & 0xFF) == 0x5A);

    GPIO_DATA = 0x0000003C;
    uint32_t data_3c = GPIO_DATA;
    report_test("GPIO_DATA outputs and loopbacks pattern 0x3C", (data_3c & 0xFF) == 0x3C);

    // ------------------------------------------------------------------------
    // Subtest 3: Input Mode Sampling (GPIO_DATA with GPIO_DIR = 0x00)
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 3] Reading External Input Pins (gpio_in)...\n");
    GPIO_DIR = 0x00000000; // Return to input mode
    uint32_t in_val = GPIO_DATA;
    uart_print("  Sampled gpio_in pattern: "); uart_print_hex(in_val); uart_print("\n");
    // In testbench, gpio_in is driven with 8'hA5
    report_test("GPIO_DATA correctly samples external gpio_in pins (0xA5)", (in_val & 0xFF) == 0xA5);

    // ------------------------------------------------------------------------
    // Subtest 4: BMC Status Register Compatibility (GPIO_STAT)
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 4] Verifying BMC Hardware Status (GPIO_STAT)...\n");
    uint32_t gpio_stat = GPIO_STAT;
    uart_print("  GPIO_STAT raw value: "); uart_print_hex(gpio_stat); uart_print("\n");

    int rst_pin = (gpio_stat & (1 << 1)) != 0;
    uart_print("  reset_out pin (Bit 1): "); uart_print_dec(rst_pin); uart_print("\n");
    report_test("GPIO_STAT reset_out indicates active-low reset DEASSERTED (Bit 1 == 1)", rst_pin);

    int reserved_zero = ((gpio_stat >> 2) & 0x3F) == 0;
    report_test("GPIO_STAT reserved bits [7:2] read as 0", reserved_zero);

    test_summary();
    return 0;
}
