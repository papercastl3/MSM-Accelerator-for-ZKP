# ZKP를 위한 MSM 가속기

[English](README.md) | **한국어**

**Groth16 영지식 증명(ZKP)의 핵심 연산인 다중 스칼라 곱셈(MSM)을 위한 저비용·저전력 FPGA 가속기 — SystemVerilog RTL부터 리눅스 커널 드라이버까지 AMD Kria KR260 보드에서 end-to-end로 구현.**

> 타깃 곡선: **ALT-BN128 (BN254)** · 보드: **AMD Kria KR260 (Zynq UltraScale+ MPSoC)** · 동작 주파수: **100 MHz** · 전력: **약 4.5 W**

## 개발 동기

영지식 증명(ZKP)은 **원본 데이터를 공개하지 않고도** 어떤 계산이 올바르게 수행되었음을 증명하게 해줍니다. 프라이버시 보존 블록체인(ZK-Rollup, 프라이빗 트랜잭션, 신원 인증)의 핵심 인프라이지만, **증명 생성 비용이 매우 큽니다.** Groth16 같은 zk-SNARK에서 타원곡선 위의 **다중 스칼라 곱셈(MSM)** 은 대표적인 병목 연산입니다.

기존 MSM 가속기 대부분은 **데이터센터급 FPGA**($8,000 보드, 50W 이상)를 대상으로 합니다. 하지만 ZK가 **모바일 지갑·IoT·엣지 디바이스**로 확장되면서, 이 연산을 **제한된 전력·면적 예산** 안에서 처리할 필요가 생겼습니다. 본 프로젝트의 질문은 이것입니다: *깨끗하고 검증 가능한 HW/SW 경계를 유지하면서, 저비용·저전력 임베디드 SoC-FPGA에 MSM을 얼마나 오프로딩할 수 있는가?* 이더리움의 **ALT-BN128** 곡선을 대상으로, **Pippenger(윈도우–버킷)** 구조와 **CPU–FPGA 협업 설계**를 적용했습니다.

## 이 프로젝트의 차별점

이것은 "세계 기록 경신"형 가속기가 **아닙니다.** 보통 여러 사람이 나눠 맡는 모든 계층을 관통한 **풀스택, 자원 제약형 시스템 프로젝트**입니다:

- **암호 연산 엔지니어링** — 몽고메리 모듈러 곱셈(CIOS), Lazy Reduction, 혼합좌표 타원곡선 점 덧셈, Pippenger 버킷화.
- **RTL 및 타이밍 클로저** — 소형 SoC-FPGA에서 100 MHz를 만족하는 SystemVerilog 데이터패스.
- **HW/SW 협업 설계** — MSM 연산의 약 96%를 차지하는 *Bucket Accumulation* 단계를 FPGA가 가속하고, ARM CPU가 dispatch·reduction·window aggregation을 담당.
- **OS 계층 통합** — **Scatter-Gather DMA** 기반 **리눅스 커널 드라이버**, cache coherency 처리, 실제 보드 bring-up까지 (RTL 시뮬레이션에서 끝나지 않음).

## 시스템 아키텍처

```
   ┌──────────────── PS (ARM Cortex-A53, Linux) ─────────────────┐
   │  point/scalar 준비 · Pippenger 제어 · bucket reduction ·     │
   │  window aggregation · 커널 드라이버 + Scatter-Gather DMA     │
   └──────────▲───────────────────────────────────────▲──────────┘
              │ AXI4-Lite (제어)      AXI4-Stream (데이터)│
   ┌──────────┴──────────────── PL (FPGA) ─────────────┴──────────┐
   │  Point/Scalar Dispatcher → 8 × [ ECC Point Adder (Mixed Add) ]│
   │                             ├─ 2 × 몽고메리 곱셈기            │
   │                             └─ 256-bit 모듈러 가감산기        │
   │  8 Bucket Banks (온칩 8×2K×96 B) · Write-Back Controller      │
   └──────────────────────────────────────────────────────────────┘
        DDR4 4 GB (PS/PL 공유) ── Point DMA · Scalar DMA
```

- **254-bit 스칼라**를 **24개 윈도우**로 분할 (윈도우당 최대 **2048개 버킷**).
- **8개의 타원곡선 점 덧셈기**를 병렬 배치 → **윈도우 8개/배치 × 3배치 = 24 윈도우**.
- 병렬성이 높은 **Bucket Accumulation**을 FPGA로 오프로딩하고, CPU가 상대적으로 가벼운 reduction/aggregation을 담당 → **단순하고 검증 가능한 HW/SW 분담**.

