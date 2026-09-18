# AES AXI CSR Wrapper: Architecture and End-to-End Implementation Plan

## 1. Objective

Integrate the existing AES-128 RTL core behind an AXI4-Lite register
interface.

The resulting block exposes the AES functionality as an AXI slave. An
AXI master writes the AES key and input data into CSR registers, issues
a start command, waits for completion through a status register, and
reads the resulting ciphertext or plaintext.

The design must preserve the timing semantics of the existing AES IP:

-   Encryption core `ld` is a one-clock-cycle load pulse.
-   Encryption core `done` is a one-clock-cycle completion pulse.
-   Inverse/decryption core has separate `kld` and `ld` pulses.
-   Inverse/decryption core produces `kdone` and `done` pulses.
-   Key and input data must remain stable while the AES operation is
    performed.

------------------------------------------------------------------------

# 2. Existing AES Core Interface

## 2.1 AES Cipher Core

The existing encryption core provides:

  Signal         Width Direction   Description
  ------------ ------- ----------- ------------------------------
  `clk`              1 Input       Core clock
  `rst`              1 Input       Active-low synchronous reset
  `ld`               1 Input       One-cycle load pulse
  `done`             1 Output      One-cycle completion pulse
  `key`            128 Input       AES-128 key
  `text_in`        128 Input       Input block
  `text_out`       128 Output      Output block

The documented interface timing shows `ld` asserted for one clock cycle
while `key` and `text_in` are valid. The core subsequently asserts
`done` for one clock cycle when `text_out` becomes valid.

## 2.2 AES Inverse Cipher Core

The inverse core provides:

  Signal         Width Direction   Description
  ------------ ------- ----------- ------------------------------
  `clk`              1 Input       Core clock
  `rst`              1 Input       Active-low synchronous reset
  `kld`              1 Input       Key-load pulse
  `kdone`            1 Output      Key expansion completion
  `ld`               1 Input       Text-load pulse
  `done`             1 Output      Text operation completion
  `key`            128 Input       AES-128 key
  `text_in`        128 Input       Input block
  `text_out`       128 Output      Output block

The inverse core therefore requires two phases:

1.  Load the key using `kld`.
2.  Wait for `kdone`.
3.  Load the input text using `ld`.
4.  Wait for `done`.

The CSR wrapper should hide this implementation detail from software.

------------------------------------------------------------------------

# 3. High-Level Architecture

The complete architecture is:

``` text
                         AXI4-Lite
                            |
                            |
                     +------v------+
                     | AXI Master  |
                     | Testbench / |
                     | CPU / SoC   |
                     +------+------+
                            |
                    AXI Read / Write
                            |
                     +------v------+
                     | AES AXI     |
                     | Slave / CSR |
                     | Wrapper     |
                     +------+------+
                            |
             +--------------+--------------+
             |              |              |
          key_reg       text_reg       control
             |              |              |
             +--------------+--------------+
                            |
                     +------v------+
                     | AES Control |
                     | FSM         |
                     +------+------+
                            |
                  +---------+---------+
                  |                   |
             Encryption           Decryption
                  |                   |
                  v                   v
             +---------+       +-------------+
             | AES     |       | AES Inverse |
             | Cipher  |       | Cipher      |
             +----+----+       +------+------+
                  |                   |
                done                kdone/done
                  |                   |
                  +---------+---------+
                            |
                     +------v------+
                     | Output      |
                     | Registers   |
                     +-------------+
```

The AES block is an **AXI slave** because software or an AXI master
accesses it through memory-mapped registers.

The AXI master is responsible for generating AXI transactions. During
standalone verification this can be an AXI master BFM in the testbench.
In a complete SoC it can instead be a processor or another bus master.

------------------------------------------------------------------------

# 4. CSR Architecture

The CSR interface is based on a 32-bit AXI data width.

The 128-bit AES key, input block, and output block are therefore exposed
as four 32-bit registers each.

## 4.1 Register Map

    Offset Register    Access  Description
  -------- ---------- -------- -------------------------------------
    `0x00` `CTRL`        RW    Operation control and start command
    `0x04` `STATUS`      RW    Operation status; `DONE` is W1C
    `0x08` `KEY0`        RW    Key `[31:0]`
    `0x0C` `KEY1`        RW    Key `[63:32]`
    `0x10` `KEY2`        RW    Key `[95:64]`
    `0x14` `KEY3`        RW    Key `[127:96]`
    `0x18` `TEXT0`       RW    Input `[31:0]`
    `0x1C` `TEXT1`       RW    Input `[63:32]`
    `0x20` `TEXT2`       RW    Input `[95:64]`
    `0x24` `TEXT3`       RW    Input `[127:96]`
    `0x28` `OUT0`        RO    Output `[31:0]`
    `0x2C` `OUT1`        RO    Output `[63:32]`
    `0x30` `OUT2`        RO    Output `[95:64]`
    `0x34` `OUT3`        RO    Output `[127:96]`

