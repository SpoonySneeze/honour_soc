#ifndef TEST_COMMON_H
#define TEST_COMMON_H

#include <stdint.h>

// ============================================================================
// BMC SoC Base Addresses (Pure AXI4 Bus Hierarchy)
// ============================================================================
#define UART_BASE 0x00020000
#define TMR_BASE  0x00020100
#define GPIO_BASE 0x00020200
#define HB_BASE   0x00020300
#define RST_BASE  0x00020400
#define POL_BASE  0x00020500
#define VGA_BASE  0x00020600

// ============================================================================
// Peripheral Register Maps
// ============================================================================
// 1. UART (16550 Compatible)
#define UART_RBR *(volatile uint32_t*)(UART_BASE + 0x00)
#define UART_THR *(volatile uint32_t*)(UART_BASE + 0x00)
#define UART_IER *(volatile uint32_t*)(UART_BASE + 0x04)
#define UART_IIR *(volatile uint32_t*)(UART_BASE + 0x08)
#define UART_FCR *(volatile uint32_t*)(UART_BASE + 0x08)
#define UART_LCR *(volatile uint32_t*)(UART_BASE + 0x0C)
#define UART_MCR *(volatile uint32_t*)(UART_BASE + 0x10)
#define UART_LSR *(volatile uint32_t*)(UART_BASE + 0x14)
#define UART_MSR *(volatile uint32_t*)(UART_BASE + 0x18)
#define UART_SCR *(volatile uint32_t*)(UART_BASE + 0x1C)
#define UART_LSR_THRE 0x20

// 2. Timer (32-bit hardware cycle counter)
#define TMR_CTR *(volatile uint32_t*)(TMR_BASE + 0x00)

// 3. GPIO Pin Status
#define GPIO_STAT *(volatile uint32_t*)(GPIO_BASE + 0x00)

// 4. Heartbeat Monitor
#define HB_CTRL      *(volatile uint32_t*)(HB_BASE + 0x00)
#define HB_THRESHOLD *(volatile uint32_t*)(HB_BASE + 0x04)
#define HB_STATUS    *(volatile uint32_t*)(HB_BASE + 0x08)
#define HB_ELAPSED   *(volatile uint32_t*)(HB_BASE + 0x0C)

// 5. Power/Reset Sequencer
#define RST_CTRL        *(volatile uint32_t*)(RST_BASE + 0x00)
#define RST_HOLD_CYCLES *(volatile uint32_t*)(RST_BASE + 0x04)
#define RST_STATUS      *(volatile uint32_t*)(RST_BASE + 0x08)

// 6. Recovery Policy & Event Log
#define POL_CTRL      *(volatile uint32_t*)(POL_BASE + 0x00)
#define POL_WINDOW    *(volatile uint32_t*)(POL_BASE + 0x04)
#define POL_THRESHOLD *(volatile uint32_t*)(POL_BASE + 0x08)
#define POL_STATUS    *(volatile uint32_t*)(POL_BASE + 0x0C)
#define POL_EVENT_TS  *(volatile uint32_t*)(POL_BASE + 0x10)
#define LOG_READ_IDX  *(volatile uint32_t*)(POL_BASE + 0x14)
#define LOG_READ_DATA *(volatile uint32_t*)(POL_BASE + 0x18)
#define LOG_COUNT     *(volatile uint32_t*)(POL_BASE + 0x1C)

// 7. VGA Controller
#define VGA_CTRL        *(volatile uint32_t*)(VGA_BASE + 0x00)
#define VGA_STATUS      *(volatile uint32_t*)(VGA_BASE + 0x04)
#define VGA_TEXT_BUFFER ((volatile uint32_t*)(VGA_BASE + 0x08))

// ============================================================================
// Test Framework Accounting
// ============================================================================
static uint32_t g_pass_count = 0;
static uint32_t g_fail_count = 0;

// ============================================================================
// UART Driver Functions
// ============================================================================
static inline void uart_putc(char c) {
    while ((UART_LSR & UART_LSR_THRE) == 0);
    UART_THR = (uint32_t)c;
}

static inline void uart_print(const char* str) {
    while (*str) {
        if (*str == '\n') {
            uart_putc('\r');
        }
        uart_putc(*str++);
    }
}

static inline void uart_print_hex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    uart_print("0x");
    for (int i = 7; i >= 0; i--) {
        uint32_t nibble = (val >> (i * 4)) & 0xF;
        uart_putc(hex_chars[nibble]);
    }
}

static inline void uart_print_dec(uint32_t val) {
    if (val == 0) {
        uart_putc('0');
        return;
    }
    char buf[12];
    int idx = 0;
    while (val > 0) {
        buf[idx++] = (char)('0' + (val % 10));
        val /= 10;
    }
    for (int i = idx - 1; i >= 0; i--) {
        uart_putc(buf[i]);
    }
}

static inline void delay(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++) {
        __asm__ volatile("nop");
    }
}

// ============================================================================
// Assertion & Reporting
// ============================================================================
static inline void report_test(const char* test_name, int pass) {
    if (pass) {
        uart_print("  [PASS] ");
        uart_print(test_name);
        uart_print("\n");
        g_pass_count++;
    } else {
        uart_print("  [FAIL] ");
        uart_print(test_name);
        uart_print("\n");
        g_fail_count++;
    }
}

static inline void test_header(const char* title) {
    uart_print("\n");
    uart_print("====================================================\n");
    uart_print("  ");
    uart_print(title);
    uart_print("\n");
    uart_print("  Processor Core: VeeR EL2 (RV32IMC Bare-Metal)\n");
    uart_print("  Bus Architecture: 100% Pure Native AXI4\n");
    uart_print("====================================================\n\n");
}

static inline void test_summary(void) {
    uart_print("\n====================================================\n");
    uart_print("  TEST SUMMARY REPORT\n");
    uart_print("====================================================\n");
    uart_print("  Total Passed: "); uart_print_dec(g_pass_count); uart_print("\n");
    uart_print("  Total Failed: "); uart_print_dec(g_fail_count); uart_print("\n");

    if (g_fail_count == 0) {
        uart_print("\n>>> ALL TESTS PASSED SUCCESSFULLY! <<<\n\n");
    } else {
        uart_print("\n*** SOME TESTS FAILED! ***\n\n");
    }
}

#endif // TEST_COMMON_H
