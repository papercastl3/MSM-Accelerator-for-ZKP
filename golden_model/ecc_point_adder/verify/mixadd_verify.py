import random
from multiprocessing import Pool

# 하드웨어 파라미터
N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013
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

def mont_mul(x,y):
    return (x * y * R_inv) % N

# =============== 하드웨어 모방 함수들 (Hardware Mimic) ===============
# 255비트를 넘어가는 순간 MAX_255 마스킹을 통해 앞 비트를 날려버립니다.

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

# ====================================================================

# Mixed Add with lazy reduction 
def mixed_add_lazy_sub(x1, y1, z1, x2, y2, z2):
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)
    Z1 = mont_domain_conversion(z1)
    X2 = mont_domain_conversion(x2)
    Y2 = mont_domain_conversion(y2)
    Z2 = mont_domain_conversion(z2)

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

# Reference 함수 
def mixed_add(x1,y1,z1,x2,y2,z2):
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)
    Z1 = mont_domain_conversion(z1)
    X2 = mont_domain_conversion(x2)
    Y2 = mont_domain_conversion(y2)
    Z2 = mont_domain_conversion(z2)

    Z2_square = mont_mul(Z2, Z2)
    Z2_cubed  = mont_mul(Z2, Z2_square)
    U1 = mont_mul(X1, Z2_square)
    H = (X2 - U1) % N
    S1 = mont_mul(Y1, Z2_cubed)
    H_sqaure = mont_mul(H, H)
    r = (Y2 - S1) % N
    Z3 = mont_mul(Z2, H)
    H_cubed = mont_mul(H_sqaure, H)
    V = mont_mul(U1, H_sqaure)
    r_square = mont_mul(r, r)
    
    r_square_minus_H_cubed = (r_square - H_cubed) % N
    r_square_minus_H_cubed_minus_V = (r_square_minus_H_cubed - V) % N
    X3 = (r_square_minus_H_cubed_minus_V - V) % N
    V_minus_X3 = (V - X3) % N
    
    W = mont_mul(S1, H_cubed)
    Y_part = mont_mul(r, V_minus_X3)
    Y3 = (Y_part - W) % N

    return X3, Y3, Z3

# 가장 빡센 값(Edge Cases) 추출기
def get_hardcore_value():
    choices = [0, 1, N - 1, N // 2, random.randint(0, N - 1)]
    return random.choice(choices)

def rand_test(test_idx):
    random.seed() 
    
    # 초반 1만 번은 오버플로우/언더플로우를 유도하는 빡센 값들의 조합으로만 융단폭격
    if test_idx < 10000:
        x1 = get_hardcore_value()
        y1 = get_hardcore_value()
        z1 = 1
        x2 = get_hardcore_value()
        y2 = get_hardcore_value()
        z2 = get_hardcore_value()
    else:
        # 나머지는 완전 무작위 테스트
        x1 = random.randint(0, N - 1)
        y1 = random.randint(0, N - 1)
        z1 = 1
        x2 = random.randint(0, N - 1)
        y2 = random.randint(0, N - 1)
        z2 = random.randint(0, N - 1)

    real_res = mixed_add(x1, y1, z1, x2, y2, z2)
    our_res = mixed_add_lazy_sub(x1, y1, z1, x2, y2, z2)

    if real_res != our_res:
        if x1 == x2 and y1 == y2:
            return "PDBL"
        else:
            return (False, (x1, y1, x2, y2, z2))
    
    return True

