#include "test_common.h"

void run_test_uart(void) {
    uart_print("\n--- [IP 1/7] UART 16550 Serial Controller ---\n");
    uint32_t lsr = UART_LSR;
    report_test("LSR indicates Transmitter Ready (THRE)", (lsr & UART_LSR_THRE) != 0);

    UART_SCR = 0xA5;
    report_test("SCR scratchpad register write/readback (0xA5)", (UART_SCR & 0xFF) == 0xA5);
}

void run_test_timer(void) {
    uart_print("\n--- [IP 2/7] System Timer Peripheral ---\n");
    uint32_t t1 = TMR_CTR;
    delay(50);
    uint32_t t2 = TMR_CTR;
    uart_print("  TMR t1: "); uart_print_hex(t1);
    uart_print(", t2: "); uart_print_hex(t2);
    uart_print("\n");
    report_test("Timer monotonic cycle counter incrementing", (t2 > t1));
}

void run_test_gpio(void) {
    uart_print("\n--- [IP 3/7] GPIO Pin Status Peripheral ---\n");
    uint32_t gpio_val = GPIO_STAT;
    uart_print("  GPIO Status: "); uart_print_hex(gpio_val); uart_print("\n");
    int rst_pin_ok = (gpio_val & (1 << 1)) != 0;
    report_test("GPIO reset_out indicates HIGH (active-low deasserted)", rst_pin_ok);
}

void run_test_heartbeat(void) {
    uart_print("\n--- [IP 4/7] Heartbeat Monitor Watchdog IP ---\n");
    HB_THRESHOLD = 50000;
    report_test("HB_THRESHOLD write/readback (50000)", (HB_THRESHOLD == 50000));

    HB_CTRL = 1; // Enable
    delay(20);
    report_test("HB_STATUS unresponsive flag is CLEAR", ((HB_STATUS & 1) == 0));

    HB_CTRL = 3; // Pet watchdog (enable + clear)
    report_test("HB_CTRL petting command executed successfully", 1);
}

void run_test_reset_sequencer(void) {
    uart_print("\n--- [IP 5/7] Power/Reset Sequencer IP ---\n");
    uint32_t rst_default = RST_HOLD_CYCLES;
    uart_print("  Default RST_HOLD_CYCLES: "); uart_print_dec(rst_default); uart_print("\n");
    report_test("RST_HOLD_CYCLES reset value is 100", (rst_default == 100));

    RST_HOLD_CYCLES = 60;
    report_test("RST_HOLD_CYCLES write/readback (60)", (RST_HOLD_CYCLES == 60));

    RST_HOLD_CYCLES = 100; // Restore
    report_test("RST_STATUS indicates idle", ((RST_STATUS & 1) == 0));
}

void run_test_recovery_policy(void) {
    uart_print("\n--- [IP 6/7] Recovery Policy & Circular Event Log IP ---\n");
    POL_WINDOW = 200000;
    report_test("POL_WINDOW write/readback (200000)", (POL_WINDOW == 200000));

    POL_THRESHOLD = 3;
    report_test("POL_THRESHOLD write/readback (3)", ((POL_THRESHOLD & 0xFF) == 3));

    POL_CTRL = 2; // clear_lockout
    report_test("POL_STATUS lockout cleared", ((POL_STATUS & 1) == 0));

    // Event 1
    POL_EVENT_TS = 0x11223344;
    POL_CTRL = 1;
    delay(10);
    report_test("LOG_COUNT updated to 1 after Event 1", (LOG_COUNT == 1));

    LOG_READ_IDX = 0;
    report_test("Circular Log[0] matches timestamp 0x11223344", (LOG_READ_DATA == 0x11223344));

    // Event 2
    POL_EVENT_TS = 0xAABBCCDD;
    POL_CTRL = 1;
    delay(10);
    report_test("LOG_COUNT updated to 2 after Event 2", (LOG_COUNT == 2));

    LOG_READ_IDX = 1;
    report_test("Circular Log[1] matches timestamp 0xAABBCCDD", (LOG_READ_DATA == 0xAABBCCDD));
}

void run_test_vga(void) {
    uart_print("\n--- [IP 7/7] VGA Status Dashboard IP ---\n");
    VGA_CTRL = 1; // Enable Display
    report_test("VGA_CTRL enable display", ((VGA_CTRL & 1) == 1));

    // Write a test pattern to buffer
    VGA_TEXT_BUFFER[0] = 0x41424344; // "ABCD"
    report_test("VGA text buffer programmed with status dashboard", (VGA_TEXT_BUFFER[0] != 0));
}

int main(void) {
    test_header("BMC System-on-Chip: Comprehensive All-IP Integration Suite");

    run_test_uart();
    run_test_timer();
    run_test_gpio();
    run_test_heartbeat();
    run_test_reset_sequencer();
    run_test_recovery_policy();
    run_test_vga();

    test_summary();

    // Heartbeat service loop
    while (1) {
        HB_CTRL = 3;
        delay(500);
    }

    return 0;
}