------------------------------------------------------------------------

# 5. CTRL Register

Suggested layout:

``` text
31                         2  1       0
+---------------------------+--+-------+
|         Reserved          | D| START |
+---------------------------+--+-------+
```

       Bit Name         Access  Description
  -------- ----------- -------- ------------------------------------
       `0` `START`        W     Launch AES operation
       `1` `DECRYPT`      RW    `0` = encryption, `1` = decryption
    `31:2` Reserved       \-    Reserved

`START` is treated as a command/event, not as a stored level.

A write to `CTRL` containing `START=1` generates the internal operation
request.

Therefore software does not directly control the AES `ld` signal.

------------------------------------------------------------------------

# 6. STATUS Register

Suggested layout:

``` text
31                         2   1      0
+---------------------------+---+------+
|         Reserved          |BUSY| DONE|
+---------------------------+---+------+
```

       Bit Name        Access  Description
  -------- ---------- -------- ---------------------------
       `0` `DONE`      RW/W1C  Operation completed
       `1` `BUSY`        RO    AES operation in progress
    `31:2` Reserved      \-    Reserved

## DONE behavior

The AES core's physical `done` output remains a one-cycle pulse.

The CSR wrapper converts that pulse into a sticky status bit:

``` text
AES done pulse
      |
      v
done_status <= 1
```

`STATUS.DONE` is **not clear-on-read**.

It is cleared using write-one-to-clear semantics:

``` text
write STATUS with bit 0 = 1
        |
        v
done_status <= 0
```

This prevents an unrelated read from destroying the completion
indication.

## BUSY behavior

`BUSY` is generated by the control FSM.

Typical behavior:

``` text
IDLE       -> BUSY = 0
START      -> BUSY = 1
AES done   -> BUSY = 0
```

A new `START` should normally be rejected or ignored while `BUSY=1`.

------------------------------------------------------------------------

# 7. Load Signal Architecture

The AES core's `ld` signal is a pulse and should remain a pulse.

There should **not** be an `LD` CSR bit.

Instead:

``` text
AXI write to KEY/TEXT registers
        |
        v
CSR staging registers

AXI write CTRL.START
        |
        v
Control FSM
        |
        v
Generate one-cycle AES ld pulse
```

The key and text registers therefore act as staging registers.

They are loaded first and remain stable during the AES operation.

The actual AES `ld` pulse is generated only by the control FSM.

This preserves the original IP timing contract while presenting a clean
software interface.

------------------------------------------------------------------------

# 8. Encryption Control Flow

For encryption:

``` text
IDLE
 |
 | AXI writes KEY registers
 | AXI writes TEXT registers
 |
 | AXI write CTRL.START
 v
LOAD_ENC
 |
 | ld = 1 for one cycle
 v
WAIT_DONE
 |
 | wait for AES done
 v
CAPTURE_OUTPUT
 |
 | output register <= text_out
 | DONE <= 1
 | BUSY <= 0
 v
IDLE
```

The encryption operation therefore requires:

1.  Write key.
2.  Write input block.
3.  Write `START`.
4.  Wait for `STATUS.DONE`.
5.  Read output registers.
6.  Clear `STATUS.DONE` using W1C.

------------------------------------------------------------------------

# 9. Decryption Control Flow

The inverse core requires key expansion before text processing.

``` text
IDLE
 |
 | AXI writes KEY registers
 | AXI writes TEXT registers
 |
 | AXI write CTRL.START + DECRYPT
 v
LOAD_DEC_KEY
 |
 | kld = 1 for one cycle
 v
WAIT_KDONE
 |
 | wait for kdone
 v
LOAD_DEC_TEXT
 |
 | ld = 1 for one cycle
 v
WAIT_DONE
 |
 | wait for done
 v
CAPTURE_OUTPUT
 |
 | output register <= text_out
 | DONE <= 1
 | BUSY <= 0
 v
IDLE
```

Software does not need to know about `kld` or `kdone`.

------------------------------------------------------------------------

# 10. Control FSM

Suggested states:

``` text
IDLE
ENC_LOAD
ENC_WAIT_DONE
DEC_KEY_LOAD
DEC_WAIT_KDONE
DEC_TEXT_LOAD
DEC_WAIT_DONE
CAPTURE
```

State responsibilities:

### `IDLE`

