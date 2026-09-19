#include <stdint.h>

// Peripheral Base Addresses
#define UART_BASE 0x00020000
#define HB_BASE   0x00020300
#define RST_BASE  0x00020400
#define POL_BASE  0x00020500
#define VGA_BASE  0x00020600

// UART Registers (16550 compatible)
#define UART_THR *(volatile uint32_t*)(UART_BASE + 0x00) // Transmit Holding Register
#define UART_LSR *(volatile uint32_t*)(UART_BASE + 0x14) // Line Status Register
#define UART_LSR_THRE 0x20 // Transmit Holding Register Empty

// Heartbeat Registers
#define HB_CTRL      *(volatile uint32_t*)(HB_BASE + 0x00)
#define HB_THRESHOLD *(volatile uint32_t*)(HB_BASE + 0x04)

// Recovery Policy Registers
#define POL_WINDOW    *(volatile uint32_t*)(POL_BASE + 0x04)
#define POL_THRESHOLD *(volatile uint32_t*)(POL_BASE + 0x08)

// VGA Registers
#define VGA_CTRL *(volatile uint32_t*)(VGA_BASE + 0x00)
#define VGA_TEXT_BUFFER ((volatile uint32_t*)(VGA_BASE + 0x08))

// Simple blocking UART print
void uart_putc(char c) {
    // Wait until THR is empty
    // (Note: in a real 16550, we wait for bit 5 of LSR. 
    // We'll just assume it's fast enough or check bit 5).
    // while ((UART_LSR & UART_LSR_THRE) == 0);
    UART_THR = c;
}

void uart_print(const char* str) {
    while (*str) {
        uart_putc(*str++);
    }
}

// Simple VGA Dashboard print
void vga_print(int row, int col, const char* str) {
    // Pack 4 characters per 32-bit word (MSB first)
    // 30 words total (120 chars) = 3 rows of 40 chars
    // This is a simplified direct write
    int char_idx = (row * 40) + col;
    while (*str && char_idx < 120) {
        int word_idx = char_idx / 4;
        int byte_sel = 3 - (char_idx % 4);
        
        uint32_t word = VGA_TEXT_BUFFER[word_idx];
        uint32_t mask = ~(0xFF << (byte_sel * 8));
        word = (word & mask) | (((uint32_t)*str) << (byte_sel * 8));
        VGA_TEXT_BUFFER[word_idx] = word;
        
        str++;
        char_idx++;
    }
}

// Simple delay loop
void delay(uint32_t count) {
    for (volatile uint32_t i = 0; i < count; i++) {
        __asm__ volatile("nop");
    }
}

int main(void) {
    // 1. Initialize Heartbeat Monitor (Threshold = 5000 cycles)
    HB_THRESHOLD = 5000;
    HB_CTRL = 1; // Enable
    
    // 2. Initialize Recovery Policy (Window = 100000 cycles, Max Resets = 3)
    POL_WINDOW = 100000;
    POL_THRESHOLD = 3;
    
    // 3. Initialize VGA Controller
    VGA_CTRL = 1; // Enable Display
    vga_print(0, 0, "BMC SoC Online - VeeR EL2 Booted!");
    vga_print(1, 0, "Monitoring System Heartbeat...");
    
    // 4. Print to UART
    uart_print("\r\n=================================\r\n");
    uart_print("  VeeR EL2 SoC Boot Successful!\r\n");
    uart_print("=================================\r\n");

    // 5. Main Control Loop
    uint32_t counter = 0;
    while (1) {
        // Feed the Heartbeat Monitor to prevent system reset
        HB_CTRL = 3; // Clear flag and Enable
        
        // Print alive message every ~loop cycles
        if (counter % 10000 == 0) {
            uart_print("System Alive...\r\n");
        }
        
        counter++;
        delay(100);
    }
    
    return 0;
}
