#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: GPIO Pin Status Peripheral (Native AXI4)");

    uart_print("[SUBTEST 1] Reading GPIO Status Register (GPIO_STAT)...\n");
    uint32_t gpio_val = GPIO_STAT;
    uart_print("  GPIO_STAT raw value: "); uart_print_hex(gpio_val); uart_print("\n");

    int rst_pin = (gpio_val & (1 << 1)) != 0;
    uart_print("  reset_out pin (Bit 1): "); uart_print_dec(rst_pin); uart_print("\n");
    report_test("GPIO reset_out indicates active-low reset DEASSERTED (Bit 1 == 1)", rst_pin);

    int hb_pin = (gpio_val & (1 << 0)) != 0;
    uart_print("  heartbeat_in pin (Bit 0): "); uart_print_dec(hb_pin); uart_print("\n");
    report_test("GPIO heartbeat_in pin readable without bus fault", 1);

    uart_print("\n[SUBTEST 2] Verifying Reserved Bitfields...\n");
    // Bits [7:2] are reserved low
    int reserved_zero = ((gpio_val >> 2) & 0x3F) == 0;
    report_test("GPIO reserved status bits [7:2] read as 0", reserved_zero);

    uart_print("\n[SUBTEST 3] GPIO Read Stability Check...\n");
    int stable = 1;
    for (int i = 0; i < 10; i++) {
        uint32_t val = GPIO_STAT;
        if ((val & (1 << 1)) == 0) {
            stable = 0;
        }
        delay(10);
    }
    report_test("GPIO status register read values remain stable over time", stable);

    test_summary();
    return 0;
}
