// ============================================================================
// Honour SoC — UVM Environment Sanity Test (test_uvm_sanity.c)
// ============================================================================
// Purpose:
//   Lightweight, fast bare-metal firmware to verify that:
//   1. VeeR EL2 CPU core boots and executes code properly.
//   2. Native AXI4 interconnect and MMIO decoding function correctly.
//   3. Peripheral register reads and writes operate as expected.
//   4. External signals (UART telemetry, GPIO pins) toggle for UVM VIPs.
//   5. Signals "UVM_SANITY_PASS" string for the UVM environment scoreboard.
// ============================================================================

#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: UVM Test Environment Sanity Check");

    // ------------------------------------------------------------------------
    // Subtest 1: UART Transmitter & Telemetry Link
    // ------------------------------------------------------------------------
    uart_print("[SUBTEST 1] Testing UART 16550 Transmission...\n");
    uint32_t lsr_val = UART_LSR;
    uart_print("  UART_LSR value: "); uart_print_hex(lsr_val); uart_print("\n");
    report_test("UART transmitter holding register is ready", (lsr_val & UART_LSR_THRE) != 0);

    // ------------------------------------------------------------------------
    // Subtest 2: System Timer Monotonic Progression
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 2] Testing System Timer Progression...\n");
    uint32_t t0 = TMR_CTR;
    delay(50);
    uint32_t t1 = TMR_CTR;
    uart_print("  t0: "); uart_print_hex(t0);
    uart_print(", t1: "); uart_print_hex(t1);
    uart_print(", delta: "); uart_print_dec(t1 - t0); uart_print(" cycles\n");
    report_test("System Timer increments monotonically (t1 > t0)", (t1 > t0));

    // ------------------------------------------------------------------------
    // Subtest 3: Standard 8-bit Bidirectional GPIO Pin Driving
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 3] Testing Standard 8-bit Bidirectional GPIO...\n");
    // Configure all 8 pins as outputs
    GPIO_DIR = 0x000000FF;
    
    // Pattern 1: 0xA5
    GPIO_DATA = 0x000000A5;
    uint32_t read_a5 = GPIO_DATA & 0xFF;
    uart_print("  GPIO write: 0xA5, readback: "); uart_print_hex(read_a5); uart_print("\n");

    // Pattern 2: 0x5A
    GPIO_DATA = 0x0000005A;
    uint32_t read_5a = GPIO_DATA & 0xFF;
    uart_print("  GPIO write: 0x5A, readback: "); uart_print_hex(read_5a); uart_print("\n");

    report_test("GPIO 8-bit output write and readback (0xA5 & 0x5A)", (read_a5 == 0xA5 && read_5a == 0x5A));

    // ------------------------------------------------------------------------
    // Subtest 4: Heartbeat Monitor Status Verification
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 4] Testing Heartbeat Monitor Initial Status...\n");
    uint32_t hb_stat = HB_STATUS;
    uart_print("  HB_STATUS: "); uart_print_hex(hb_stat); uart_print("\n");
    report_test("Heartbeat Monitor is idle with no premature timeout", (hb_stat & 0x02) == 0);

    // ------------------------------------------------------------------------
    // Subtest 5: Power/Reset Sequencer Status Verification
    // ------------------------------------------------------------------------
    uart_print("\n[SUBTEST 5] Testing Reset Sequencer Initial Status...\n");
    uint32_t rst_stat = RST_STATUS;
    uart_print("  RST_STATUS: "); uart_print_hex(rst_stat); uart_print("\n");
    report_test("Reset Sequencer is idle (no reset pulse in progress)", (rst_stat & 0x01) == 0);

    // ------------------------------------------------------------------------
    // Summary & UVM Milestone Token
    // ------------------------------------------------------------------------
    test_summary();

    if (g_fail_count == 0) {
        uart_print("UVM_SANITY_PASS\n");
    } else {
        uart_print("UVM_SANITY_FAIL\n");
    }

    return (g_fail_count == 0) ? 0 : 1;
}
