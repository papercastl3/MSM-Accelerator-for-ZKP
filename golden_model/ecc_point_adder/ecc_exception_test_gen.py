import random

# 하드웨어 파라미터
N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013
W = 17
K = 15
R = 2**(W * K)
R_inv = pow(R, -1, N) 

TWO_N = 2 * N
THREE_N = 3 * N

MAX_255 = (1 << 255) - 1
N_INV_MOD_R = pow(-N % R, -1, R)

# [하드웨어 스펙 설정]
EXPECT_HW_ZERO_FLUSH = True

def mont_domain_conversion(x):
    return (x * (R**2) * R_inv) % N

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

# Mixed Add with lazy reduction 
# [성능 최적화] 커버리지 측정을 위해 내부 계산된 H 값을 함께 반환 (X3, Y3, Z3, H)
def mixed_add_hw(X1, Y1, Z1, X2, Y2, Z2):
    Z2_square = mont_mul_lazy_hw(Z2, Z2)
    Z2_cubed  = mont_mul_lazy_hw(Z2, Z2_square)
    U1 = mont_mul_lazy_hw(X1, Z2_square)
    
    # 예외 감지의 핵심 변수 H
    H = lazy_subtraction_2N_hw(X2, U1)
    
    S1 = mont_mul_lazy_hw(Y1, Z2_cubed)
    H_sqaure = mont_mul_lazy_hw(H, H)
    r = lazy_subtraction_2N_hw(Y2, S1)
    Z3 = mont_mul_lazy_hw(Z2, H)
    H_cubed = mont_mul_lazy_hw(H_sqaure, H)
    V = mont_mul_lazy_hw(U1, H_sqaure)
    r_square = mont_mul_lazy_hw(r, r)
    r_square_minus_H_cubed = lazy_subtraction_3N_hw(r_square, H_cubed)
    r_square_minus_H_cubed_minus_V = lazy_subtraction_3N_hw(r_square_minus_H_cubed, V)
    X3 = lazy_subtraction_3N_hw(r_square_minus_H_cubed_minus_V, V)
    V_minus_X3 = lazy_subtraction_3N_hw(V, X3)
    W_val = mont_mul_lazy_hw(S1, H_cubed) 
    Y_part = mont_mul_lazy_hw(r, V_minus_X3)
    Y3 = lazy_subtraction_3N_hw(Y_part, W_val)

    # final_sub
    Y3 = lazy_subtraction_N_hw(Y3)
    Y3 = lazy_subtraction_N_hw(Y3)
    Z3 = lazy_subtraction_N_hw(Z3)
    Z3 = lazy_subtraction_N_hw(Z3)
    X3 = lazy_subtraction_N_hw(X3)
    X3 = lazy_subtraction_N_hw(X3)
    
    return X3, Y3, Z3, H

def main():
    # 원하는 목표 개수 설정 (각각 5000개씩, 총 10000개)
    TARGET_COUNT = 5000
    outfile = "ecc_exception_test_vectors_balanced.hex"

    # Coverage Tracking 변수
    count_H_0 = 0
    count_H_N = 0

    random.seed(42)
    with open(outfile, "w") as f:
        # 두 카운트가 모두 목표치에 도달할 때까지 무한 반복 (Rejection Sampling)
        while count_H_0 < TARGET_COUNT or count_H_N < TARGET_COUNT:
            x1 = random.randint(0, N-1)
            y1 = random.randint(1, N-1) 
            z1 = 1 

            x2_aff = x1
            y2_aff = N - y1 

            z2 = random.randint(1, N-1)
            x2 = (x2_aff * pow(z2, 2, N)) % N
            y2 = (y2_aff * pow(z2, 3, N)) % N

            X1 = mont_domain_conversion(x1)
            Y1 = mont_domain_conversion(y1)
            Z1 = mont_domain_conversion(z1)
            X2 = mont_domain_conversion(x2)
            Y2 = mont_domain_conversion(y2)
            Z2 = mont_domain_conversion(z2)
            
            # 파이썬 S/W 레퍼런스 모델 연산
            X3, Y3, Z3, H_val = mixed_add_hw(X1, Y1, Z1, X2, Y2, Z2)
            
            # --- SW 모델 H_val 분류, 스킵 로직 및 커버리지 측정 ---
            if H_val == 0:
                if count_H_0 >= TARGET_COUNT:
                    continue # 이미 목표치를 채웠으면 스킵 (파일에 안 씀)
                count_H_0 += 1
                case_label = "H_ZERO"
            elif H_val == N:
                if count_H_N >= TARGET_COUNT:
                    continue # 이미 목표치를 채웠으면 스킵
                count_H_N += 1
                case_label = "H_N"
            else:
                raise RuntimeError(f"수학적 증명 위배: 예상치 못한 H 값 ({H_val})")

            # 정합성 검증
            assert Z3 == 0, f"SW 모델 오류: Z3 != 0 ({Z3})"
            
            # 하드웨어 스펙에 맞춘 마스킹
            if Z3 == 0 and EXPECT_HW_ZERO_FLUSH:
                X3 = 0
                Y3 = 0
            
            # 파일 기록 (SystemVerilog $readmemh 호환 주석 포함)
            f.write(f"{X1:064x}_{Y1:064x}_{Z1:064x}_{X2:064x}_{Y2:064x}_{Z2:064x}_{X3:064x}_{Y3:064x}_{Z3:064x} // {case_label}\n")

    # 결과 통계 출력
    total_generated = count_H_0 + count_H_N
    print(f"Generated {total_generated} Balanced Exception Test Vectors -> {outfile}")
    print(f"HW Output Flush Setting: {'Zero Flush (0x00...0)' if EXPECT_HW_ZERO_FLUSH else 'Hold/Garbage'}")
    print("-" * 50)
    print("[ Lazy Reduction Coverage Statistics ]")
    print(f" - H == 0 Cases : {count_H_0} ({(count_H_0/total_generated)*100:.2f}%)")
    print(f" - H == N Cases : {count_H_N} ({(count_H_N/total_generated)*100:.2f}%)")
    print("-" * 50)

if __name__ == "__main__":
    main()