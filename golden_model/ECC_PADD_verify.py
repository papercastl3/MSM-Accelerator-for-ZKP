from multiprocessing import Pool
import random
# Mixed Add with lazy Reduction 기법 검증 테스트 -> 통과?
# 하드웨어 파라미터
N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013
W = 17
K = 15
# R = 2^(W*K) = 2^255
R = 2**(W * K)
R_inv = pow(R, -1, N) 


TWO_N = 2*N
THREE_N = TWO_N + N

def mont_domain_conversion(x):
    return (x * (R**2) * R_inv) % N

def jacobian_conversion(x):
    return (x * (R**2) * R_inv) % N

def mont_mul(x,y):
    return (x * y * R_inv) % N

def mont_mul_lazy(x,y):
    T = x*y
    N_inv = pow(-N % R, -1, R)
    M = (T * N_inv) % R
    redc = (T + M*N) // R 
    return redc

# A mod N
def lazy_subtraction_N(x):
    if(x-N<0):
        return x
    return x-N

# A - B mod 2N
def lazy_subtraction_2N(x,y):
    if(x-y<0):
        return x-y + TWO_N
    return x-y

# A - B mod 3N
def lazy_subtraction_3N(x,y):
    if(x-y<0):
        return x-y + THREE_N
    return x-y

# Mixed Add with lazy reduction
def mixed_add_lazy_sub(x1,y1,z1,x2,y2,z2) :
    # 1. 몽고메리 도메인 변환
    # X1 = mont_domain_conversion(x1)
    # Y1 = mont_domain_conversion(y1)
    # Z1 = mont_domain_conversion(z1)
    # X2 = mont_domain_conversion(x2)
    # Y2 = mont_domain_conversion(y2)
    # Z2 = mont_domain_conversion(z2)

    X1 = x1
    Y1 = y1
    Z1 = z1
    X2 = x2
    Y2 = y2
    Z2 = z2

    # 2. Jacobian- Affine Mixed ADD
    # stage 0
    Z2_square= mont_mul_lazy(Z2, Z2)

    # stage 1
    Z2_cubed= mont_mul_lazy(Z2, Z2_square)
    U1 = mont_mul_lazy(X1, Z2_square)
    H = lazy_subtraction_2N(X2, U1)

    # stage 2
    S1 = mont_mul_lazy(Y1, Z2_cubed)
    H_sqaure = mont_mul_lazy(H, H)
    r = lazy_subtraction_2N(Y2, S1)

    # stage 3
    Z3 = mont_mul_lazy(Z2, H)
    H_cubed = mont_mul_lazy(H_sqaure, H)

    # stage 4
    V = mont_mul_lazy(U1, H_sqaure)
    r_square = mont_mul_lazy(r, r)
    r_square_minus_H_cubed = lazy_subtraction_3N(r_square, H_cubed)
    r_square_minus_H_cubed_minus_V = lazy_subtraction_3N(r_square_minus_H_cubed, V)
    X3 = lazy_subtraction_3N(r_square_minus_H_cubed_minus_V, V)
    V_minus_X3 = lazy_subtraction_3N (V, X3)

    # stage 5
    W = mont_mul_lazy(S1, H_cubed)
    Y_part = mont_mul_lazy(r, V_minus_X3)
    Y3 = lazy_subtraction_3N(Y_part, W)

    # final_sub
    Y3 = lazy_subtraction_N(Y3)
    Y3 = lazy_subtraction_N(Y3)
    Z3 = lazy_subtraction_N(Z3)
    Z3 = lazy_subtraction_N(Z3)
    X3 = lazy_subtraction_N(X3)
    X3 = lazy_subtraction_N(X3)

    return X3,Y3,Z3

