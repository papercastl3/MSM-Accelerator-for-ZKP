import random

# 하드웨어 파라미터
N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013
W, K = 17, 15
R = 2**(W * K)
TWO_N = 2 * N
THREE_N = 3 * N
N_inv = pow(-N % R, -1, R)

def mont_conversion(x):
    T = x * (R**2)
    M = (T * N_inv) % R
    Redc = ((T + M*N) // R) % N
    return Redc

def mont_mul_lazy(x, y):
    T = x * y
    M = (T * N_inv) % R
    return (T + M * N) // R 

def lazy_sub(x, y, mod):
    res = x - y
    return res + mod if res < 0 else res

def mixed_add_reference(x1, y1, z1, x2, y2, z2):
    # Stage 0
    z2_sq = mont_mul_lazy(z2, z2)
    # Stage 1
    z2_cb = mont_mul_lazy(z2, z2_sq)
    u1 = mont_mul_lazy(x1, z2_sq)
    h = lazy_sub(x2, u1, TWO_N)
    # Stage 2
    s1 = mont_mul_lazy(y1, z2_cb)
    h_sq = mont_mul_lazy(h, h)
    r = lazy_sub(y2, s1, TWO_N)
    # Stage 3
    z3 = mont_mul_lazy(z2, h)
    h_cb = mont_mul_lazy(h_sq, h)
    # Stage 4
    v = mont_mul_lazy(u1, h_sq)
    r_sq = mont_mul_lazy(r, r)
    t_x3 = lazy_sub(lazy_sub(lazy_sub(r_sq, h_cb, THREE_N), v, THREE_N), v, THREE_N)
    # Stage 5
    v_minus_x3 = lazy_sub(v, t_x3, THREE_N)
    y_part = mont_mul_lazy(r, v_minus_x3)
    t_y3 = lazy_sub(y_part, mont_mul_lazy(s1, h_cb), THREE_N)
    
    # Final Reduction (N 미만으로 보정)
    def to_n(val):
        tmp = val
        while tmp >= N: tmp -= N
        return tmp

    return to_n(t_x3), to_n(t_y3), to_n(z3)

# ==========================================
# 단일 파일 생성 로직
# ==========================================
NUM_TESTS = 1000
OUTPUT_FILE = "ecc_mixed_add_test_vectors.hex"

with open(OUTPUT_FILE, "w") as f:
    for i in range(NUM_TESTS):
        # Mixed Add가 성립하도록 x1 != x2 보장 (더블링/무한대점 회피)
        x1_val = mont_conversion(random.getrandbits(254) % N)
        x2_val = mont_conversion(random.getrandbits(254) % N)
        while x1_val == x2_val: 
            x2_val = mont_conversion(random.getrandbits(254) % N)
        
        y1_val = mont_conversion(random.getrandbits(254) % N)
        y2_val = mont_conversion(random.getrandbits(254) % N)
        z1_val = mont_conversion(1) % N
        z2_val = mont_conversion(random.getrandbits(254) % N)

        x3_ref, y3_ref, z3_ref = mixed_add_reference(x1_val, y1_val, z1_val, x2_val, y2_val, z2_val)
        
        # x1_y1_z1_x2_y2_z2_x3_y3_z3 순서로 한 줄에 9개(64자리 헥스) 데이터를 연결
        # 총 9 * 256 = 2304비트가 한 줄에 기록됨
        f.write(f"{x1_val:064x}_{y1_val:064x}_{z1_val:064x}_{x2_val:064x}_{y2_val:064x}_{z2_val:064x}_{x3_ref:064x}_{y3_ref:064x}_{z3_ref:064x}\n")

print(f"Generated {NUM_TESTS} Mixed-Add vectors into '{OUTPUT_FILE}'.")