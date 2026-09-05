# VeeR EL2 Processor — Architectural Diagram

> [!NOTE]
> This diagram was derived by analyzing the actual SystemVerilog source code in [`rtl/core/Cores-VeeR-EL2/design/`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design). All module names and hierarchies match the RTL.

## 1. Top-Level Module Hierarchy

```mermaid
graph TD
    WRAPPER["el2_veer_wrapper<br/>(Top-level SoC wrapper)"]
    CORE["el2_veer<br/>(Core processor)"]
    MEM["el2_mem<br/>(Memory subsystem)"]

    WRAPPER --> CORE
    WRAPPER --> MEM

    subgraph "el2_veer — Core Internals"
        IFU["el2_ifu<br/>(Instruction Fetch Unit)"]
        DEC["el2_dec<br/>(Decode + TLU + GPR)"]
        EXU["el2_exu<br/>(Execution Unit)"]
        LSU["el2_lsu<br/>(Load/Store Unit)"]
        DBG["el2_dbg<br/>(Debug Module)"]
        DMA["el2_dma_ctrl<br/>(DMA Controller)"]
        PIC["el2_pic_ctrl<br/>(PIC Interrupt Controller)"]
        PMP["el2_pmp<br/>(Physical Memory Protection)"]
    end

    CORE --> IFU
    CORE --> DEC
    CORE --> EXU
    CORE --> LSU
    CORE --> DBG
    CORE --> DMA
    CORE --> PIC
    CORE --> PMP
```

---

## 2. Detailed Pipeline Architecture

The VeeR EL2 is a **9-stage, dual-issue capable, in-order pipeline** (RV32IMC).

```mermaid
graph LR
    subgraph "Instruction Fetch Unit — el2_ifu"
        IFC["el2_ifu_ifc_ctl<br/>(Fetch Control)"]
        IC_MEM["el2_ifu_ic_mem<br/>(I-Cache Memory)"]
        ICCM["el2_ifu_iccm_mem<br/>(ICCM - Tightly Coupled)"]
        MEM_CTL["el2_ifu_mem_ctl<br/>(Mem Controller + ECC)"]
        BP["el2_ifu_bp_ctl<br/>(Branch Predictor - BHT/BTB/RAS)"]
        ALN["el2_ifu_aln_ctl<br/>(Aligner - 16/32-bit)"]
        COMP["el2_ifu_compress_ctl<br/>(RV32C Decompressor)"]
    end

    IFC --> MEM_CTL
    MEM_CTL --> IC_MEM
    MEM_CTL --> ICCM
    MEM_CTL --> ALN
    IFC --> BP
    ALN --> COMP
```

```mermaid
graph LR
    subgraph "Decode Unit — el2_dec"
        DEC_CTL["el2_dec_decode_ctl<br/>(Instruction Decode)"]
        IB["el2_dec_ib_ctl<br/>(Instruction Buffer)"]
        GPR["el2_dec_gpr_ctl<br/>(General Purpose Registers)"]
        TLU["el2_dec_tlu_ctl<br/>(Trap/CSR/Timer Logic Unit)"]
        TRIGGER["el2_dec_trigger<br/>(Debug Triggers)"]
        DEC_PMP["el2_dec_pmp_ctl<br/>(PMP CSR Decode)"]
    end

    IB --> DEC_CTL
    DEC_CTL --> GPR
    DEC_CTL --> TLU
    TLU --> TRIGGER
    TLU --> DEC_PMP
```

```mermaid
graph LR
    subgraph "Execution Unit — el2_exu"
        ALU["el2_exu_alu_ctl<br/>(ALU - add/sub/logic/shift)"]
        MUL["el2_exu_mul_ctl<br/>(Multiplier - 1-cycle)"]
        DIV["el2_exu_div_ctl<br/>(Divider - multi-cycle)"]
    end
```

