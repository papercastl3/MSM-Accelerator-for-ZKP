# MSM Accelerator for ZKP

**English** | [한국어](README.ko.md)

**A low-cost, low-power FPGA accelerator for Multi-Scalar Multiplication (MSM) on the Groth16 zero-knowledge proof protocol — implemented end-to-end from SystemVerilog RTL down to a Linux kernel driver on an AMD Kria KR260.**

> Target curve: **ALT-BN128 (BN254)** · Board: **AMD Kria KR260 (Zynq UltraScale+ MPSoC)** · Clock: **100 MHz** · Power: **~4.5 W**
---
<img width="707" height="418" alt="image" src="https://github.com/user-attachments/assets/38c3926b-f97e-4516-bae0-ef968652a455" />

## Table of Contents
- [Motivation](#motivation)
- [Why This Project Is Different](#why-this-project-is-different)
- [System Architecture](#system-architecture)
- [Hardware Design Details](#hardware-design-details)
- [Results](#results)
- [Verification](#verification)
- [Limitations & Future Work](#limitations--future-work)
- [Repository Structure](#repository-structure)
- [Build & Run](#build--run)
- [References](#references)
- [Team](#team)

---

## Motivation

Zero-knowledge proofs (ZKPs) let one party prove that a computation was performed correctly **without revealing the underlying data**. They are becoming core infrastructure for privacy-preserving blockchains (ZK-Rollups, private transactions, identity), but **proof generation is extremely expensive**. Within zk-SNARK systems such as Groth16, **Multi-Scalar Multiplication (MSM)** over elliptic curves is one of the dominant bottlenecks.

Most existing MSM accelerators target **datacenter-class FPGAs** (e.g. $8,000 boards, 50+ W). As ZK moves toward **mobile wallets, IoT, and edge devices**, there is a need to run these primitives under **tight power and area budgets**. This project asks: *how far can we offload MSM onto a cheap, low-power embedded SoC-FPGA while keeping a clean, verifiable HW/SW boundary?*

We target Ethereum's **ALT-BN128** curve and accelerate MSM using a **Pippenger (window–bucket)** structure with a **CPU–FPGA co-design**.

## Why This Project Is Different

This is **not** a "beat the world record" accelerator. It is a **full-stack, resource-constrained systems project** that spans every layer usually split across multiple people:

- **Cryptographic engineering** — Montgomery modular multiplication (CIOS), lazy reduction, mixed-coordinate elliptic-curve point addition, Pippenger bucketization.
- **RTL & timing closure** — SystemVerilog datapath meeting 100 MHz on a small SoC-FPGA.
- **HW/SW co-design** — the FPGA accelerates the ~96%-heavy *Bucket Accumulation* stage; the ARM CPU handles dispatch, reduction, and window aggregation.
- **OS-level integration** — a **Linux kernel driver** with **Scatter-Gather DMA**, cache-coherency handling, and real board bring-up — not just an RTL simulation.

The design choices throughout are driven by **explicit area/latency/frequency trade-offs on a $350 board**, which is documented in the [design report](#references).

## System Architecture

```
        ┌──────────────────────── PS (ARM Cortex-A53, Linux) ────────────────────────┐
        │  point/scalar preparation · Pippenger control · bucket reduction ·          │
        │  window aggregation · kernel driver + Scatter-Gather DMA                     │
        └───────────────▲───────────────────────────────────────────────▲────────────┘
                        │ AXI4-Lite (control)          AXI4-Stream (data) │
                        │                                                 │
        ┌───────────────┴───────────────── PL (FPGA) ─────────────────────┴───────────┐
        │  Point/Scalar Dispatcher → 8 × [ ECC Point Adder (Mixed Add) ]               │
        │                              ├─ 2 × Montgomery Multiplier (CIOS)             │
        │                              └─ 256-bit Modular Add/Sub (word-serial)        │
        │  8 Bucket Banks (on-chip, 8 × 2K × 96 B)  ·  Bucket Write-Back Controller    │
        └──────────────────────────────────────────────────────────────────────────────┘
                        DDR4 4 GB (shared PS/PL) ── Point DMA · Scalar DMA
```

- **254-bit scalars** are sliced into **24 windows** (up to **2048 buckets** each).
- **8 elliptic-curve point adders** run in parallel — **8 windows per batch × 3 batches = 24 windows**.
- The heavy, highly parallel **Bucket Accumulation** stage is offloaded to the FPGA; the CPU performs the lighter reduction and aggregation, giving a **simple, verifiable HW/SW split**.

## Hardware Design Details

### Montgomery Multiplier (finite-field multiply)
- **CIOS** (Coarsely Integrated Operand Scanning) with **17-bit words**, chosen to map efficiently onto the DSP48E2's 27×18 signed multiplier.
- `R = 2^255`, `N' = -N⁻¹ mod R` precomputed → modular reduction becomes **shift + add** instead of division.
- **4 DSPs** with overlapped multiply/reduce scheduling to hide latency (partial, not fully pipelined).
- **Final subtraction omitted** — valid under lazy reduction — saving comparator/subtractor LUTs.

### 256-bit Modular Adder/Subtractor
- **32-bit word-serial** design (8 words) → short carry chains, higher Fmax, lower area than a full-width 256-bit adder.
- Single adder reused for subtraction via **two's-complement** (`A − B = A + ~B + 1`).
- Three modes: **Lazy Add**, **Lazy Sub** (both keep results in `[0, 2N)`), and **Final Sub** (reduce to `[0, N)`).
- Rotational data alignment; borrow decided from the final carry-out. 17-cycle (add/sub) / 9-cycle (final sub).

### Mixed Addition (elliptic-curve point add)
- **Affine input point + Jacobian accumulator** (`Z₁ = 1`) → eliminates modular inversion and drops several multiplications vs. general Jacobian addition.
- Built from **2 Montgomery multipliers + 1 modular add/sub**, scheduled around the data dependencies of `U₁, S₁, H, r, V, X₃, Y₃, Z₃`.
- **Exception handling** for the point-at-infinity / negation / doubling cases is derived from the intermediates `H` and `r` (`H=0, r=0` → doubling; `H=0, r≠0` → infinity), since the two operands live in different coordinate systems.

### Pippenger Bucketization
- Scalars split into windows; points with the same window value accumulate into the same bucket; buckets are reduced and window results are shifted and summed.
- Turns per-point scalar multiplication (lots of point doublings) into **parallelizable point-addition-centric bucket accumulation** — the part we push to hardware.

## Results

**MSM & Groth16 wall-clock (2¹⁶ points), vs. the same board's ARM Cortex-A53 baseline:**

| Implementation | Frequency | MSM Time (2¹⁶) | Groth16 Time |
|---|---|---|---|
| **This work (FPGA + A53)** | 100 MHz | **10.98 s** | **38.24 s** |
| ARM Cortex-A53 (single thread) | 1.2 GHz | 47.36 s | 187.21 s |
| ARM Cortex-A53 (multi thread) | 1.2 GHz | 12.08 s | 41.32 s |

→ **4.31× speedup vs. single-thread CPU** on the same SoC. (Multi-thread margin is smaller — see [Limitations](#limitations--future-work).)

**Cost / power / resource comparison with a datacenter-class MSM accelerator:**

| | Curve | Processor | Cost | Power | LUT | Freq | MSM Time |
|---|---|---|---|---|---|---|---|
| **This work** | ALT-BN128 | Zynq US+ MPSoC | **$350** | **4.5 W** | 95,386 | 100 MHz | 10.98 s (2¹⁶) |
| Hardcaml ZPrize | BLS12-377 | UltraScale+ VU9P | $8,000 | 52 W | 387,166 | 278 MHz | 5.52 s (2²⁶) |

The goal here is **efficiency per dollar and per watt on an edge-class board**, not absolute throughput against a 23×-more-expensive, 11×-higher-power FPGA.

**Resource utilization (KR260):** CLB 14,544 (99%) · LUT 95,386 (81%) · URAM 44 (69%). Verified stable at 100 MHz via Vivado timing analysis.

## Verification

1. **RTL simulation** — SystemVerilog testbench with a **Zynq VIP** modeling the PS, exercising AXI4-Lite control, Scatter-Gather DMA, and AXI4-Stream handshakes. Per-window / per-bucket Jacobian coordinates are compared against a software **golden model** over a 2¹⁶-point test vector.
2. **On-board validation** — a **Linux kernel driver** drives real DMA transfers on the KR260; FPGA bucket results are compared against the golden model end-to-end (user program → driver → DMA → PL → result buffer). ILA/JTAG-vs-CPU-idle contention was resolved with `cpuidle.off=1`.

## Limitations & Future Work

**Honest limitations:**
- **Partial acceleration** — only Bucket Accumulation is offloaded; the full Groth16 proving pipeline is not accelerated end-to-end.
- **No deep pipelining** — to fit the small board, compute units were replicated instead of deeply pipelined, which caps throughput and explains the modest margin over the multi-thread CPU.
- **Power not yet measured** — the "low power" claim rests on the 4.5 W device figure, not an `energy-per-MSM` measurement.
- **Scale** — tested at 2¹⁶ points; production ZK circuits use 2²⁰–2²², so the scaling behavior of bucket memory and DMA needs study.

**Future work:**
- Pipeline the Montgomery multiplier and Mixed-Adder to raise Fmax and throughput.
- Overlap DMA transfer with computation; optimize memory access.
- End-to-end integration with a Groth16 proving pipeline; extend to PLONK-family MSM.
- `energy-per-MSM` measurement to substantiate the low-power claim; ASIC area estimate.

## Repository Structure

```
.
├── accelerator/    # SystemVerilog RTL: Montgomery mult, modular add/sub, Mixed Adder, Pippenger controller, bucket banks
├── driver/         # Linux kernel driver: Scatter-Gather DMA, AXI control, user-space interface
├── golden_model/   # Reference software model (MSM / bucket accumulation) for verification
├── test_bench/     # Zynq VIP-based RTL testbenches and test vectors
├── exp/            # Experiment scripts and measurement results
└── etc/            # Misc / helper files
```

## Build & Run

> The exact toolchain versions and paths are environment-specific; the flow below is the intended high-level sequence. See each subdirectory for details.

**Prerequisites**
- AMD Vivado / Vitis (SoC-FPGA build)
- AMD Kria KR260 with a PetaLinux / Ubuntu image
- CMake, a C++17 toolchain (for the golden model and host app)

**1. Build & simulate the RTL**
```bash
# Open the project in Vivado and run the Zynq VIP testbench in test_bench/,
# or use the provided scripts to run RTL simulation against golden_model/.
```

**2. Synthesize the bitstream**
```bash
# Synthesize/implement accelerator/ for the KR260 target and export the bitstream + hardware handoff.
```

**3. Build the golden model / host app**
```bash
cmake -S . -B build
cmake --build build
```

**4. Load the driver and run on-board**
```bash
# Program the PL, insmod the driver in driver/, then run the host application
# to stream points/scalars over DMA and compare FPGA output against the golden model.
```

## References

1. Z. Yang et al., *"LegoZK: A Dynamically Reconfigurable Accelerator for Zero-Knowledge Proof,"* IEEE HPCA 2025.
2. K. Aasaraai et al., *"FPGA Acceleration of Multi-Scalar Multiplication: CycloneMSM,"* Cryptology ePrint Archive, 2022.
3. M. Petkus, *"Why and How zk-SNARK Works,"* arXiv:1906.07221, 2019.
4. Hardcaml ZPrize — https://zprize.hardcaml.com/
5. SCIPR Lab, libsnark — https://github.com/scipr-lab/libsnark
6. AMD Kria KR260 / KV260 documentation; AXI DMA (PG021), UltraScale Memory Resources (UG573).

## Team

**Team 0지식1지성 (0-Knowledge 1-Intelligence)** — Kwangwoon University, Dept. of Computer Information Engineering
Advisor: Prof. Hoyoung Hwang · *ChamBit Capstone Design, 2026 Spring.*

| Member | Role |
|---|---|
| **Habin Cho** (Lead) | Pippenger Controller · overall system integration |
| **Jisung Han** | Montgomery multiplier · Mixed-Addition & exception/branch logic of the EC point adder · libsnark modification and remaining field operations |
| **Yejun Song** | PS–PL DMA connection · data-transfer device driver |
| **Woojin Yang** | 256-bit modular adder/subtractor · point-Doubling logic · exhibition panel |

## License

Released under the MIT License — see `LICENSE`. *(Add a LICENSE file if not present.)*
