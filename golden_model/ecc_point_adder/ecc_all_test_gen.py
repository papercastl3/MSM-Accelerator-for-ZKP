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

# Affine ECC 점 덧셈
def affine_add(x1, y1, x2, y2):
    lamda = (y2 - y1) * pow(x2 - x1, -1, N) % N
    x3 = (lamda**2 - x1 - x2) % N
    y3 = (lamda*(x1 - x3) - y1) % N
    return x3, y3

# Affine ECC 점 배가
def affine_double(x, y):
    lamda = (3 * x**2) * pow(2 * y, -1, N) % N
    x3 = (lamda**2 - 2 * x) % N
    y3 = (lamda*(x - x3) - y) % N
    return x3, y3

def jacobian_conversion(x, y, z):
    z_square = (z * z) % N
    z_cubed  = (z_square * z) % N
    x_jac = (x * z_square) % N
    y_jac = (y * z_cubed) % N
    z_jac = z % N
    return x_jac, y_jac, z_jac

def mont_domain_conversion(x):
    return (x * (R**2) * R_inv) % N

def mont_domain_exit(x):
    return (x * 1 * R_inv) % N

def mont_mul_lazy_hw(x, y):
    T = x * y
    M = (T * N_INV_MOD_R) % R
    redc = (T + M * N) // R 
    return redc & MAX_255

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
def point_double_hw(X1, Y1, Z1):
    XX = mont_mul_lazy_hw(X1, X1)
    YY = mont_mul_lazy_hw(Y1, Y1)
    two_Y1 = 2 * Y1
    Z3     = mont_mul_lazy_hw(two_Y1, Z1)
    YYYY   = mont_mul_lazy_hw(YY, YY)
    two_XX = lazy_add(XX, XX)
    M      = lazy_add(XX, two_XX)
    S_base = mont_mul_lazy_hw(X1, YY)
    T      = mont_mul_lazy_hw(M, M)
    Z3     = lazy_subtraction_N_hw(Z3)
    S_2   = lazy_add(S_base, S_base)
    S     = lazy_add(S_2, S_2)
    two_S = lazy_add(S, S)
    X3    = lazy_sub(T, two_S)
    temp  = lazy_sub(S, X3)
    U   = mont_mul_lazy_hw(M, temp)
    Y_2 = lazy_add(YYYY, YYYY)
    Y_4 = lazy_add(Y_2, Y_2)
    Y_8 = lazy_add(Y_4, Y_4)
    X3  = lazy_subtraction_N_hw(X3)
    X3  = lazy_subtraction_N_hw(X3)
    Y3 = lazy_sub(U, Y_8)
    Y3 = lazy_subtraction_N_hw(Y3)
    Y3 = lazy_subtraction_N_hw(Y3)
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

    # [수정] 모듈러 연산으로 논리 동치 완벽 체크
    if H % N == 0:
        if r % N == 0: # 동일한 점이므로 Doubling으로 분기
            return point_double_hw(X1, Y1, Z1)
        else:          # 덧셈 역원 관계이므로 무한원점(0,0,0) 반환
            return 0, 0, 0
            
    # 일반 Mixed Add 진행
    Z3 = mont_mul_lazy_hw(Z2, H)
    H_cubed = mont_mul_lazy_hw(H_sqaure, H)
    V = mont_mul_lazy_hw(U1, H_sqaure)
    r_square = mont_mul_lazy_hw(r, r)
    r_square_minus_H_cubed = lazy_subtraction_3N_hw(r_square, H_cubed)
    r_square_minus_H_cubed_minus_V = lazy_subtraction_3N_hw(r_square_minus_H_cubed, V)
    X3 = lazy_subtraction_3N_hw(r_square_minus_H_cubed_minus_V, V)
    V_minus_X3 = lazy_subtraction_3N_hw(V, X3)
    W = mont_mul_lazy_hw(S1, H_cubed)
    Y_part = mont_mul_lazy_hw(r, V_minus_X3)
    Y3 = lazy_subtraction_3N_hw(Y_part, W)

    Y3 = lazy_subtraction_N_hw(Y3)
    Y3 = lazy_subtraction_N_hw(Y3)
    Z3 = lazy_subtraction_N_hw(Z3)
    Z3 = lazy_subtraction_N_hw(Z3)
    X3 = lazy_subtraction_N_hw(X3)
    X3 = lazy_subtraction_N_hw(X3)
    return X3, Y3, Z3

# 최상위 하드웨어 래퍼 (Wrapper)
def FPGA_ECC_point_adder(X1, Y1, Z1, X2, Y2, Z2):
    # [수정] 입력이 영점일 경우 상대방 점을 Bypass 하도록 논리 교정
    if Z1 == 0:
        return X2, Y2, Z2
    if Z2 == 0:
        return X1, Y1, Z1
        
    # 두 점 모두 유효하면 Mixed Adder (내부에서 Doubling/Infinity 자동 분기)
    return mixed_add_hw(X1, Y1, Z1, X2, Y2, Z2)
    