-   `BUSY=0`
-   Wait for `START`.

### `ENC_LOAD`

-   Assert encryption `ld` for exactly one clock.
-   Transition to `ENC_WAIT_DONE`.

### `ENC_WAIT_DONE`

-   Wait for encryption `done`.
-   Transition to `CAPTURE`.

### `DEC_KEY_LOAD`

-   Assert inverse-core `kld` for exactly one clock.
-   Transition to `DEC_WAIT_KDONE`.

### `DEC_WAIT_KDONE`

-   Wait for inverse-core `kdone`.

### `DEC_TEXT_LOAD`

-   Assert inverse-core `ld` for exactly one clock.
-   Transition to `DEC_WAIT_DONE`.

### `DEC_WAIT_DONE`

-   Wait for inverse-core `done`.
-   Transition to `CAPTURE`.

### `CAPTURE`

-   Latch `text_out`.
-   Set sticky `DONE`.
-   Clear `BUSY`.
-   Return to `IDLE`.

------------------------------------------------------------------------

# 11. AXI Slave Implementation

The AES CSR wrapper should implement an AXI4-Lite slave.

For a 32-bit data bus:

``` text
AXI slave signals

Write address:
AWADDR
AWVALID
AWREADY

Write data:
WDATA
WSTRB
WVALID
WREADY

Write response:
BRESP
BVALID
BREADY

Read address:
ARADDR
ARVALID
ARREADY

Read data:
RDATA
RRESP
RVALID
RREADY
```

The CSR block decodes the AXI address and converts successful AXI
transactions into register accesses.

Conceptually:

``` text
AXI AW/W
   |
   v
+--------+
| AXI    |
| Write  |
| Logic  |
+---+----+
    |
    v
CSR write enable
CSR address
CSR write data
CSR byte enables
    |
    v
+-----------+
| CSR       |
| Decoder   |
+-----------+
```

For reads:

``` text
AXI AR
  |
  v
CSR address
  |
  v
+-----------+
| CSR Read  |
| Decoder   |
+-----+-----+
      |
      v
   RDATA
```

The AXI protocol logic and AES control logic should remain separate.

------------------------------------------------------------------------

# 12. AXI Master for Verification

A dedicated AXI master BFM should be used in the simulation testbench.

The master performs:

``` text
AXI WRITE
    |
    +-- KEY0
    +-- KEY1
    +-- KEY2
    +-- KEY3
    |
    +-- TEXT0
    +-- TEXT1
    +-- TEXT2
    +-- TEXT3
    |
    +-- CTRL.START
    |
    v
AXI READ STATUS
    |
    | wait until DONE=1
    v
AXI READ OUT0..OUT3
```

The BFM should implement reusable tasks such as:

``` verilog
axi_write(addr, data);
axi_read(addr, data);
aes_write_key(key);
aes_write_text(text);
aes_start(decrypt);
aes_wait_done();
aes_read_output(data);
```

This makes the testbench test the **actual AXI interface**, rather than
bypassing the CSR wrapper and directly toggling AES signals.

------------------------------------------------------------------------

# 13. End-to-End Data Flow

## Encryption

``` text
                 AXI MASTER
                     |
                     | AXI writes
                     v
             +---------------+
             | AXI4-Lite     |
             | Slave         |
             +-------+-------+
                     |
          +----------+----------+
          |                     |
          v                     v
     key_reg[127:0]       text_reg[127:0]
          |                     |
          +----------+----------+
                     |
                     v
                AES Cipher
                     |
                   ld pulse
                     |
                     v
                  done
                     |
                     v
              output_reg[127:0]
                     |
                     v
                 AXI READ
                     |
                     v
                 AXI MASTER
```

## Decryption

``` text
                 AXI MASTER
                     |
                     v
             +---------------+
             | AXI4-Lite     |
             | Slave / CSR   |
             +-------+-------+
                     |
             key_reg / text_reg
                     |
                     v
                Control FSM
                     |
                  kld pulse
                     |
                     v
                  kdone
                     |
                  ld pulse
                     |
                     v
             AES Inverse Core
                     |
                   done
                     |
                     v
                output_reg
                     |
                     v
                 AXI READ
```

------------------------------------------------------------------------

# 14. AXI Master and AES AXI Slave Testbench

The standalone verification environment should contain:

``` text
tb_top
 |
 +-- clock/reset generation
 |
 +-- AXI master BFM
 |
 +-- AES AXI slave DUT
       |
       +-- AXI slave interface
       |
       +-- CSR registers
       |
       +-- control FSM
       |
       +-- AES cipher core
       |
       +-- AES inverse cipher core
```