```mermaid
graph LR
    subgraph "Load/Store Unit — el2_lsu"
        LSC["el2_lsu_lsc_ctl<br/>(LS Control)"]
        ADDR["el2_lsu_addrcheck<br/>(Address Checker)"]
        DCCM_CTL["el2_lsu_dccm_ctl<br/>(DCCM Control)"]
        DCCM_MEM["el2_lsu_dccm_mem<br/>(DCCM - Tightly Coupled)"]
        STBUF["el2_lsu_stbuf<br/>(Store Buffer)"]
        ECC["el2_lsu_ecc<br/>(ECC Engine)"]
        BUS_INTF["el2_lsu_bus_intf<br/>(AXI Bus Interface)"]
        BUS_BUF["el2_lsu_bus_buffer<br/>(Bus Buffer)"]
        CLK["el2_lsu_clkdomain<br/>(Clock Domain)"]
        LSU_TRIG["el2_lsu_trigger<br/>(LSU Triggers)"]
    end

    LSC --> ADDR
    LSC --> DCCM_CTL
    DCCM_CTL --> DCCM_MEM
    DCCM_CTL --> ECC
    LSC --> STBUF
    LSC --> BUS_INTF
    BUS_INTF --> BUS_BUF
    LSC --> CLK
    LSC --> LSU_TRIG
```

---

## 3. Bus Interface Architecture

The VeeR EL2 supports **both AXI4 and AHB-Lite** via compile-time defines (`RV_BUILD_AXI4` / `RV_BUILD_AHB_LITE`).

```mermaid
graph TB
    subgraph "VeeR EL2 Core"
        IFU_AXI["IFU AXI Master<br/>(Instruction Fetch)"]
        LSU_AXI["LSU AXI Master<br/>(Load/Store)"]
        SB_AXI["SB AXI Master<br/>(System Bus - Debug)"]
        DMA_AXI["DMA AXI Slave<br/>(DMA Inbound)"]
    end

    subgraph "AXI4 Bus Fabric"
        AXI_BUS["AXI4 Interconnect"]
    end

    subgraph "AHB-Lite Bridge (optional)"
        AXI2AHB_LSU["axi4_to_ahb<br/>(LSU Bridge)"]
        AXI2AHB_IFU["axi4_to_ahb<br/>(IFU Bridge)"]
        AXI2AHB_SB["axi4_to_ahb<br/>(Debug Bridge)"]
        AHB2AXI_DMA["ahb_to_axi4<br/>(DMA Bridge)"]
    end

    IFU_AXI -->|"Read Only"| AXI_BUS
    LSU_AXI -->|"Read/Write"| AXI_BUS
    SB_AXI -->|"Read/Write"| AXI_BUS
    AXI_BUS -->|"Inbound"| DMA_AXI

    IFU_AXI -.->|"AHB mode"| AXI2AHB_IFU
    LSU_AXI -.->|"AHB mode"| AXI2AHB_LSU
    SB_AXI -.->|"AHB mode"| AXI2AHB_SB
    AHB2AXI_DMA -.->|"AHB mode"| DMA_AXI
```

---

## 4. Memory Subsystem

```mermaid
graph TB
    subgraph "el2_mem — Memory Subsystem"
        ICCM_M["ICCM<br/>(Instruction Closely Coupled Memory)<br/>Default: 64KB @ 0xEE000000"]
        DCCM_M["DCCM<br/>(Data Closely Coupled Memory)<br/>Default: 64KB @ 0xF0040000"]
        ICACHE_M["I-Cache<br/>(2-way set-associative)<br/>Default: 16KB"]
        ICACHE_TAG["I-Cache Tag Array"]
    end

    IFU2["IFU"] -->|"Fetch"| ICCM_M
    IFU2 -->|"Fetch"| ICACHE_M
    ICACHE_M --- ICACHE_TAG
    LSU2["LSU"] -->|"Load/Store"| DCCM_M
    DMA2["DMA"] -->|"DMA Access"| ICCM_M
    DMA2 -->|"DMA Access"| DCCM_M
```

---

## 5. Interrupt & Debug Architecture

