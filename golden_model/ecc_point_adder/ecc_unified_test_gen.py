import random
from multiprocessing import Pool

# 하드웨어 파라미터
N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
W = 17
K = 15
R = 2**(W * K)
R_inv = pow(R, -1, N) 

TWO_N = 2 * N
THREE_N = 3 * N

# 하드웨어 255비트 레지스터 한계 마스킹
MAX_255 = (1 << 255) - 1
N_INV_MOD_R = pow(-N % R, -1, R)

def mont_domain_conversion(x):
    return (x * (R**2) * R_inv) % N

def mont_mul_lazy_hw(x, y):
    T = x * y
    M = (T * N_INV_MOD_R) % R
    redc = (T + M * N) // R 
    return redc & MAX_255  # 하드웨어 Truncation 모방

def lazy_subtraction_N_hw(x):
    res = x if (x - N < 0) else (x - N)
    return res & MAX_255

def lazy_subtraction_2N_hw(x, y):
    res = (x - y + TWO_N) if (x - y < 0) else (x - y)
    return res & MAX_255

def lazy_subtraction_3N_hw(x, y):
    res = (x - y + THREE_N) if (x - y < 0) else (x - y)
    return res & MAX_255

def lazy_add(x, y):
    s = x + y
    return s - TWO_N if s >= TWO_N else s


def lazy_sub(x, y):
    d = x - y
    return d + TWO_N if d < 0 else d

# Doubling with lazy reduction
def point_double_z1_hw(X1, Y1):
    # [Slot 1]
    XX = mont_mul_lazy_hw(X1, X1)
    YY = mont_mul_lazy_hw(Y1, Y1)
    Z3 = 2 * Y1              # shift
    Z3 = lazy_subtraction_N_hw(Z3)

    # [Wait 1] M = 3XX
    two_XX = lazy_add(XX, XX)
    M      = lazy_add(XX, two_XX)

    # [Slot 2]
    S_base = mont_mul_lazy_hw(X1, YY)
    T      = mont_mul_lazy_hw(M, M)

    # [Wait 2]
    S_2   = lazy_add(S_base, S_base)
    S     = lazy_add(S_2, S_2)
    two_S = lazy_add(S, S)
    X3    = lazy_subtraction_2N_hw(T, two_S)
    temp  = lazy_subtraction_2N_hw(S, X3)

    # [Slot 3]
    U    = mont_mul_lazy_hw(M, temp)
    YYYY = mont_mul_lazy_hw(YY, YY)
    X3   = lazy_subtraction_N_hw(X3)
    X3   = lazy_subtraction_N_hw(X3)

    # [Final]
    Y_2 = lazy_add(YYYY, YYYY)
    Y_4 = lazy_add(Y_2, Y_2)
    Y_8 = lazy_add(Y_4, Y_4)
    Y3  = lazy_subtraction_2N_hw(U, Y_8)
    Y3  = lazy_subtraction_N_hw(Y3)
    Y3  = lazy_subtraction_N_hw(Y3)

    return X3, Y3, Z3

# Mixed Add with lazy reduction 
def mixed_add_hw(X1, Y1, Z1, X2, Y2, Z2):
    # stage0
    Z2_square = mont_mul_lazy_hw(Z2, Z2)

    # stage1
    Z2_cubed  = mont_mul_lazy_hw(Z2, Z2_square)
    U1 = mont_mul_lazy_hw(X1, Z2_square)
    H  = lazy_subtraction_2N_hw(X2, U1)

    # stage2
    S1 = mont_mul_lazy_hw(Y1, Z2_cubed)
    H_sqaure = mont_mul_lazy_hw(H, H)
    r = lazy_subtraction_2N_hw(Y2, S1)

    # stage3
    Z3 = mont_mul_lazy_hw(Z2, H)
    H_cubed = mont_mul_lazy_hw(H_sqaure, H)

    # stage 4
    V = mont_mul_lazy_hw(U1, H_sqaure)
    r_square = mont_mul_lazy_hw(r, r)
    r_square_minus_H_cubed = lazy_subtraction_3N_hw(r_square, H_cubed)
    r_square_minus_H_cubed_minus_V = lazy_subtraction_3N_hw(r_square_minus_H_cubed, V)
    X3 = lazy_subtraction_3N_hw(r_square_minus_H_cubed_minus_V, V)
    V_minus_X3 = lazy_subtraction_3N_hw(V, X3)

    # stage 5
    W = mont_mul_lazy_hw(S1, H_cubed)
    Y_part = mont_mul_lazy_hw(r, V_minus_X3)
    Y3 = lazy_subtraction_3N_hw(Y_part, W)

    # final_sub (2번씩 빼서 완벽한 N 이하로 리덕션)
    Y3 = lazy_subtraction_N_hw(Y3)
    Y3 = lazy_subtraction_N_hw(Y3)
    Z3 = lazy_subtraction_N_hw(Z3)
    Z3 = lazy_subtraction_N_hw(Z3)
    X3 = lazy_subtraction_N_hw(X3)
    X3 = lazy_subtraction_N_hw(X3)
    return X3, Y3, Z3

def main():
    NUM_TESTS = 100000
    db_test_count = 0
    outfile = "ecc_test_vectors.hex"

    random.seed(42)
    with open(outfile, "w") as f:

        # mixed_doubling test
        for _ in range(NUM_TESTS//2):
            # affine points 
            x1 = random.randint(0, N-1)
            y1 = random.randint(0, N-1)
            z1 = 1 # affine 

            # jacobian points (same as x1,y1,z1)
            z2 = random.randint(0, N-1)
            x2 = (x1 * pow(z2,2,N)) % N
            y2 = (y1 * pow(z2,3,N)) % N

            X1 = mont_domain_conversion(x1)
            Y1 = mont_domain_conversion(y1)
            Z1 = mont_domain_conversion(z1)
            X2 = mont_domain_conversion(x2)
            Y2 = mont_domain_conversion(y2)
            Z2 = mont_domain_conversion(z2)

            X3,Y3,Z3 = point_double_z1_hw(X1,Y1)
            f.write(f"{X1:064x}_{Y1:064x}_{Z1:064x}_{X2:064x}_{Y2:064x}_{Z2:064x}_{X3:064x}_{Y3:064x}_{Z3:064x}\n")

        # mixed_add test_vectors
        for _ in range(NUM_TESTS//2):

            # affine points 
            x1 = random.randint(0, N-1)
            y1 = random.randint(0, N-1)
            z1 = 1 # affine 

            # jacobian points (buckets value)
            x2 = random.randint(0, N-1)
            y2 = random.randint(0, N-1)
            z2 = random.randint(0, N-1)

            X1 = mont_domain_conversion(x1)
            Y1 = mont_domain_conversion(y1)
            Z1 = mont_domain_conversion(z1)
            X2 = mont_domain_conversion(x2)
            Y2 = mont_domain_conversion(y2)
            Z2 = mont_domain_conversion(z2)
            
            X3,Y3,Z3 = mixed_add_hw(X1,Y1,Z1,X2,Y2,Z2)
            f.write(f"{X1:064x}_{Y1:064x}_{Z1:064x}_{X2:064x}_{Y2:064x}_{Z2:064x}_{X3:064x}_{Y3:064x}_{Z3:064x}\n")


    print(f"Generated {NUM_TESTS} test vectors -> {outfile}")

if __name__ == "__main__":
    main()