The AXI master BFM is therefore the initiator.

The AES wrapper is the target/slave.

This is a better verification structure than directly instantiating the
AES core and driving `ld`, `key`, and `text_in` from the testbench
because it verifies the complete software-visible interface.

------------------------------------------------------------------------

# 15. End-to-End Implementation Plan

## Phase 1: Freeze the AES IP interface

1.  Verify the existing AES cipher module ports.
2.  Verify the existing inverse cipher module ports.
3.  Confirm reset polarity and reset behavior.
4.  Confirm `ld`, `done`, `kld`, and `kdone` timing.
5.  Run the existing RTL testbench independently.
6.  Record a known-good AES-128 test vector.

Deliverable:

``` text
Known-good AES RTL core
```

------------------------------------------------------------------------

## Phase 2: Define the CSR specification

1.  Implement the register map.
2.  Define 32-bit register packing of the 128-bit key.
3.  Define 32-bit register packing of the 128-bit input.
4.  Define output register packing.
5.  Define `CTRL.START`.
6.  Define `CTRL.DECRYPT`.
7.  Define `STATUS.BUSY`.
8.  Define sticky `STATUS.DONE`.
9.  Define W1C behavior for `DONE`.
10. Define behavior of writes while `BUSY=1`.

Deliverable:

``` text
AES CSR specification
```

------------------------------------------------------------------------

## Phase 3: Implement CSR registers

Create:

``` text
aes_csr_regs.v
```

Implement:

-   key registers
-   text input registers
-   output registers
-   CTRL register
-   STATUS register
-   AXI read/write register decoding

At this stage, the AES core does not need to be connected yet.

Verify register read/write behavior independently.

------------------------------------------------------------------------

## Phase 4: Implement AXI4-Lite slave

Create:

``` text
aes_axi_slave.v
```

Implement:

-   AXI write address channel
-   AXI write data channel
-   AXI write response
-   AXI read address channel
-   AXI read response
-   address decoding
-   byte write strobes
-   AXI handshake correctness

The AXI interface should generate a clean internal CSR interface:

``` text
csr_wr_en
csr_rd_en
csr_addr
csr_wdata
csr_wstrb
csr_rdata
```

Keeping this interface separate from the AES logic makes later
integration substantially easier.

------------------------------------------------------------------------

## Phase 5: Implement AES control FSM

Create:

``` text
aes_control_fsm.v
```

Implement:

``` text
IDLE
ENC_LOAD
ENC_WAIT_DONE
DEC_KEY_LOAD
DEC_WAIT_KDONE
DEC_TEXT_LOAD
DEC_WAIT_DONE
CAPTURE
```

Generate:

``` text
cipher_ld
inverse_kld
inverse_ld
```

and consume:

``` text
cipher_done
inverse_kdone
inverse_done
```

Generate:

``` text
busy
done_event
```

------------------------------------------------------------------------

## Phase 6: Integrate the AES cores

Create a top-level wrapper:

``` text
aes_axi.v
```

Structure:

``` text
aes_axi
 |
 +-- aes_axi_slave
 |
 +-- aes_csr_regs
 |
 +-- aes_control_fsm
 |
 +-- aes_cipher_top
 |
 +-- aes_inv_cipher_top
```

Connect:

``` text
key_reg  -> AES key
text_reg -> AES text_in
AES text_out -> output_reg
```

The wrapper controls which core is active.

------------------------------------------------------------------------

# 16. Phase 7: AXI Master BFM

Create:

``` text
tb_axi_master.v
```

Implement reusable AXI transactions.

Minimum tasks:

``` verilog
axi_write();
axi_read();

aes_write_key();
aes_write_text();

aes_start_encrypt();
aes_start_decrypt();

aes_wait_done();
aes_read_output();
```

The BFM should check AXI handshake signals rather than assuming
zero-latency transactions.

------------------------------------------------------------------------

# 17. Phase 8: Verification

## Test 1: CSR reset

Check:

``` text
KEY = 0
TEXT = 0
OUTPUT = 0
BUSY = 0
DONE = 0
```

## Test 2: CSR read/write

Write and read every writable register.

Verify that:

-   address decoding is correct
-   register contents are preserved
-   byte strobes work
-   read-only registers cannot be modified

## Test 3: Encryption

Use a known AES-128 vector.

Verify:

``` text
key
plaintext
     |
     v
AES
     |
     v
ciphertext
```

## Test 4: Decryption

Feed the encryption result back into the inverse path.

Verify:

``` text
ciphertext
     |
     v
AES inverse
     |
     v
original plaintext
```

## Test 5: DONE behavior

Verify:

