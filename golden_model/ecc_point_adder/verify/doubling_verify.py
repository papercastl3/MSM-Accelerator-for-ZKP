from multiprocessing import Pool
import random

# =============================================================================
# z1=1 최적화 Point Doubling 시뮬레이션
# 스케줄: 3T + 12N
#
# 메모리 맵:
#   M_X1=0, M_Y1=1 (입력, read-only)
#   M_T0=2: Z3 → Z3'(fsub)
#   M_T1=3: M(=3XX) → U → Y3
#   M_T2=4: XX → YYYY → Y8
#   M_T3=5: YY_saved (Slot3 YYYY 계산용 보존)
#   M_T4=6: S_BASE → S → temp
#   M_T5=7: T(=M²) → X3 → X3'(fsub)
# =============================================================================

N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
W = 17; K = 15
R = 2**(W * K)
R_inv = pow(R, -1, N)
TWO_N = 2 * N

def mont_domain_conversion(x): return (x * (R**2) * R_inv) % N
def mont_mul(x, y): return (x * y * R_inv) % N
def mont_mul_lazy(x, y):
    T = x * y
    N_inv = pow(-N % R, -1, R)
    M = (T * N_inv) % R
    return (T + M * N) // R
def lazy_add(x, y):
    s = x + y
    return s - TWO_N if s >= TWO_N else s
def lazy_sub(x, y):
    d = x - y
    return d + TWO_N if d < 0 else d
def final_sub(x):
    return x - N if x >= N else x


def point_double_z1_ref(x1, y1):
    """수학적 레퍼런스 (정확한 mod N 연산), z1=1"""
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)
    # Z1 = mont_domain_conversion(1) = R mod N
    # mont_mul(2*Y1, Z1_mont) = (2*Y1 * R_mod_N * R_inv) mod N = 2*Y1 mod N

    XX   = mont_mul(X1, X1)
    YY   = mont_mul(Y1, Y1)
    YYYY = mont_mul(YY, YY)
    Z3   = (2 * Y1) % N            # Z1=1 → Z3 = 2*Y1 (shift + mod)
    M    = (3 * XX) % N
    S_base = mont_mul(X1, YY)
    T      = mont_mul(M, M)
    S      = (4 * S_base) % N
    two_S  = (2 * S) % N
    X3     = (T - two_S) % N
    temp   = (S - X3) % N
    U      = mont_mul(M, temp)
    Y3     = (U - (8 * YYYY) % N) % N
    return X3, Y3, Z3


def point_double_z1_hw(x1, y1):
    """HW 스케줄 매칭 (lazy 연산), z1=1"""
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)

    # ─────────────────────────────────────────────────
    # [Slot 1] MUL_A: XX=X1², MUL_B: YY=Y1²
    #          ADD: Z3=2Y1 (shift) + final_sub(Z3)
    # ─────────────────────────────────────────────────
    XX = mont_mul_lazy(X1, X1)          # MUL_A → M_T2
    YY = mont_mul_lazy(Y1, Y1)          # MUL_B → M_T3 (YY_saved)
    Z3 = 2 * Y1                         # shift (Y1 < N → 2Y1 < 2N)
    Z3 = final_sub(Z3)                  # → M_T0

    # ─────────────────────────────────────────────────
    # [Wait 1] ADD: M = 3XX (2 adder ops, 2N cycle)
    # ─────────────────────────────────────────────────
    two_XX = lazy_add(XX, XX)           # XX+XX
    M      = lazy_add(XX, two_XX)       # XX+2XX → M_T1

    # ─────────────────────────────────────────────────
    # [Slot 2] MUL_A: S_base=X1*YY, MUL_B: T=M²
    # ─────────────────────────────────────────────────
    S_base = mont_mul_lazy(X1, YY)      # MUL_A → M_T4
    T      = mont_mul_lazy(M, M)        # MUL_B → M_T5

    # ─────────────────────────────────────────────────
    # [Wait 2] ADD chain (5 ops, 5N cycle)
    #   S_2 = S_base+S_base
    #   S   = S_2+S_2
    #   2S  = S+S
    #   X3  = T - 2S
    #   temp= S - X3
    # ─────────────────────────────────────────────────
    S_2   = lazy_add(S_base, S_base)
    S     = lazy_add(S_2, S_2)
    two_S = lazy_add(S, S)
    X3    = lazy_sub(T, two_S)          # → M_T5 (overwrite T)
    temp  = lazy_sub(S, X3)             # → M_T4 (overwrite S_base→S)

    # ─────────────────────────────────────────────────
    # [Slot 3] MUL_A: U=M*temp, MUL_B: YYYY=YY²
    #          BG ADD: final_sub(X3) ×2
    # ─────────────────────────────────────────────────
    U    = mont_mul_lazy(M, temp)       # MUL_A → M_T1 (overwrite M)
    YYYY = mont_mul_lazy(YY, YY)        # MUL_B → M_T2 (overwrite XX)
    X3   = final_sub(X3)               # 1회차
    X3   = final_sub(X3)               # 2회차 → M_T5

    # ─────────────────────────────────────────────────
    # [Final] ADD: Y_2, Y_4, Y_8, Y3=U-Y_8, fsub(Y3)×2
    #         (6N cycle)
    # ─────────────────────────────────────────────────
    Y_2 = lazy_add(YYYY, YYYY)
    Y_4 = lazy_add(Y_2, Y_2)
    Y_8 = lazy_add(Y_4, Y_4)           # → M_T2 (overwrite YYYY)
    Y3  = lazy_sub(U, Y_8)
    Y3  = final_sub(Y3)                # 1회차
    Y3  = final_sub(Y3)                # 2회차 → M_T1

    return X3, Y3, Z3


def rand_test(test_idx):
    random.seed()
    x1 = random.randint(0, N - 1)
    y1 = random.randint(0, N - 1)
    ref = point_double_z1_ref(x1, y1)
    hw  = point_double_z1_hw(x1, y1)
    if ref != hw:
        return (False, test_idx, x1, y1, ref, hw)
    return True


if __name__ == "__main__":
    TEST_COUNT = 1_000_000
    print(f"z1=1 Point Doubling 시뮬레이션: {TEST_COUNT}회 테스트...")
    with Pool() as p:
        results = p.map(rand_test, range(TEST_COUNT))
    passed = results.count(True)
    failed = [r for r in results if isinstance(r, tuple)]
    print(f"\n  Passed: {passed}")
    print(f"  Failed: {len(failed)}")
    if failed:
        for f in failed[:5]:
            _, idx, x1, y1, ref, hw = f
            print(f"  FAIL #{idx}: x1={x1:#x}, y1={y1:#x}")
            print(f"    ref={ref}")
            print(f"    hw ={hw}")
    else:
        print("  >> ALL TESTS PASSED!")
