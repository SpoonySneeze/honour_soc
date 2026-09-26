#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: Recovery Policy & Circular Event Log IP (Native AXI4)");

    uart_print("[SUBTEST 1] Verifying Window & Threshold Configuration...\n");
    POL_WINDOW = 350000;
    uint32_t win_rb = POL_WINDOW;
    uart_print("  POL_WINDOW readback: "); uart_print_dec(win_rb); uart_print("\n");
    report_test("POL_WINDOW write/readback (350000 cycles)", (win_rb == 350000));

    POL_THRESHOLD = 5;
    uint32_t thresh_rb = POL_THRESHOLD & 0xFF;
    uart_print("  POL_THRESHOLD readback: "); uart_print_dec(thresh_rb); uart_print("\n");
    report_test("POL_THRESHOLD write/readback (5)", (thresh_rb == 5));

    uart_print("\n[SUBTEST 2] Clearing Lockout & Reading POL_STATUS...\n");
    POL_CTRL = 2; // clear_lockout
    delay(10);
    uint32_t pol_stat = POL_STATUS;
    uart_print("  POL_STATUS raw: "); uart_print_hex(pol_stat); uart_print("\n");
    report_test("POL_STATUS lockout flag is clear (Bit 0 == 0)", ((pol_stat & 1) == 0));

    uart_print("\n[SUBTEST 3] Logging Event 1 (Timestamp: 0x11223344)...\n");
    POL_EVENT_TS = 0x11223344;
    POL_CTRL = 1; // record_event
    delay(10);
    uint32_t cnt1 = LOG_COUNT;
    uart_print("  LOG_COUNT after Event 1: "); uart_print_dec(cnt1); uart_print("\n");
    report_test("LOG_COUNT updated to 1 after Event 1", (cnt1 == 1));

    LOG_READ_IDX = 0;
    uint32_t log0 = LOG_READ_DATA;
    uart_print("  Circular Log[0] readback: "); uart_print_hex(log0); uart_print("\n");
    report_test("Circular Log[0] matches staged timestamp 0x11223344", (log0 == 0x11223344));

    uart_print("\n[SUBTEST 4] Logging Event 2 (Timestamp: 0xAABBCCDD)...\n");
    POL_EVENT_TS = 0xAABBCCDD;
    POL_CTRL = 1; // record_event
    delay(10);
    uint32_t cnt2 = LOG_COUNT;
    uart_print("  LOG_COUNT after Event 2: "); uart_print_dec(cnt2); uart_print("\n");
    report_test("LOG_COUNT updated to 2 after Event 2", (cnt2 == 2));

    LOG_READ_IDX = 1;
    uint32_t log1 = LOG_READ_DATA;
    uart_print("  Circular Log[1] readback: "); uart_print_hex(log1); uart_print("\n");
    report_test("Circular Log[1] matches staged timestamp 0xAABBCCDD", (log1 == 0xAABBCCDD));

    uart_print("\n[SUBTEST 5] Logging Event 3 (Timestamp: 0x99887766)...\n");
    POL_EVENT_TS = 0x99887766;
    POL_CTRL = 1; // record_event
    delay(10);
    uint32_t cnt3 = LOG_COUNT;
    uart_print("  LOG_COUNT after Event 3: "); uart_print_dec(cnt3); uart_print("\n");
    report_test("LOG_COUNT updated to 3 after Event 3", (cnt3 == 3));

    LOG_READ_IDX = 2;
    uint32_t log2 = LOG_READ_DATA;
    uart_print("  Circular Log[2] readback: "); uart_print_hex(log2); uart_print("\n");
    report_test("Circular Log[2] matches staged timestamp 0x99887766", (log2 == 0x99887766));

    test_summary();
    return 0;
}
