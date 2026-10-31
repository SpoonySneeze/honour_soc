#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: Power/Reset Sequencer IP (Native AXI4)");

    uart_print("[SUBTEST 1] Power-On Default Hold Cycles...\n");
    uint32_t rst_default = RST_HOLD_CYCLES;
    uart_print("  Default RST_HOLD_CYCLES: "); uart_print_dec(rst_default); uart_print("\n");
    report_test("RST_HOLD_CYCLES reset value is 100 clock cycles", (rst_default == 100));

    uart_print("\n[SUBTEST 2] Modifying RST_HOLD_CYCLES Configuration...\n");
    RST_HOLD_CYCLES = 45;
    uint32_t hold1 = RST_HOLD_CYCLES;
    uart_print("  RST_HOLD_CYCLES test value 1: "); uart_print_dec(hold1); uart_print("\n");
    report_test("RST_HOLD_CYCLES write/readback (45 cycles)", (hold1 == 45));

    RST_HOLD_CYCLES = 250;
    uint32_t hold2 = RST_HOLD_CYCLES;
    uart_print("  RST_HOLD_CYCLES test value 2: "); uart_print_dec(hold2); uart_print("\n");
    report_test("RST_HOLD_CYCLES write/readback (250 cycles)", (hold2 == 250));

    // Restore standard hold cycles
    RST_HOLD_CYCLES = 100;
    report_test("RST_HOLD_CYCLES restored to default 100", (RST_HOLD_CYCLES == 100));

    uart_print("\n[SUBTEST 3] Reading RST_STATUS Register...\n");
    uint32_t status = RST_STATUS;
    uart_print("  RST_STATUS raw: "); uart_print_hex(status); uart_print("\n");
    int in_prog = status & 1;
    report_test("RST_STATUS indicates sequencer idle (in_progress == 0)", (in_prog == 0));

    uart_print("\n[SUBTEST 4] Triggering Reset Sequence via RST_CTRL...\n");
    RST_HOLD_CYCLES = 500; // Extend duration to guarantee sampling in_progress
    RST_CTRL = 1;          // Trigger reset sequence
    uint32_t in_prog_status = RST_STATUS;
    uart_print("  RST_STATUS immediately after trigger: "); uart_print_hex(in_prog_status); uart_print("\n");
    int in_progress = (in_prog_status & 1) != 0;
    report_test("RST_STATUS indicates sequence in progress (Bit 0 == 1)", in_progress);

    delay(600);   // Wait for 500 hold cycles + margin
    uint32_t post_status = RST_STATUS;
    uart_print("  RST_STATUS after sequence complete: "); uart_print_hex(post_status); uart_print("\n");
    int complete = ((post_status & 2) != 0) && ((post_status & 1) == 0);
    report_test("Reset sequence marked complete (Bit 1 == 1, Bit 0 == 0)", complete);
    RST_HOLD_CYCLES = 100; // Restore default

    test_summary();
    return 0;
}