## 하드웨어 설계 상세

### 몽고메리 곱셈기 (유한체 곱셈)
- **CIOS** 알고리즘 · **17-bit word** (DSP48E2의 27×18 signed 곱셈기에 최적 매핑).
- `R = 2^255`, `N' = -N⁻¹ mod R` 사전 계산 → 모듈러 감소가 **나눗셈이 아닌 shift + add**로 처리됨.
- **DSP 4개**로 곱셈/reduction을 중첩 스케줄링하여 latency 은닉.
- **Lazy Reduction 전제로 final subtraction 생략** → 비교기/뺄셈 LUT 절감.

### 256-bit 모듈러 가감산기
- **32-bit word-serial**(8 word) 구조 → carry chain을 짧게 유지하여 full-width 256-bit 대비 높은 Fmax·낮은 자원.
- **2의 보수**(`A − B = A + ~B + 1`)로 하나의 가산기를 뺄셈에 재활용.
- 세 가지 모드: **Lazy Add / Lazy Sub**(`[0, 2N)` 유지)와 **Final Sub**(`[0, N)`로 감소). 17-cycle / 9-cycle.

### Mixed Addition (타원곡선 점 덧셈)
- **Affine 입력점 + Jacobian 누적점**(`Z₁ = 1`) → modular inversion 제거, 일반 Jacobian 덧셈 대비 곱셈 수 감소.
- **몽고메리 곱셈기 2개 + 모듈러 가감산기 1개**로 구성, `U₁, S₁, H, r, V, X₃, Y₃, Z₃` 의존성에 맞춰 스케줄링.
- **예외 처리**(무한원점 / 역원 / 동일점)를 중간값 `H`, `r`로 판별 (`H=0,r=0`→doubling, `H=0,r≠0`→무한원점) — 좌표계가 서로 달라 직접 비교가 어려운 문제를 중간값으로 해결.

### Pippenger 버킷화
- 같은 윈도우 값을 가진 점들을 공용 버킷에 누적 → 버킷을 reduction하고 윈도우 결과를 shift·합산. 점별 스칼라 곱셈(다량의 doubling)을 **병렬화 가능한 덧셈 중심의 버킷 누적**으로 변환 (이 부분을 하드웨어로 오프로딩).

## 실험 결과

**MSM 및 Groth16 실행 시간 (2¹⁶ points), 동일 보드의 ARM Cortex-A53 대비:**

| 구현 | 주파수 | MSM 시간 (2¹⁶) | Groth16 시간 |
|---|---|---|---|
| **본 설계 (FPGA + A53)** | 100 MHz | **10.98 s** | **38.24 s** |
| ARM Cortex-A53 (싱글 스레드) | 1.2 GHz | 47.36 s | 187.21 s |
| ARM Cortex-A53 (멀티 스레드) | 1.2 GHz | 12.08 s | 41.32 s |

→ 동일 SoC에서 **싱글 스레드 CPU 대비 4.31배 속도 향상.**

**데이터센터급 MSM 가속기와의 비용/전력/자원 비교:**

| | 곡선 | 프로세서 | 가격 | 전력 | LUT | 주파수 | MSM 시간 |
|---|---|---|---|---|---|---|---|
| **본 설계** | ALT-BN128 | Zynq US+ MPSoC | **$350** | **4.5 W** | 95,386 | 100 MHz | 10.98 s (2¹⁶) |
| Hardcaml ZPrize | BLS12-377 | UltraScale+ VU9P | $8,000 | 52 W | 387,166 | 278 MHz | 5.52 s (2²⁶) |

목표는 23배 비싸고 11배 높은 전력의 FPGA와 절대 속도로 경쟁하는 것이 아니라, **엣지급 보드에서 달러·와트당 효율**을 달성하는 것입니다.

**자원 사용량 (KR260):** CLB 14,544 (99%) · LUT 95,386 (81%) · URAM 44 (69%). Vivado 타이밍 분석으로 100 MHz 안정 동작 검증.

## 검증