def main():
    NUM_TESTS = 1000000
    outfile = "all_covering_test_vectors.hex"
    random.seed(42)
    
    with open(outfile, "w") as f:
        f.write(f"{NUM_TESTS}\n")
        
        for _ in range(NUM_TESTS):
            rand_type = random.random()
            
            # --- 1. 확률적 분기를 통한 모든 케이스 입력 점 생성 ---
            if rand_type < 0.01:    # Case 1: P1이 영점 (1%)
                x1, y1 = 0, 0
                x2 = random.randint(1, N - 1)
                y2 = random.randint(1, N - 1)
                
            elif rand_type < 0.02:  # Case 2: P2가 영점 (1%)
                x1 = random.randint(1, N - 1)
                y1 = random.randint(1, N - 1)
                x2, y2 = 0, 0
                
            elif rand_type < 0.20:  # Case 3: 동일한 점 (배가 연산, 18%)
                x1 = random.randint(1, N - 1)
                y1 = random.randint(1, N - 1)
                x2, y2 = x1, y1       # x2=x1, y2=y1
                
            elif rand_type < 0.38:  # Case 4: 대칭점 (덧셈 역원, 18%)
                x1 = random.randint(1, N - 1)
                y1 = random.randint(1, N - 1)
                x2 = x1
                y2 = N - y1           # y축 대칭 (모듈러 역원)
                
            else:                   # Case 5: 일반 덧셈 (62%)
                x1 = random.randint(1, N - 1)
                y1 = random.randint(1, N - 1)
                x2 = random.randint(1, N - 1)
                y2 = random.randint(1, N - 1)

            # --- 2. 하드웨어 입력 맵핑 (영점일 경우 명시적으로 0, 0, 0 주입) ---
            if x1 == 0 and y1 == 0:
                X1, Y1, Z1 = 0, 0, 0
            else:
                X1 = mont_domain_conversion(x1)
                Y1 = mont_domain_conversion(y1)
                Z1 = mont_domain_conversion(1)

            if x2 == 0 and y2 == 0:
                X2, Y2, Z2 = 0, 0, 0
            else:
                z2 = random.randint(1, N - 1)
                x2_jac, y2_jac, z2_jac = jacobian_conversion(x2, y2, z2)
                X2 = mont_domain_conversion(x2_jac)
                Y2 = mont_domain_conversion(y2_jac)
                Z2 = mont_domain_conversion(z2_jac)

            # 🚨 들여쓰기 원복 구간: if ~ else 블록 바깥으로 빼야 정상 동작합니다!
            
            # --- 3. 하드웨어 연산 수행 ---
            X3, Y3, Z3 = FPGA_ECC_point_adder(X1, Y1, Z1, X2, Y2, Z2)
            
            our_x3_jac = mont_domain_exit(X3)
            our_y3_jac = mont_domain_exit(Y3)
            our_z3 = mont_domain_exit(Z3)

            # 하드웨어 결과를 Affine으로 복원
            if our_z3 != 0:
                z_inv = pow(our_z3, -1, N)       
                z_inv_sq = (z_inv * z_inv) % N   
                z_inv_cu = (z_inv_sq * z_inv) % N 
                our_x3 = (our_x3_jac * z_inv_sq) % N
                our_y3 = (our_y3_jac * z_inv_cu) % N
            else:
                our_x3, our_y3 = 0, 0

            # --- 4. Python Affine 정답 연산 ---
            if x1 == 0 and y1 == 0:
                true_x3, true_y3 = x2, y2
            elif x2 == 0 and y2 == 0:
                true_x3, true_y3 = x1, y1
            elif x1 != x2:
                true_x3, true_y3 = affine_add(x1, y1, x2, y2)
            elif y1 == y2:
                if y1 == 0:
                    true_x3, true_y3 = 0, 0
                else:
                    true_x3, true_y3 = affine_double(x1, y1)
            else:
                # [대칭점 확인] x1 == x2 인데 y1 != y2 인 경우 (무한원점)
                true_x3, true_y3 = 0, 0
                
            # --- 5. 크로스 체크 ---
            if true_x3 != our_x3 or true_y3 != our_y3:
                print(f"[Error!] Expected ({true_x3:x}, {true_y3:x}), Got ({our_x3:x}, {our_y3:x})")
                
            # --- 6. 테스트 벡터 파일 쓰기 ---
            # 포맷: X1_Y1_Z1_X2_Y2_Z2_X3_Y3_Z3 (모두 256비트 Hex 문자열)
            f.write(f"{X1:064x}_{Y1:064x}_{Z1:064x}_{X2:064x}_{Y2:064x}_{Z2:064x}_{X3:064x}_{Y3:064x}_{Z3:064x}\n")

    print(f"Generated {NUM_TESTS} test vectors -> {outfile}")

if __name__ == "__main__":
    main()