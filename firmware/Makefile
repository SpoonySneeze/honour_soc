CROSS_COMPILE ?= riscv64-unknown-elf-
CC      = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
OBJDUMP = $(CROSS_COMPILE)objdump

CFLAGS = -march=rv32imc_zicsr -mabi=ilp32 -mcmodel=medany -Wall -O2 -ffreestanding -nostdlib
LDFLAGS = -T link.ld -nostartfiles -Wl,--no-relax

all: firmware.hex firmware.dump

firmware.elf: start.S main.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

# Generate verilog hex file (32-bit words)
firmware.hex: firmware.elf
	$(OBJCOPY) --change-addresses -0x80000000 -O verilog $< $@
	cp $@ ../

# Generate assembly dump for debugging
firmware.dump: firmware.elf
	$(OBJDUMP) -D $< > $@

clean:
	rm -f *.elf *.hex *.dump