# Mixed Add without lazy reduction
def mixed_add(x1,y1,z1,x2,y2,z2) :
    # 1. 몽고메리 도메인 변환
    X1 = mont_domain_conversion(x1)
    Y1 = mont_domain_conversion(y1)
    Z1 = mont_domain_conversion(z1)
    X2 = mont_domain_conversion(x2)
    Y2 = mont_domain_conversion(y2)
    Z2 = mont_domain_conversion(z2)

    # 2. Mixed ADD
    # stage 0
    Z2_square= mont_mul(Z2, Z2)

    # stage 1
    Z2_cubed= mont_mul(Z2, Z2_square)
    U1 = mont_mul(X1, Z2_square)
    H = (X2 - U1) % N

    # stage 2
    S1 = mont_mul(Y1, Z2_cubed)
    H_sqaure = mont_mul(H, H)
    r = (Y2 - S1) % N

    # stage 3
    Z3 = mont_mul(Z2, H)
    H_cubed = mont_mul(H_sqaure, H)

    # stage 4
    V = mont_mul(U1, H_sqaure)
    r_square = mont_mul(r, r)
    r_square_minus_H_cubed = (r_square - H_cubed) % N
    r_square_minus_H_cubed_minus_V = (r_square_minus_H_cubed - V) % N
    X3 = (r_square_minus_H_cubed_minus_V - V) % N
    V_minus_X3 = (V - X3) % N

    # stage 5
    W = mont_mul(S1, H_cubed)
    Y_part = mont_mul(r, V_minus_X3)
    Y3 = (Y_part - W) % N

    return X3,Y3,Z3


x1 = 0x12345678
y1 = 0xABCDEF 
z1 = 0x1   
        
x2 = 0x87654321
y2 = 0xFEDCBA 
z2 = 0x1     

x3,y3,z3 = mixed_add_lazy_sub(x1,y1,z1,x2,y2,z2)
print(f"x3 : {hex(x3)}")
print(f"y3 : {hex(y3)}")
print(f"z3 : {hex(z3)}")
0xfd78a65b768093fec32f28831dd6609240b7c0ade906d4e736bb2d93e76f918
0xfd78a65b768093fec32f28831dd6609240b7c0ade906d4e736bb2d93e76f918

# def rand_test(test_idx):
#     """
#     각 프로세스가 독립적으로 실행할 테스트 함수
#     test_idx: map에서 넘겨주는 루프 인덱스
#     """
#     # 매번 새로운 시드를 생성하여 랜덤성을 보장 (멀티프로세싱 대응)
#     random.seed() 
    
#     x1 = random.randint(0, N - 1)
#     y1 = random.randint(0, N - 1)
#     z1 = 1
#     x2 = random.randint(0, N - 1)
#     y2 = random.randint(0, N - 1)
#     z2 = random.randint(0, N - 1)

#     real_res = mixed_add(x1, y1, z1, x2, y2, z2)
#     our_res = mixed_add_lazy_sub(x1, y1, z1, x2, y2, z2)

#     if real_res != our_res:
#         # PDBL 케이스인지 확인
#         # (실제 하드웨어 로직에서는 H=0 조건을 체크해야 함)
#         if x1 == x2 and y1 == y2:
#             return "PDBL"
#         else:
#             # 실패 시 입력 벡터를 리턴하여 메인에서 확인 가능하게 함
#             return (False, (x1, y1, x2, y2, z2))
    
#     return True

# if __name__ == "__main__":
#     TEST_COUNT = 1000000
#     print(f"{TEST_COUNT}회 병렬 테스트 시작 (멀티코어 가동)...")

#     with Pool() as p:
#         # range(TEST_COUNT)를 통해 인덱스를 하나씩 던져줍니다.
#         results = p.map(rand_test, range(TEST_COUNT))

#     # 결과 분석
#     passed = results.count(True)
#     pdbl = results.count("PDBL")
#     failed = [r for r in results if isinstance(r, tuple)]

#     print("\n" + "="*40)
#     print(f" Total Passed: {passed}")
#     print(f" PDBL Skipped: {pdbl}")
#     print(f" Total Failed: {len(failed)}")
#     print("="*40)

#     if failed:
#         print("\n첫 번째 실패 케이스 입력값:")
#         f_in = failed[0][1]
#         print(f"x1: {hex(f_in[0])}\ny1: {hex(f_in[1])}\nx2: {hex(f_in[2])}\ny2: {hex(f_in[3])}\nz2: {hex(f_in[4])}")