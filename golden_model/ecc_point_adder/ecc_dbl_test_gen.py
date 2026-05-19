"""
Golden model test vector generator for point_doubling_z1 (Z1=1 optimized).
HW expects inputs already in Montgomery domain (or any value < N).
Z1 is always 1 — not passed to HW.
"""
import random

N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013
W = 17; K = 15
R = 2**(W * K)
TWO_N = 2 * N

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

def point_double_z1_hw(X1, Y1):
    """Matches HW exactly — no domain conversion, Z1=1 assumed."""
    # [Slot 1]
    XX = mont_mul_lazy(X1, X1)
    YY = mont_mul_lazy(Y1, Y1)
    Z3 = 2 * Y1              # shift
    Z3 = final_sub(Z3)

    # [Wait 1] M = 3XX
    two_XX = lazy_add(XX, XX)
    M      = lazy_add(XX, two_XX)

    # [Slot 2]
    S_base = mont_mul_lazy(X1, YY)
    T      = mont_mul_lazy(M, M)

    # [Wait 2]
    S_2   = lazy_add(S_base, S_base)
    S     = lazy_add(S_2, S_2)
    two_S = lazy_add(S, S)
    X3    = lazy_sub(T, two_S)
    temp  = lazy_sub(S, X3)

    # [Slot 3]
    U    = mont_mul_lazy(M, temp)
    YYYY = mont_mul_lazy(YY, YY)
    X3   = final_sub(X3)
    X3   = final_sub(X3)

    # [Final]
    Y_2 = lazy_add(YYYY, YYYY)
    Y_4 = lazy_add(Y_2, Y_2)
    Y_8 = lazy_add(Y_4, Y_4)
    Y3  = lazy_sub(U, Y_8)
    Y3  = final_sub(Y3)
    Y3  = final_sub(Y3)

    return X3, Y3, Z3

def main():
    NUM_TESTS = 1000
    outfile = "test_vectors_z1.txt"

    random.seed(42)
    with open(outfile, "w") as f:
        f.write(f"{NUM_TESTS}\n")
        for _ in range(NUM_TESTS):
            x1 = random.randint(0, N - 1)
            y1 = random.randint(1, N - 1)  # Y1 != 0 (avoid degenerate case)
            ex3, ey3, ez3 = point_double_z1_hw(x1, y1)
            f.write(f"{x1:064x} {y1:064x} {ex3:064x} {ey3:064x} {ez3:064x}\n")

    print(f"Generated {NUM_TESTS} z1=1 test vectors -> {outfile}")

if __name__ == "__main__":
    main()
