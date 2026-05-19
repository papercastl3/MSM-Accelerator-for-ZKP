import random

# 파라미터 정의
N = 0x32523648240000001BA344D80000000086121000000000013A700000000000013
R = 2**255
MAX_255 = (1 << 255) - 1

N_inv = pow(-N % R, -1, R)

def mont_mul_lazy_hw(x, y):
    T = x * y
    M = (T * N_inv) % R
    result = (T + M * N) // R 
    return result & MAX_255 

# ==========================================
# 테스트 벡터 배열 생성 
# ==========================================
NUM_TESTS = 10000
test_vectors = []

# edge 케이스 
edge_cases = [
    (0x23767d65afa086af0d9ea8f040596923fdf9e3fd7d5260ac546f3aa78cfd7f86, 0x23767d65afa086af0d9ea8f040596923fdf9e3fd7d5260ac546f3aa78cfd7f86),
    (0, 0),                           
    (1, 1),                           
    (N - 1, N - 1),                   
    (2 * N - 1, 2 * N - 1),             
    (3 * N - 1, 3 * N - 1),           # 최대 한계치 (3N-1)
    (MAX_255, MAX_255),               # 오버 플로우 발생
    (MAX_255, 0),                     
    (MAX_255, N - 1)                  
]
test_vectors.extend(edge_cases)

remaining_tests = NUM_TESTS - len(test_vectors)
for i in range(remaining_tests):
    category = i % 4  # 4개의 구간으로 분할
    
    if category == 0:
        # [안전 구간] 0 ~ N-1
        x = random.randint(0, N - 1)
        y = random.randint(0, N - 1)
    elif category == 1:
        # [Lazy 구간 1] N ~ 2N-1
        x = random.randint(N, 2 * N - 1)
        y = random.randint(N, 2 * N - 1)
    elif category == 2:
        # [파이프라인 한계 구간] 2N ~ 3N-1 ( 실제 스케줄링 시트 최대치)
        x = random.randint(2 * N, 3 * N - 1)
        y = random.randint(2 * N, 3 * N - 1)
    else:
        # [극한의 오버플로우 구간] 3N ~ MAX_255 (하드웨어 포트 최대치)
        x = random.randint(3 * N, MAX_255)
        y = random.randint(3 * N, MAX_255)
    
    test_vectors.append((x, y))

# ==========================================
# 단일 파일(test_vectors.hex)에 통합 저장
# ==========================================
with open("mont_mul_test_vectors.hex", "w") as f:
    for x_val, y_val in test_vectors:
        result_val = mont_mul_lazy_hw(x_val, y_val)
        f.write(f"{x_val:064x}_{y_val:064x}_{result_val:064x}\n")

print(f"Generated {NUM_TESTS} vectors (Targeting 0~N, N~2N, 2N~3N, 3N~MAX).")