``` text
AES done pulse
       |
       v
STATUS.DONE = 1

STATUS read
       |
       v
STATUS.DONE remains 1

write STATUS.DONE = 1
       |
       v
STATUS.DONE = 0
```

## Test 6: BUSY behavior

Verify:

``` text
START
 |
 v
BUSY = 1
 |
 v
operation
 |
 v
DONE
 |
 +--> BUSY = 0
```

Attempting another `START` while busy should follow the defined policy.
The preferred initial behavior is to ignore the new start request.

## Test 7: Back-to-back operations

Verify multiple encryption operations without reset.

Then verify:

``` text
encrypt -> decrypt -> encrypt -> decrypt
```

------------------------------------------------------------------------

# 18. Phase 9: VCS + Verdi

Compile the complete hierarchy using VCS with debug information:

``` text
-full64
-sverilog
-debug_access+all
-kdb
```

Generate FSDB from the testbench.

Useful signals to inspect in Verdi:

``` text
AXI:
  AWVALID
  AWREADY
  WVALID
  WREADY
  BVALID
  BREADY
  ARVALID
  ARREADY
  RVALID
  RREADY

CSR:
  key_reg
  text_reg
  output_reg
  ctrl
  status

Control:
  state
  busy
  done_status
  cipher_ld
  inverse_kld
  inverse_ld

AES:
  key
  text_in
  text_out
  ld
  done
  kld
  kdone
```

The most important waveform check is that the CSR wrapper generates
**one-cycle load pulses**.

------------------------------------------------------------------------

# 19. Phase 10: Synthesis and Integration

After simulation passes:

1.  Synthesize the AES AXI wrapper.
2.  Check inferred registers.
3.  Check FSM implementation.
4.  Check timing.
5.  Check area.
6.  Check whether AXI logic dominates the small AES wrapper.
7.  Run lint.
8.  Check reset behavior.
9.  Integrate into the target SoC or FPGA design.

The AXI interface should eventually connect to the system interconnect:

``` text
             CPU / AXI Master
                    |
                    v
             AXI Interconnect
                    |
                    v
             AES AXI Slave
                    |
                    v
                AES Core
```

------------------------------------------------------------------------

# 20. Recommended RTL File Structure

A clean implementation could become:

``` text
rtl/
└── verilog/
    ├── aes_cipher_top.v
    ├── aes_inv_cipher_top.v
    ├── aes_inv_sbox.v
    ├── aes_key_expand_128.v
    ├── aes_rcon.v
    ├── aes_sbox.v
    ├── timescale.v
    │
    ├── aes_axi.v
    ├── aes_axi_slave.v
    ├── aes_csr_regs.v
    └── aes_control_fsm.v

bench/
└── verilog/
    ├── test_bench_top.v
    └── tb_axi_master.v
```

The exact partition can be reduced if the project needs fewer files, but
the architectural separation should remain.

------------------------------------------------------------------------

# 21. Final Hardware Contract

The final AES peripheral should behave as follows:

``` text
              AXI WRITE KEY
                    |
              AXI WRITE TEXT
                    |
              AXI WRITE CTRL
                    |
                    v
                 START
                    |
                    v
               Control FSM
              /           \
         ENCRYPT         DECRYPT
            |               |
         ld pulse        kld pulse
            |               |
            |             kdone
            |               |
            |             ld pulse
            |               |
            +-------+-------+
                    |
                  done
                    |
                    v
             output_reg
                    |
             DONE_STATUS=1
                    |
                    v
                AXI READ
```

The central design principle is:

> **AXI transactions manipulate software-visible state. The control FSM
> converts that state into the pulse-based interface expected by the
> existing AES IP.**

This keeps the AXI protocol, CSR state, AES control timing, and AES
datapath logically separated.

------------------------------------------------------------------------

# 22. Immediate Implementation Order

The practical coding order should be:

``` text
1. aes_csr_regs.v
        |
        v
2. aes_axi_slave.v
        |
        v
3. aes_control_fsm.v
        |
        v
4. aes_axi.v
        |
        v
5. tb_axi_master.v
        |
        v
6. AXI encryption test
        |
        v
7. AXI decryption test
        |
        v
8. DONE/BUSY corner cases
        |
        v
9. Verdi waveform verification
        |
        v
10. Synthesis
```

Do not start by writing the whole thing as one giant RTL file. That
would make the first bug a detective novel.

The first implementation milestone should be **AXI master BFM → AXI
slave → CSR registers**, with the AES cores temporarily replaced by
simple behavioral logic or left disconnected. Once AXI and CSR behavior
are proven, connect the actual AES control FSM and cores. This gives
each layer a separately verifiable contract.
