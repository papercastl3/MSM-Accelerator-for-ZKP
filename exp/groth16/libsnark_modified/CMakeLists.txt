cmake_minimum_required(VERSION 3.10)
project(ZKP_Hardware_Bench)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(
	    -Wno-deprecated-declarations
	        -Wno-error
		    -Wno-shift-count-overflow
		    )

	    set(CMAKE_BUILD_TYPE Release)

	    # ARM/Kria 설정
	    set(USE_ASM OFF CACHE BOOL "Disable x86 assembly for ARM" FORCE)

	    # OpenMP / multicore
	    set(MULTICORE ON CACHE BOOL "Enable multicore" FORCE)
	    set(WITH_PROCPS OFF CACHE BOOL "Disable memory profiling" FORCE)

	    # Xbyak/JIT 비활성화
	    set(USE_XBYAK OFF CACHE BOOL "Disable Xbyak JIT" FORCE)
	    set(MIE_USE_XBYAK OFF CACHE BOOL "Disable MIE Xbyak" FORCE)
	    set(XBYAK_DISABLE ON CACHE BOOL "Disable Xbyak" FORCE)

	    add_compile_definitions(
		        USE_ASM=0
			    USE_XBYAK=0
			        MIE_USE_XBYAK=0
				    XBYAK_DISABLE
				    MULTICORE=1
				    )

			    # libsnark 빌드
			    add_subdirectory(libsnark)

			    # benchmark 실행파일
			    add_executable(benchmark benchmark_sha256_groth16.cpp)

			    target_compile_definitions(benchmark PRIVATE CURVE_ALT_BN128)

			    target_include_directories(benchmark PRIVATE
				        ${CMAKE_CURRENT_SOURCE_DIR}/libsnark
					    ${CMAKE_CURRENT_SOURCE_DIR}/libsnark/depends/libff
					    )

				    find_package(OpenMP REQUIRED)

				    target_link_libraries(benchmark
					        PRIVATE
						    snark
						        ff
							    gmp
							        OpenMP::OpenMP_CXX
								)
