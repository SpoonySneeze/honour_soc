#include "test_common.h"

int main(void) {
    test_header("TEST SUITE: System Timer Peripheral (Native AXI4)");

    uart_print("[SUBTEST 1] Initial Counter Read...\n");
    uint32_t t0 = TMR_CTR;
    uart_print("  TMR_CTR initial value: "); uart_print_hex(t0); uart_print("\n");
    report_test("Timer counter is non-zero after boot", (t0 > 0));

    uart_print("\n[SUBTEST 2] Monotonic Counter Progression...\n");
    uint32_t t1 = TMR_CTR;
    delay(100);
    uint32_t t2 = TMR_CTR;
    uart_print("  t1: "); uart_print_hex(t1);
    uart_print(", t2: "); uart_print_hex(t2);
    uart_print(", delta: "); uart_print_dec(t2 - t1); uart_print(" cycles\n");
    report_test("Timer monotonically increments over time (t2 > t1)", (t2 > t1));

    uart_print("\n[SUBTEST 3] Multiple Sequential Readings...\n");
    uint32_t samples[5];
    for (int i = 0; i < 5; i++) {
        samples[i] = TMR_CTR;
        delay(30);
    }
    int monotonic_chain = 1;
    for (int i = 1; i < 5; i++) {
        uart_print("  Sample "); uart_print_dec(i); uart_print(": "); uart_print_hex(samples[i]); uart_print("\n");
        if (samples[i] <= samples[i - 1]) {
            monotonic_chain = 0;
        }
    }
    report_test("Sequential multi-sample progression is strictly increasing", monotonic_chain);

    uart_print("\n[SUBTEST 4] Precision Delay Verification...\n");
    uint32_t start_time = TMR_CTR;
    delay(500);
    uint32_t end_time = TMR_CTR;
    uint32_t elapsed = end_time - start_time;
    uart_print("  Elapsed cycles for delay(500): "); uart_print_dec(elapsed); uart_print("\n");
    report_test("Measured delay elapsed cycles in expected window (> 1000 cycles)", (elapsed > 1000));

    test_summary();
    return 0;
}