```mermaid
graph TB
    subgraph "Interrupt Path"
        EXT_INT["External Interrupts<br/>(extintsrc_req - up to 255)"]
        PIC_C["el2_pic_ctrl<br/>(Programmable Interrupt Controller)"]
        TIMER_INT["Timer Interrupt<br/>(timer_int)"]
        SOFT_INT["Software Interrupt<br/>(soft_int)"]
        TLU_C["el2_dec_tlu_ctl<br/>(Trap Logic Unit)"]
    end

    EXT_INT --> PIC_C
    PIC_C -->|"claimid, pl, mexintpend"| TLU_C
    TIMER_INT --> TLU_C
    SOFT_INT --> TLU_C

    subgraph "Debug Path"
        JTAG["JTAG Interface<br/>(tck, tms, tdi, tdo)"]
        DMI["DMI Port<br/>(Debug Module Interface)"]
        DBG_C["el2_dbg<br/>(Debug Module)"]
        SB_BUS["System Bus AXI<br/>(sb_axi_*)"]
    end

    JTAG --> DBG_C
    DMI --> DBG_C
    DBG_C -->|"Debug commands"| TLU_C
    DBG_C -->|"Memory access"| SB_BUS
```

---

## 6. Complete Data Flow Summary

```mermaid
graph TD
    subgraph "el2_veer_wrapper"
        direction TB

        subgraph "el2_veer Core"
            direction LR
            A["IFU<br/>Fetch + BPU + I-Cache + ICCM<br/>Aligner + Decompressor"] --> B["DEC<br/>Decode + GPR + CSR<br/>Trap Logic Unit"]
            B --> C["EXU<br/>ALU + MUL + DIV"]
            B --> D["LSU<br/>Addr Check + DCCM<br/>Store Buffer + Bus Intf"]
        end

        subgraph "Support Blocks"
            E["PIC Ctrl<br/>(Interrupt Controller)"]
            F["Debug Module<br/>(JTAG/DMI)"]
            G["DMA Controller"]
            H["PMP<br/>(Memory Protection)"]
        end

        subgraph "el2_mem"
            I["ICCM"] 
            J["DCCM"]
            K["I-Cache + Tags"]
        end
    end

    A ---|"Fetch from"| I
    A ---|"Fetch from"| K
    D ---|"Load/Store"| J
    G ---|"DMA to"| I
    G ---|"DMA to"| J

    L["AXI4 / AHB-Lite<br/>External Bus"] <--> A
    L <--> D
    L <--> F
    L <--> G

    M["JTAG"] --> F
    N["Ext Interrupts"] --> E
    E --> B
```

---

## 7. Key Source File Reference

| Module | Source File | Purpose |
|---|---|---|
| `el2_veer_wrapper` | [`el2_veer_wrapper.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/el2_veer_wrapper.sv) | Top-level wrapper with AXI/AHB ports |
| `el2_veer` | [`el2_veer.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/el2_veer.sv) | Core processor, instantiates all units |
| `el2_mem` | [`el2_mem.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/el2_mem.sv) | Memory subsystem (ICCM, DCCM, I-Cache) |
| `el2_ifu` | [`el2_ifu.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/ifu/el2_ifu.sv) | Instruction Fetch Unit |
| `el2_dec` | [`el2_dec.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/dec/el2_dec.sv) | Decode, GPR, TLU, Triggers |
| `el2_exu` | [`el2_exu.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/exu/el2_exu.sv) | Execution: ALU, MUL, DIV |
| `el2_lsu` | [`el2_lsu.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/lsu/el2_lsu.sv) | Load/Store Unit |
| `el2_dbg` | [`el2_dbg.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/dbg/el2_dbg.sv) | Debug Module (JTAG + System Bus) |
| `el2_dma_ctrl` | [`el2_dma_ctrl.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/el2_dma_ctrl.sv) | DMA Controller |
| `el2_pic_ctrl` | [`el2_pic_ctrl.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/el2_pic_ctrl.sv) | Programmable Interrupt Controller |
| `el2_pmp` | [`el2_pmp.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/el2_pmp.sv) | Physical Memory Protection |
| `axi4_to_ahb` | [`axi4_to_ahb.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/lib/axi4_to_ahb.sv) | AXI4→AHB-Lite bridge |
| `ahb_to_axi4` | [`ahb_to_axi4.sv`](file:///e:/Projects/honours_project/rtl/core/Cores-VeeR-EL2/design/lib/ahb_to_axi4.sv) | AHB-Lite→AXI4 bridge |
