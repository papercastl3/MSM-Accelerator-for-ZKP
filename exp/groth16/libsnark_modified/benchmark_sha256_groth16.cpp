#include <libff/common/default_types/ec_pp.hpp>
#include <libsnark/zk_proof_systems/ppzksnark/r1cs_gg_ppzksnark/r1cs_gg_ppzksnark.hpp>
#include <libsnark/relations/constraint_satisfaction_problems/r1cs/examples/r1cs_examples.hpp>
#include <iostream>
#include <fstream>
#include <chrono>

using namespace std;

int main() {
    // 🔍 1. 내장 프로파일러 활성화 (MSM 소요 시간 상세 추적)
    libff::inhibit_profiling_info = false;
    libff::inhibit_profiling_counters = false;

    // 타원 곡선 파라미터 초기화
    libff::default_ec_pp::init_public_params();

    // =================================================================
    // 🛠️ 2. 하드웨어 스트레스 테스트용 Dense 회로 생성
    // =================================================================
    const int NUM_CONSTRAINTS = 262144;    //  원하는 데이터 개수만큼 조절 가능
    // const int NUM_CONSTRAINTS = 65536;    // 2^16 
    //const int NUM_CONSTRAINTS = 1048576;  // 2^20 
    const int NUM_INPUTS = 10;
    cout << "🛠️ [하드웨어 스트레스 테스트용] 공식 R1CS 벤치마크 데이터 생성 중..." << endl;
    
    // 254비트 완벽한 난수로 채워진 65536개의 데이터셋 생성
    libsnark::r1cs_example<libff::alt_bn128_Fr> example = 
        libsnark::generate_r1cs_example_with_field_input<libff::alt_bn128_Fr>(NUM_CONSTRAINTS, NUM_INPUTS);
    cout << " ✅ 생성 완료! (제약 조건: " << example.constraint_system.num_constraints() << "개)\n" << endl;

    // =================================================================
    // 🔑 3. 증명 키 생성 및 로드 (Trusted Setup 파일 입출력)
    // =================================================================
    bool GENERATE_NEW_KEYS = true; // 🚨 최초 1회만 true, 파일 생성 후 false로 변경!
    
    libsnark::r1cs_gg_ppzksnark_proving_key<libff::alt_bn128_pp> pk;
    libsnark::r1cs_gg_ppzksnark_verification_key<libff::alt_bn128_pp> vk;

    if (GENERATE_NEW_KEYS) {
        cout << "🔑 [Setup] 새로운 키 쌍 생성 및 파일 저장 중 (약 7초 소요)..." << endl;
        auto keypair = libsnark::r1cs_gg_ppzksnark_generator<libff::alt_bn128_pp>(example.constraint_system);
        pk = keypair.pk;
        vk = keypair.vk;

        std::ofstream pk_out("proving_key.bin", std::ios::binary); pk_out << pk; pk_out.close();
        std::ofstream vk_out("verification_key.bin", std::ios::binary); vk_out << vk; vk_out.close();
    } else {
        cout << "🔑 [Setup] 기존 키 쌍 불러오는 중 (0.1초 소요)..." << endl;
        std::ifstream pk_in("proving_key.bin", std::ios::binary); pk_in >> pk; pk_in.close();
        std::ifstream vk_in("verification_key.bin", std::ios::binary); vk_in >> vk; vk_in.close();
    }

    // =================================================================
    // 🚀 4. 증명 생성 (Prover) & 타이머 측정
    // =================================================================
    cout << "\n🚀 증명 생성 (Prover) 시작 - 데이터 덤프 진행됨!" << endl;
    auto prover_start = std::chrono::high_resolution_clock::now();

    auto proof = libsnark::r1cs_gg_ppzksnark_prover<libff::alt_bn128_pp>(
        pk, 
        example.primary_input, 
        example.auxiliary_input
    );

    auto prover_end = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double> prover_time = prover_end - prover_start;

    // =================================================================
    // 🛡️ 5. 최종 검증 (Verifier)
    // =================================================================
    cout << "\n🛡️ 검증 (Verifier) 시작..." << endl;
    bool is_valid = libsnark::r1cs_gg_ppzksnark_verifier_strong_IC<libff::alt_bn128_pp>(
        vk, 
        example.primary_input, 
        proof
    );

    cout << "===================================================" << endl;
    cout << "📊 [Performance & Result Report]" << endl;
    cout << "⏱️ 전체 Prover 수행 시간 : " << prover_time.count() << " 초" << endl;
    cout << "✅ 최종 검증 결과        : " << (is_valid ? "True (성공)" : "False (실패)") << endl;
    cout << "===================================================" << endl;

    return 0;
}
