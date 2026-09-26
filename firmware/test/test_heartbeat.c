#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: Heartbeat Monitor Watchdog IP (Native AXI4)");

    uart_print("[SUBTEST 1] Initial Status Check...\n");
    uint32_t status_init = HB_STATUS;
    uart_print("  Initial HB_STATUS: "); uart_print_hex(status_init); uart_print("\n");
    report_test("HB_STATUS unresponsive flag (Bit 0) is initially 0", ((status_init & 1) == 0));

    uart_print("\n[SUBTEST 2] Verifying Threshold Configuration (HB_THRESHOLD)...\n");
    HB_THRESHOLD = 25000;
    uint32_t thresh1 = HB_THRESHOLD;
    uart_print("  HB_THRESHOLD Pattern 1 (25000): "); uart_print_dec(thresh1); uart_print("\n");
    report_test("HB_THRESHOLD write/readback (25000 cycles)", (thresh1 == 25000));

    HB_THRESHOLD = 60000;
    uint32_t thresh2 = HB_THRESHOLD;
    uart_print("  HB_THRESHOLD Pattern 2 (60000): "); uart_print_dec(thresh2); uart_print("\n");
    report_test("HB_THRESHOLD write/readback (60000 cycles)", (thresh2 == 60000));

    uart_print("\n[SUBTEST 3] Enabling Monitor & Checking Elapsed Timer...\n");
    HB_CTRL = 1; // Enable
    delay(50);
    uint32_t elapsed1 = HB_ELAPSED;
    delay(50);
    uint32_t elapsed2 = HB_ELAPSED;
    uart_print("  HB_ELAPSED sample 1: "); uart_print_dec(elapsed1); uart_print("\n");
    uart_print("  HB_ELAPSED sample 2: "); uart_print_dec(elapsed2); uart_print("\n");
    report_test("HB_ELAPSED counter is running (non-zero sample observed)", (elapsed1 > 0 || elapsed2 > 0));

    uart_print("\n[SUBTEST 4] Watchdog Petting / Servicing Command...\n");
    HB_CTRL = 3; // Bit 0: enable, Bit 1: clear_flag
    delay(10);
    uint32_t status_after_pet = HB_STATUS;
    uart_print("  HB_STATUS after pet: "); uart_print_hex(status_after_pet); uart_print("\n");
    report_test("Watchdog serviced cleanly; unresponsive flag remains 0", ((status_after_pet & 1) == 0));

    uart_print("\n[SUBTEST 5] Disabling Heartbeat Monitor...\n");
    HB_CTRL = 0; // Disable
    delay(10);
    uint32_t ctrl_rb = HB_CTRL;
    report_test("HB_CTRL disabled (readback Bit 0 is 0)", ((ctrl_rb & 1) == 0));

    test_summary();
    return 0;
}
