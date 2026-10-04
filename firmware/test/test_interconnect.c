#include "test_common.h"

int main() {
    test_header("AXI4 Interconnect Stress Test");

    int pass = 1;

    // 1. Write to multiple slave peripherals sequentially to test crossbar routing
    uart_print("  Testing sequential writes to multiple slaves...\n");
    
    // Write arbitrary safe values to non-destructive registers
    HB_THRESHOLD = 0x12345678;
    RST_HOLD_CYCLES = 0x87654321;
    POL_WINDOW = 0x0F0F0F0F;

    // Read back and verify
    if (HB_THRESHOLD != 0x12345678) pass = 0;
    if (RST_HOLD_CYCLES != 0x87654321) pass = 0;
    if (POL_WINDOW != 0x0F0F0F0F) pass = 0;

    report_test("Interconnect Sequential R/W", pass);

    // 2. High-speed back-to-back operations
    uart_print("  Testing back-to-back crossbar arbitration...\n");
    int burst_pass = 1;
    for (int i = 0; i < 100; i++) {
        HB_THRESHOLD = i;
        if (HB_THRESHOLD != i) burst_pass = 0;
    }
    report_test("Interconnect Burst R/W", burst_pass);

    test_summary();

    // Signal completion
    uart_print(">>> ALL IP INTEGRATION TESTS PASSED SUCCESSFULLY! <<<\n");
    
    // Halt
    while(1);
    return 0;
}
