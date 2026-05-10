import time

# start_time = time.perf_counter()

# 하드웨어 파라미터
W = 17
K = 15
# R = 2^(W*K) = 2^255
R = 2**(W * K) 
N = 0x2523648240000001BA344D80000000086121000000000013A700000000000013

R_inv = pow(R, -1, N)

# tb_case_1 : 경계 값 
X = N-1
Y = N-1
golden_result = (X * Y * R_inv) % N
golden_result2 = (X * Y * R_inv) % N + N
print(f"tb_1 : 하드웨어가 뱉어야 할 정답 (Hex): {hex(golden_result)}")
# answer : 0xfc324f3523e22fb8ff38a9daad048050c61a2802e9ac3516fec55d39eda7679
print(f"tb_1 : 하드웨어가 뱉어야 할 정답 (뺄셈 제외) (Hex): {hex(golden_result2)}")
# answer : 0x34e68975923e22fd4a27d81daad0480d6d82a2802e9ac36516ec55d39eda768c

# tb_case_2 : 0 
X = 0
Y = N-1
golden_result = (X * Y * R_inv) % N
golden_result2 = (X * Y * R_inv) % N + N
print(f"tb_2 : tb_1 : 하드웨어가 뱉어야 할 정답 (Hex): {hex(golden_result)}")
print(f"tb_2 : 하드웨어가 뱉어야 할 정답 (뺄셈 제외) (Hex): {hex(golden_result2)}")
# answer : 0

# tb_case_3 : 0 
X = N-1
Y = 0
golden_result = (X * Y * R_inv) % N
golden_result2 = (X * Y * R_inv) % N + N
print(f"tb_3 : tb_1 : 하드웨어가 뱉어야 할 정답 (Hex): {hex(golden_result)}")
print(f"tb_3 : 하드웨어가 뱉어야 할 정답 (뺄셈 제외) (Hex): {hex(golden_result2)}")
# answer : 0

# tb_case_3 : 항등원 테스트
X = 1
Y = R % N
print(hex(Y))
golden_result = (X * Y * R_inv) % N
golden_result2 = (X * Y * R_inv) % N + N
print(f"tb_4 : tb_1 : 하드웨어가 뱉어야 할 정답 (Hex): {hex(golden_result)}")
# 1
print(f"tb_4 : 하드웨어가 뱉어야 할 정답 (뺄셈 제외) (Hex): {hex(golden_result2)}")
# 0x2523648240000001ba344d80000000086121000000000013a700000000000014

#X = 2^252 (가장 단순한 253비트 숫자)
        
#Y = 2^252 + 모두 1로 채워진 값 (극단적인 253비트 숫자)
Y = 0x1ffffffffffffffffffacdffffffffffffffffffffffffffffffffffffffffff
# R의 모듈러 역원 구하기 (R^-1 mod N)