1. **RTL 시뮬레이션** — PS를 모델링하는 **Zynq VIP** 기반 SystemVerilog 테스트벤치(AXI4-Lite 제어, SG-DMA, AXI4-Stream handshake). 윈도우별/버킷별 Jacobian 좌표를 소프트웨어 **골든 모델**과 2¹⁶-point 테스트 벡터로 비교.
2. **실보드 검증** — **리눅스 커널 드라이버**로 KR260에서 실제 DMA 전송을 수행, FPGA 버킷 결과를 골든 모델과 end-to-end 비교(유저 프로그램 → 드라이버 → DMA → PL → 결과 버퍼). ILA/JTAG와 CPU idle 충돌은 `cpuidle.off=1`로 해결.

## 한계 및 향후 과제

**한계:** 부분 가속(Bucket Accumulation만, Groth16 end-to-end 아님); 깊은 파이프라인 미적용(소형 보드에 맞춰 연산기 복제 → throughput 제한, 멀티스레드 대비 마진 작음); 전력을 `energy-per-MSM`으로 측정하지 않음; 2¹⁶ points에서 테스트(실제 ZK 회로는 2²⁰–2²²).

**향후 과제:** 몽고메리 곱셈기·Mixed-Adder 파이프라이닝으로 Fmax·throughput 향상; DMA 전송과 연산 중첩; Groth16(및 PLONK 계열) end-to-end 통합; `energy-per-MSM` 측정; ASIC 면적 추정.

## 저장소 구조

```
├── accelerator/    # SystemVerilog RTL: 몽고메리 곱셈기, 모듈러 가감산기, Mixed Adder, Pippenger 컨트롤러, 버킷 뱅크
├── driver/         # 리눅스 커널 드라이버: Scatter-Gather DMA, AXI 제어, 유저 공간 인터페이스
├── golden_model/   # 검증용 소프트웨어 참조 모델 (MSM / bucket accumulation)
├── test_bench/     # Zynq VIP 기반 RTL 테스트벤치 및 테스트 벡터
├── exp/            # 실험 스크립트 및 측정 결과
└── etc/            # 기타 / 헬퍼 파일
```

## 빌드 & 실행

> 툴체인 버전/경로는 환경에 따라 다릅니다. 아래는 의도한 상위 수준 흐름이며, 세부 사항은 각 하위 디렉토리를 참고하세요.

- **사전 요구사항:** AMD Vivado/Vitis · PetaLinux/Ubuntu가 올라간 Kria KR260 · CMake + C++17 툴체인.
- **RTL 시뮬레이션:** `test_bench/`의 Zynq VIP 테스트벤치를 `golden_model/`과 비교 실행.
- **비트스트림:** `accelerator/`를 KR260 타깃으로 합성/구현, 비트스트림 + 핸드오프 export.
- **호스트/골든 모델:** `cmake -S . -B build && cmake --build build`
- **실보드 실행:** PL 프로그래밍 후 `driver/`의 드라이버를 `insmod`, 호스트 앱으로 point/scalar를 DMA 스트리밍하여 골든 모델과 비교.

## 참고 문헌

1. Z. Yang et al., *"LegoZK: A Dynamically Reconfigurable Accelerator for Zero-Knowledge Proof,"* IEEE HPCA 2025.
2. K. Aasaraai et al., *"FPGA Acceleration of Multi-Scalar Multiplication: CycloneMSM,"* Cryptology ePrint Archive, 2022.
3. M. Petkus, *"Why and How zk-SNARK Works,"* arXiv:1906.07221, 2019.
4. Hardcaml ZPrize — https://zprize.hardcaml.com/ · SCIPR Lab libsnark — https://github.com/scipr-lab/libsnark
5. AMD Kria KR260 문서; AXI DMA (PG021), UltraScale Memory Resources (UG573).

## 팀

**팀 0지식1지성** — 광운대학교 컴퓨터정보공학부 · 지도교수: 황호영 교수님 · *2026학년도 1학기 참빛설계학기.*

| 팀원 | 역할 |
|---|---|
| **조하빈** (팀장) | Pippenger Controller · 전체 시스템 통합 |
| **한지성** | 몽고메리 곱셈기 · 타원곡선 점 덧셈기의 Mixed Add 및 예외/분기 로직 · libsnark 수정 및 나머지 유한체 연산 |
| **송예준** | PS–PL 간 DMA 연결 · 데이터 송수신 드라이버 |
| **양우진** | 256-bit 모듈러 가감산기 · 점 Doubling 로직 · 전시 판넬 제작 |

## 라이선스

MIT License — `LICENSE` 참고.
