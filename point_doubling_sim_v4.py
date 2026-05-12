from multiprocessing import Pool
import random

# =============================================================================
# Section 4 최종판: final_sub 2회 (X3, Y3 모두)
# 총 레이턴시: 4T + 8N
# =============================================================================

N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013
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


def point_double_ref(x1, y1, z1):
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)
    Z1 = mont_domain_conversion(z1)
    XX   = mont_mul(X1, X1)
    YY   = mont_mul(Y1, Y1)
    YYYY = mont_mul(YY, YY)
    Z3   = mont_mul((2 * Y1) % N, Z1)
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


def point_double_s4(x1, y1, z1):
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)
    Z1 = mont_domain_conversion(z1)

    # [Slot 1]
    XX = mont_mul_lazy(X1, X1)
    YY = mont_mul_lazy(Y1, Y1)

    # [Slot 2] — 2Y1은 shift로 계산 (Y1 < N → 2Y1 < 2N 보장)
    two_Y1 = 2 * Y1    # HW: Y1 << 1 (no adder needed)
    Z3     = mont_mul_lazy(two_Y1, Z1)
    YYYY   = mont_mul_lazy(YY, YY)
    two_XX = lazy_add(XX, XX)
    M      = lazy_add(XX, two_XX)

    # [Slot 3] + final_sub(Z3) 1회 (Z3 < 2N 보장)
    S_base = mont_mul_lazy(X1, YY)
    T      = mont_mul_lazy(M, M)
    Z3     = final_sub(Z3)

    # [Slot 4 Adder chain]
    S_2   = lazy_add(S_base, S_base)
    S     = lazy_add(S_2, S_2)
    two_S = lazy_add(S, S)
    X3    = lazy_sub(T, two_S)
    temp  = lazy_sub(S, X3)

    # [Slot 4 MUL + bg] Y2,Y4,Y8,fsub(X3)×2
    U   = mont_mul_lazy(M, temp)
    Y_2 = lazy_add(YYYY, YYYY)
    Y_4 = lazy_add(Y_2, Y_2)
    Y_8 = lazy_add(Y_4, Y_4)
    X3  = final_sub(X3)    # 1회차
    X3  = final_sub(X3)    # 2회차

    # [최종] Y3, fsub(Y3)×2
    Y3 = lazy_sub(U, Y_8)
    Y3 = final_sub(Y3)     # 1회차
    Y3 = final_sub(Y3)     # 2회차

    return X3, Y3, Z3


def rand_test(test_idx):
    random.seed()
    x1 = random.randint(0, N - 1)
    y1 = random.randint(0, N - 1)
    z1 = random.randint(1, N - 1)
    ref = point_double_ref(x1, y1, z1)
    s4  = point_double_s4(x1, y1, z1)
    if ref != s4:
        return (False, test_idx)
    return True


if __name__ == "__main__":
    TEST_COUNT = 1_000_000
    print(f"Section 4 최종판 (fsub x2): {TEST_COUNT}회 테스트...")
    with Pool() as p:
        results = p.map(rand_test, range(TEST_COUNT))
    passed = results.count(True)
    failed = [r for r in results if isinstance(r, tuple)]
    print(f"\n  Passed: {passed}")
    print(f"  Failed: {len(failed)}")
    if not failed:
        print("  >> ALL TESTS PASSED!")
