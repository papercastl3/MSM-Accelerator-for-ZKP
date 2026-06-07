/** @file
 *****************************************************************************

 Implementation of interfaces for multi-exponentiation routines.

 See multiexp.hpp .

 *****************************************************************************
 * @author     This file is part of libff, developed by SCIPR Lab
 *             and contributors (see AUTHORS).
 * @copyright  MIT license (see LICENSE file)
 *****************************************************************************/

#ifndef MULTIEXP_TCC_
#define MULTIEXP_TCC_

#include <algorithm>
#include <cassert>
#include <type_traits>
#include <typeinfo>
#include <string>    
#include <fstream>  
#include <iostream>

#include <utility>
#include <vector>
#include <cstdlib> // std::system 호출을 위해 반드시 추가!
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <stdint.h>
#include <cstring>
#include <cstdio>

struct msm_dma_xfer_req {
    uint32_t in_count;
    uint32_t out_count;
};

#define MSM_DMA_MAGIC 'M'
#define MSM_DMA_IOC_XFER           _IOWR(MSM_DMA_MAGIC, 1, msm_dma_xfer_req)
#define MSM_DMA_IOC_GET_PT_PHYS    _IOWR(MSM_DMA_MAGIC, 2, uint32_t)
#define MSM_DMA_IOC_GET_SC_PHYS    _IOWR(MSM_DMA_MAGIC, 3, uint32_t)
#define MSM_DMA_IOC_GET_RX_PHYS    _IOWR(MSM_DMA_MAGIC, 4, uint32_t)
#define MSM_DMA_IOC_GET_DESC_PHYS  _IOWR(MSM_DMA_MAGIC, 5, uint32_t)

#include <libff/algebra/fields/bigint.hpp>
#include <libff/algebra/fields/fp_aux.tcc>
#include <libff/algebra/scalar_multiplication/multiexp.hpp>
#include <libff/algebra/scalar_multiplication/wnaf.hpp>
#include <libff/common/profiling.hpp>
#include <libff/common/utils.hpp>

namespace libff {

template<mp_size_t n>
class ordered_exponent {
// to use std::push_heap and friends later
public:
    size_t idx;
    bigint<n> r;

    ordered_exponent(const size_t idx, const bigint<n> &r) : idx(idx), r(r) {};

    bool operator<(const ordered_exponent<n> &other) const
    {
#if defined(__x86_64__) && defined(USE_ASM)
        if (n == 3)
        {
            long res;
            __asm__
                ("// check for overflow           \n\t"
                 "mov $0, %[res]                  \n\t"
                 ADD_CMP(16)
                 ADD_CMP(8)
                 ADD_CMP(0)
                 "jmp done%=                      \n\t"
                 "subtract%=:                     \n\t"
                 "mov $1, %[res]                  \n\t"
                 "done%=:                         \n\t"
                 : [res] "=&r" (res)
                 : [A] "r" (other.r.data), [mod] "r" (this->r.data)
                 : "cc", "%rax");
            return res;
        }
        else if (n == 4)
        {
            long res;
            __asm__
                ("// check for overflow           \n\t"
                 "mov $0, %[res]                  \n\t"
                 ADD_CMP(24)
                 ADD_CMP(16)
                 ADD_CMP(8)
                 ADD_CMP(0)
                 "jmp done%=                      \n\t"
                 "subtract%=:                     \n\t"
                 "mov $1, %[res]                  \n\t"
                 "done%=:                         \n\t"
                 : [res] "=&r" (res)
                 : [A] "r" (other.r.data), [mod] "r" (this->r.data)
                 : "cc", "%rax");
            return res;
        }
        else if (n == 5)
        {
            long res;
            __asm__
                ("// check for overflow           \n\t"
                 "mov $0, %[res]                  \n\t"
                 ADD_CMP(32)
                 ADD_CMP(24)
                 ADD_CMP(16)
                 ADD_CMP(8)
                 ADD_CMP(0)
                 "jmp done%=                      \n\t"
                 "subtract%=:                     \n\t"
                 "mov $1, %[res]                  \n\t"
                 "done%=:                         \n\t"
                 : [res] "=&r" (res)
                 : [A] "r" (other.r.data), [mod] "r" (this->r.data)
                 : "cc", "%rax");
            return res;
        }
        else
#endif
        {
            return (mpn_cmp(this->r.data, other.r.data, n) < 0);
        }
    }
};

/**
 * multi_exp_inner<T, FieldT, Method>() implementes the specified
 * multiexponentiation method.
 * this implementation relies on some rather arcane template magic:
 * function templates cannot be partially specialized, so we cannot just write
 *     template<typename T, typename FieldT>
 *     T multi_exp_inner<T, FieldT, multi_exp_method_naive>
 * thus we resort to using std::enable_if. the basic idea is that *overloading*
 * is what's actually happening here, it's just that, for any given value of
 * Method, only one of the templates will be valid, and thus the correct
 * implementation will be used.
 */

template<typename T, typename FieldT, multi_exp_method Method,
    typename std::enable_if<(Method == multi_exp_method_naive), int>::type = 0>
T multi_exp_inner(
    typename std::vector<T>::const_iterator vec_start,
    typename std::vector<T>::const_iterator vec_end,
    typename std::vector<FieldT>::const_iterator scalar_start,
    typename std::vector<FieldT>::const_iterator scalar_end)
{
    T result(T::zero());

    typename std::vector<T>::const_iterator vec_it;
    typename std::vector<FieldT>::const_iterator scalar_it;

    for (vec_it = vec_start, scalar_it = scalar_start; vec_it != vec_end; ++vec_it, ++scalar_it)
    {
        bigint<FieldT::num_limbs> scalar_bigint = scalar_it->as_bigint();
        result = result + opt_window_wnaf_exp(*vec_it, scalar_bigint, scalar_bigint.num_bits());
    }
    assert(scalar_it == scalar_end);

    return result;
}


template<typename T, typename FieldT, multi_exp_method Method,
    typename std::enable_if<(Method == multi_exp_method_naive_plain), int>::type = 0>
T multi_exp_inner(
    typename std::vector<T>::const_iterator vec_start,
    typename std::vector<T>::const_iterator vec_end,
    typename std::vector<FieldT>::const_iterator scalar_start,
    typename std::vector<FieldT>::const_iterator scalar_end)
{
    T result(T::zero());

    typename std::vector<T>::const_iterator vec_it;
    typename std::vector<FieldT>::const_iterator scalar_it;

    for (vec_it = vec_start, scalar_it = scalar_start; vec_it != vec_end; ++vec_it, ++scalar_it)
    {
        result = result + (*scalar_it) * (*vec_it);
    }
    assert(scalar_it == scalar_end);

    return result;
}


template<typename T, typename FieldT, multi_exp_method Method,
    typename std::enable_if<(Method == multi_exp_method_BDLO12), int>::type = 0>
T multi_exp_inner(
    typename std::vector<T>::const_iterator bases,
    typename std::vector<T>::const_iterator bases_end,
    typename std::vector<FieldT>::const_iterator exponents,
    typename std::vector<FieldT>::const_iterator exponents_end)
{
    UNUSED(exponents_end);
    size_t length = bases_end - bases;
    size_t log2_length = log2(length);
    size_t c = log2_length - (log2_length / 3 - 2);

    const mp_size_t exp_num_limbs =
        std::remove_reference<decltype(*exponents)>::type::num_limbs;
    std::vector<bigint<exp_num_limbs> > bn_exponents(length);
    size_t num_bits = 0;

    for (size_t i = 0; i < length; i++)
    {
        bn_exponents[i] = exponents[i].as_bigint();
        num_bits = std::max(num_bits, bn_exponents[i].num_bits());
    }

    size_t num_groups = (num_bits + c - 1) / c;

    T result;
    bool result_nonzero = false;

    for (size_t k = num_groups - 1; k <= num_groups; k--)
    {
        if (result_nonzero)
        {
            for (size_t i = 0; i < c; i++)
            {
                result = result.dbl();
            }
        }

        std::vector<T> buckets(1 << c);
        std::vector<bool> bucket_nonzero(1 << c);

        for (size_t i = 0; i < length; i++)
        {
            size_t id = 0;
            for (size_t j = 0; j < c; j++)
            {
                if (bn_exponents[i].test_bit(k*c + j))
                {
                    id |= 1 << j;
                }
            }

            if (id == 0)
            {
                continue;
            }

            if (bucket_nonzero[id])
            {
#ifdef USE_MIXED_ADDITION
                buckets[id] = buckets[id].mixed_add(bases[i]);
#else
                buckets[id] = buckets[id] + bases[i];
#endif
            }
            else
            {
                buckets[id] = bases[i];
                bucket_nonzero[id] = true;
            }
        }

#ifdef USE_MIXED_ADDITION
        batch_to_special(buckets);
#endif

        T running_sum;
        bool running_sum_nonzero = false;

        for (size_t i = (1u << c) - 1; i > 0; i--)
        {
            if (bucket_nonzero[i])
            {
                if (running_sum_nonzero)
                {
#ifdef USE_MIXED_ADDITION
                    running_sum = running_sum.mixed_add(buckets[i]);
#else
                    running_sum = running_sum + buckets[i];
#endif
                }
                else
                {
                    running_sum = buckets[i];
                    running_sum_nonzero = true;
                }
            }

            if (running_sum_nonzero)
            {
                if (result_nonzero)
                {
                    result = result + running_sum;
                }
                else
                {
                    result = running_sum;
                    result_nonzero = true;
                }
            }
        }
    }

    return result;
}


template<typename T, typename FieldT, multi_exp_method Method,
    typename std::enable_if<(Method == multi_exp_method_bos_coster), int>::type = 0>
T multi_exp_inner(
    typename std::vector<T>::const_iterator vec_start,
    typename std::vector<T>::const_iterator vec_end,
    typename std::vector<FieldT>::const_iterator scalar_start,
    typename std::vector<FieldT>::const_iterator scalar_end)
{
    const mp_size_t n = std::remove_reference<decltype(*scalar_start)>::type::num_limbs;

    if (vec_start == vec_end)
    {
        return T::zero();
    }

    if (vec_start + 1 == vec_end)
    {
        return (*scalar_start)*(*vec_start);
    }

    std::vector<ordered_exponent<n> > opt_q;
    const size_t vec_len = scalar_end - scalar_start;
    const size_t odd_vec_len = (vec_len % 2 == 1 ? vec_len : vec_len + 1);
    opt_q.reserve(odd_vec_len);
    std::vector<T> g;
    g.reserve(odd_vec_len);

    typename std::vector<T>::const_iterator vec_it;
    typename std::vector<FieldT>::const_iterator scalar_it;
    size_t i;
    for (i=0, vec_it = vec_start, scalar_it = scalar_start; vec_it != vec_end; ++vec_it, ++scalar_it, ++i)
    {
        g.emplace_back(*vec_it);

        opt_q.emplace_back(ordered_exponent<n>(i, scalar_it->as_bigint()));
    }
    std::make_heap(opt_q.begin(),opt_q.end());
    assert(scalar_it == scalar_end);

    if (vec_len != odd_vec_len)
    {
        g.emplace_back(T::zero());
        opt_q.emplace_back(ordered_exponent<n>(odd_vec_len - 1, bigint<n>(0ul)));
    }
    assert(g.size() % 2 == 1);
    assert(opt_q.size() == g.size());

    T opt_result = T::zero();

    while (true)
    {
        ordered_exponent<n> &a = opt_q[0];
        ordered_exponent<n> &b = (opt_q[1] < opt_q[2] ? opt_q[2] : opt_q[1]);

        const size_t abits = a.r.num_bits();

        if (b.r.is_zero())
        {
            // opt_result = opt_result + (a.r * g[a.idx]);
            opt_result = opt_result + opt_window_wnaf_exp(g[a.idx], a.r, abits);
            break;
        }

        const size_t bbits = b.r.num_bits();
        const size_t limit = (abits-bbits >= 20 ? 20 : abits-bbits);

        if (bbits < 1ul<<limit)
        {
            /*
              In this case, exponentiating to the power of a is cheaper than
              subtracting b from a multiple times, so let's do it directly
            */
            // opt_result = opt_result + (a.r * g[a.idx]);
            opt_result = opt_result + opt_window_wnaf_exp(g[a.idx], a.r, abits);
#ifdef DEBUG
            printf("Skipping the following pair (%zu bit number vs %zu bit):\n", abits, bbits);
            a.r.print();
            b.r.print();
#endif
            a.r.clear();
        }
        else
        {
            // x A + y B => (x-y) A + y (B+A)
            mpn_sub_n(a.r.data, a.r.data, b.r.data, n);
            g[b.idx] = g[b.idx] + g[a.idx];
        }

        // regardless of whether a was cleared or subtracted from we push it down, then take back up

        /* heapify A down */
        size_t a_pos = 0;
        while (2*a_pos + 2< odd_vec_len)
        {
            // this is a max-heap so to maintain a heap property we swap with the largest of the two
            if (opt_q[2*a_pos+1] < opt_q[2*a_pos+2])
            {
                std::swap(opt_q[a_pos], opt_q[2*a_pos+2]);
                a_pos = 2*a_pos+2;
            }
            else
            {
                std::swap(opt_q[a_pos], opt_q[2*a_pos+1]);
                a_pos = 2*a_pos+1;
            }
        }

        /* now heapify A up appropriate amount of times */
        while (a_pos > 0 && opt_q[(a_pos-1)/2] < opt_q[a_pos])
        {
            std::swap(opt_q[a_pos], opt_q[(a_pos-1)/2]);
            a_pos = (a_pos-1) / 2;
        }
    }

    return opt_result;
}

template<typename G1_PointT, typename ScalarFieldT>
G1_PointT multi_exp_g1_prove_fpga(
    typename std::vector<G1_PointT>::const_iterator vec_start,
    typename std::vector<G1_PointT>::const_iterator vec_end,
    typename std::vector<ScalarFieldT>::const_iterator scalar_start,
    typename std::vector<ScalarFieldT>::const_iterator scalar_end,
    const size_t chunks)
{
    libff::UNUSED(chunks);

    const size_t length = vec_end - vec_start;
    if (length == 0) {
        return G1_PointT::zero();
    }

    using BaseFieldT = typename std::decay<decltype(vec_start->X)>::type;
    using BaseBigIntT = decltype(vec_start->X.as_bigint());
    using ScalarBigIntT = decltype(scalar_start->as_bigint());

    static const BaseFieldT base_R255 = BaseFieldT(2) ^ 255;

    // =====================================================================
    // 1. Host -> FPGA 입력 데이터 준비
    //    PT = X 32B + Y 32B = 64B
    //    SC = scalar 32B
    // =====================================================================
    struct DmaPoint {
        BaseBigIntT X;
        BaseBigIntT Y;
    };

    std::vector<DmaPoint> dma_points(length);
    std::vector<ScalarBigIntT> dma_scalars(length);

    std::vector<G1_PointT> affine_bases(vec_start, vec_end);
    batch_to_special(affine_bases);

#ifdef MULTICORE
#pragma omp parallel for
#endif
    for (size_t i = 0; i < length; ++i) {
        if (affine_bases[i].is_zero()) {
            dma_scalars[i]  = 0UL;
            dma_points[i].X = 0UL;
            dma_points[i].Y = 0UL;
        } else {
            dma_scalars[i]  = scalar_start[i].as_bigint();
            dma_points[i].X = (affine_bases[i].X * base_R255).as_bigint();
            dma_points[i].Y = (affine_bases[i].Y * base_R255).as_bigint();
        }
    }

    // =====================================================================
    // 2. FPGA -> Host 출력 bucket 구조
    //    총 24개 window
    //    window당 2048 bucket
    //    bucket당 X/Y/Z = 96B
    // =====================================================================
    const size_t WINDOW_COUNT = 24;
    const size_t BITS_PER_WINDOW = 11;
    const size_t BUCKETS_PER_WINDOW = 1 << BITS_PER_WINDOW; // 2048

    struct FpgaRawJacobian {
        BaseBigIntT X;
        BaseBigIntT Y;
        BaseBigIntT Z;
    };

    std::vector<std::vector<FpgaRawJacobian>> fpga_buckets(
        WINDOW_COUNT,
        std::vector<FpgaRawJacobian>(BUCKETS_PER_WINDOW)
    );

    // =====================================================================
    // 3. DMA 실행
    // =====================================================================
    enter_block("Hardware FPGA DMA Execution");

    constexpr size_t PT_BYTES = 64;
    constexpr size_t SC_BYTES = 32;
    constexpr size_t RX_BYTES = 96;

    /*
     * 11만 개 입력 대응용 40MB 배치 기준
     *
     * PT   offset 0x0000000 size 0x700000
     * SC   offset 0x0700000 size 0x400000
     * RX   offset 0x0B00000 size 0x500000
     * DESC offset 0x1000000 size 0x1500000
     */
    constexpr size_t PT_MAP_SIZE   = 0x700000;
    constexpr size_t SC_MAP_SIZE   = 0x400000;
    constexpr size_t RX_MAP_SIZE   = 0x500000;

    constexpr size_t DESC_CH_SIZE  = 0x700000;
    constexpr size_t DESC_MAP_SIZE = DESC_CH_SIZE * 3;
    constexpr size_t MAX_DESC_COUNT = DESC_CH_SIZE / 64;
    constexpr size_t DESC_CH_DESC_COUNT = DESC_CH_SIZE / 64;

    constexpr off_t PT_MMAP_OFFSET   = 0x0000000;
    constexpr off_t SC_MMAP_OFFSET   = 0x0700000;
    constexpr off_t RX_MMAP_OFFSET   = 0x0B00000;
    constexpr off_t DESC_MMAP_OFFSET = 0x1000000;

    constexpr uint32_t BD_CTRL_TXSOF = 0x08000000;
    constexpr uint32_t BD_CTRL_TXEOF = 0x04000000;

    /*
     * 한 번의 MSM 연산:
     * - 같은 전체 입력 length개를 3번 전송
     * - iter마다 8개 window 결과만 수신
     */
    constexpr size_t OUT_ZONES_PER_ITER = 8;
    constexpr size_t DMA_ITERATIONS = 3;
    constexpr size_t OUT_COUNT_PER_ITER = BUCKETS_PER_WINDOW * OUT_ZONES_PER_ITER; // 2048 * 8 = 16384
    constexpr size_t RX_BYTES_PER_ITER = OUT_COUNT_PER_ITER * RX_BYTES;            // 0x180000
    constexpr size_t TOTAL_RX_BYTES = RX_BYTES_PER_ITER * DMA_ITERATIONS;          // 0x480000

    struct local_sg_descriptor_t {
        uint32_t next_desc;
        uint32_t next_desc_msb;
        uint32_t buffer_address;
        uint32_t buffer_msb;
        uint32_t reserved0;
        uint32_t reserved1;
        uint32_t control;
        uint32_t status;
        uint32_t app[5];
        uint32_t pad[3];
    } __attribute__((aligned(64)));

    const size_t in_count = length;

    if (in_count > MAX_DESC_COUNT ||
        OUT_COUNT_PER_ITER > MAX_DESC_COUNT ||
        in_count * PT_BYTES > PT_MAP_SIZE ||
        in_count * SC_BYTES > SC_MAP_SIZE ||
        TOTAL_RX_BYTES > RX_MAP_SIZE) {

        std::cerr << "[FPGA DMA] size/count overflow. "
                  << "in_count=" << in_count
                  << " out_per_iter=" << OUT_COUNT_PER_ITER
                  << " max_desc=" << MAX_DESC_COUNT
                  << " PT_need=0x" << std::hex << (in_count * PT_BYTES)
                  << " SC_need=0x" << (in_count * SC_BYTES)
                  << " RX_need=0x" << TOTAL_RX_BYTES
                  << " PT_MAP=0x" << PT_MAP_SIZE
                  << " SC_MAP=0x" << SC_MAP_SIZE
                  << " RX_MAP=0x" << RX_MAP_SIZE
                  << std::dec << std::endl;

        leave_block("Hardware FPGA DMA Execution");

        return multi_exp<G1_PointT, ScalarFieldT, multi_exp_method_BDLO12>(
            vec_start, vec_end, scalar_start, scalar_end, chunks
        );
    }

    int fd = open("/dev/msm_dma", O_RDWR);
    if (fd < 0) {
        perror("[FPGA DMA] open /dev/msm_dma");
        leave_block("Hardware FPGA DMA Execution");

        return multi_exp<G1_PointT, ScalarFieldT, multi_exp_method_BDLO12>(
            vec_start, vec_end, scalar_start, scalar_end, chunks
        );
    }

    uint32_t phys_pt = 0;
    uint32_t phys_sc = 0;
    uint32_t phys_rx = 0;
    uint32_t phys_desc = 0;

    if (ioctl(fd, MSM_DMA_IOC_GET_PT_PHYS, &phys_pt) < 0 ||
        ioctl(fd, MSM_DMA_IOC_GET_SC_PHYS, &phys_sc) < 0 ||
        ioctl(fd, MSM_DMA_IOC_GET_RX_PHYS, &phys_rx) < 0 ||
        ioctl(fd, MSM_DMA_IOC_GET_DESC_PHYS, &phys_desc) < 0) {

        std::cout<<"[문제가 발생하여 그냥 계산으로 넘어감]"<<std::endl;
        perror("[FPGA DMA] GET_PHYS");
        close(fd);
        leave_block("Hardware FPGA DMA Execution");

        return multi_exp<G1_PointT, ScalarFieldT, multi_exp_method_BDLO12>(
            vec_start, vec_end, scalar_start, scalar_end, chunks
        );
    }

    uint8_t *pt_buf = static_cast<uint8_t *>(
        mmap(nullptr, PT_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, PT_MMAP_OFFSET));

    uint8_t *sc_buf = static_cast<uint8_t *>(
        mmap(nullptr, SC_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, SC_MMAP_OFFSET));

    uint8_t *rx_buf = static_cast<uint8_t *>(
        mmap(nullptr, RX_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, RX_MMAP_OFFSET));

    local_sg_descriptor_t *desc_pool =
        static_cast<local_sg_descriptor_t *>(
            mmap(nullptr, DESC_MAP_SIZE, PROT_READ | PROT_WRITE,
                 MAP_SHARED, fd, DESC_MMAP_OFFSET));

    if (pt_buf == MAP_FAILED ||
        sc_buf == MAP_FAILED ||
        rx_buf == MAP_FAILED ||
        desc_pool == MAP_FAILED) {

        perror("[FPGA DMA] mmap");

        if (pt_buf != MAP_FAILED) munmap(pt_buf, PT_MAP_SIZE);
        if (sc_buf != MAP_FAILED) munmap(sc_buf, SC_MAP_SIZE);
        if (rx_buf != MAP_FAILED) munmap(rx_buf, RX_MAP_SIZE);
        if (desc_pool != MAP_FAILED) munmap(desc_pool, DESC_MAP_SIZE);

        close(fd);
        leave_block("Hardware FPGA DMA Execution");

        return multi_exp<G1_PointT, ScalarFieldT, multi_exp_method_BDLO12>(
            vec_start, vec_end, scalar_start, scalar_end, chunks
        );
    }

    /*
     * PT/SC 전체 입력을 한 번만 DMA 공유 메모리에 복사.
     * 이후 3번의 DMA iteration에서 같은 PT/SC 영역을 반복해서 읽는다.
     */
    memset(pt_buf, 0, PT_MAP_SIZE);
    memset(sc_buf, 0, SC_MAP_SIZE);
    memset(rx_buf, 0, RX_MAP_SIZE);
    memset(desc_pool, 0, DESC_MAP_SIZE);

    for (size_t i = 0; i < in_count; ++i) {
        uint8_t *pt = pt_buf + i * PT_BYTES;
        uint8_t *sc = sc_buf + i * SC_BYTES;

        memcpy(pt,
               &dma_points[i].X,
               std::min(sizeof(dma_points[i].X), size_t(32)));

        memcpy(pt + 32,
               &dma_points[i].Y,
               std::min(sizeof(dma_points[i].Y), size_t(32)));

        memcpy(sc,
               &dma_scalars[i],
               std::min(sizeof(dma_scalars[i]), size_t(32)));
    }

    bool dma_error = false;

    /*
     * 3번 반복:
     * iter 0 -> window 0~7 bucket 결과
     * iter 1 -> window 8~15 bucket 결과
     * iter 2 -> window 16~23 bucket 결과
     *
     * 입력은 매번 같은 전체 length개.
     * 출력만 iter마다 16384개씩 다른 RX offset에 저장.
     */
    for (size_t iter = 0; iter < DMA_ITERATIONS; ++iter) {
        memset(desc_pool, 0, DESC_MAP_SIZE);

        local_sg_descriptor_t *mm2s0 = desc_pool;
        local_sg_descriptor_t *s2mm0 = desc_pool + DESC_CH_DESC_COUNT;
        local_sg_descriptor_t *mm2s1 = desc_pool + DESC_CH_DESC_COUNT * 2;

        const size_t rx_iter_base = iter * RX_BYTES_PER_ITER;

        /*
         * MM2S0: point 전체 length개
         * MM2S1: scalar 전체 length개
         */
        for (size_t i = 0; i < in_count; ++i) {
            const uint32_t is_last = (i == in_count - 1);

            mm2s0[i].next_desc =
                phys_desc + (is_last ? 0 : static_cast<uint32_t>((i + 1) * 64));
            mm2s0[i].buffer_address =
                phys_pt + static_cast<uint32_t>(i * PT_BYTES);
            mm2s0[i].control =
                BD_CTRL_TXSOF | BD_CTRL_TXEOF | PT_BYTES;

            mm2s1[i].next_desc =
                phys_desc + DESC_CH_SIZE * 2 +
                (is_last ? 0 : static_cast<uint32_t>((i + 1) * 64));
            mm2s1[i].buffer_address =
                phys_sc + static_cast<uint32_t>(i * SC_BYTES);
            mm2s1[i].control =
                BD_CTRL_TXSOF | BD_CTRL_TXEOF | SC_BYTES;
        }

        /*
         * S2MM: 이번 iter의 8개 window bucket 결과만 수신
         * 16384 packets × 96B
         */
        for (size_t i = 0; i < OUT_COUNT_PER_ITER; ++i) {
            const uint32_t is_last = (i == OUT_COUNT_PER_ITER - 1);

            s2mm0[i].next_desc =
                phys_desc + DESC_CH_SIZE +
                (is_last ? 0 : static_cast<uint32_t>((i + 1) * 64));

            s2mm0[i].buffer_address =
                phys_rx + static_cast<uint32_t>(rx_iter_base + i * RX_BYTES);

            s2mm0[i].control = RX_BYTES;
        }

        msm_dma_xfer_req req;
        req.in_count = static_cast<uint32_t>(in_count);
        req.out_count = static_cast<uint32_t>(OUT_COUNT_PER_ITER);

        std::cerr << "[FPGA DMA] MSM bucket iter=" << iter
                  << " in_count=" << req.in_count
                  << " out_count=" << req.out_count
                  << " rx_base=0x" << std::hex << rx_iter_base
                  << std::dec << std::endl;

        if (ioctl(fd, MSM_DMA_IOC_XFER, &req) < 0) {
            perror("[FPGA DMA] XFER");
            dma_error = true;
            break;
        }
    }

    if (dma_error) {
        munmap(pt_buf, PT_MAP_SIZE);
        munmap(sc_buf, SC_MAP_SIZE);
        munmap(rx_buf, RX_MAP_SIZE);
        munmap(desc_pool, DESC_MAP_SIZE);
        close(fd);

        leave_block("Hardware FPGA DMA Execution");

        return multi_exp<G1_PointT, ScalarFieldT, multi_exp_method_BDLO12>(
            vec_start, vec_end, scalar_start, scalar_end, chunks
        );
    }

    /*
     * RX 전체를 fpga_buckets[24][2048]로 복사.
     *
     * iter 0 RX + 0x000000 -> window 0~7
     * iter 1 RX + 0x180000 -> window 8~15
     * iter 2 RX + 0x300000 -> window 16~23
     */
    for (size_t iter = 0; iter < DMA_ITERATIONS; ++iter) {
        const size_t rx_iter_base = iter * RX_BYTES_PER_ITER;

        for (size_t local_w = 0; local_w < OUT_ZONES_PER_ITER; ++local_w) {
            const size_t global_w = iter * OUT_ZONES_PER_ITER + local_w;

            for (size_t b = 0; b < BUCKETS_PER_WINDOW; ++b) {
                const size_t local_idx = local_w * BUCKETS_PER_WINDOW + b;
                uint8_t *rx = rx_buf + rx_iter_base + local_idx * RX_BYTES;

                memcpy(&fpga_buckets[global_w][b].X,
                       rx,
                       std::min(sizeof(fpga_buckets[global_w][b].X), size_t(32)));

                memcpy(&fpga_buckets[global_w][b].Y,
                       rx + 32,
                       std::min(sizeof(fpga_buckets[global_w][b].Y), size_t(32)));

                memcpy(&fpga_buckets[global_w][b].Z,
                       rx + 64,
                       std::min(sizeof(fpga_buckets[global_w][b].Z), size_t(32)));
            }
        }
    }

    std::cerr << "[FPGA DMA] done. 24-window bucket RX copied"
              << std::endl;

    munmap(pt_buf, PT_MAP_SIZE);
    munmap(sc_buf, SC_MAP_SIZE);
    munmap(rx_buf, RX_MAP_SIZE);
    munmap(desc_pool, DESC_MAP_SIZE);
    close(fd);

    leave_block("Hardware FPGA DMA Execution");

    // =====================================================================
    // 4. 도메인 복원 및 대규모 일괄 아핀 변환
    // =====================================================================
    static const BaseFieldT inv_R255 = (BaseFieldT(2) ^ 255).inverse();

    std::vector<std::vector<G1_PointT>> window_buckets(
        WINDOW_COUNT,
        std::vector<G1_PointT>(BUCKETS_PER_WINDOW, G1_PointT::zero())
    );

    std::vector<G1_PointT> active_buckets;
    std::vector<std::pair<size_t, size_t>> active_indices;

    active_buckets.reserve(WINDOW_COUNT * BUCKETS_PER_WINDOW);
    active_indices.reserve(WINDOW_COUNT * BUCKETS_PER_WINDOW);

    for (size_t w = 0; w < WINDOW_COUNT; ++w) {
        for (size_t b = 1; b < BUCKETS_PER_WINDOW; ++b) {
            if (fpga_buckets[w][b].Z.is_zero()) {
                continue;
            }

            BaseFieldT restored_X = BaseFieldT(fpga_buckets[w][b].X) * inv_R255;
            BaseFieldT restored_Y = BaseFieldT(fpga_buckets[w][b].Y) * inv_R255;
            BaseFieldT restored_Z = BaseFieldT(fpga_buckets[w][b].Z) * inv_R255;

            active_buckets.emplace_back(G1_PointT(restored_X, restored_Y, restored_Z));
            active_indices.emplace_back(w, b);
        }
    }

    if (!active_buckets.empty()) {
        batch_to_special(active_buckets);
    }

    for (size_t i = 0; i < active_buckets.size(); ++i) {
        const size_t w = active_indices[i].first;
        const size_t b = active_indices[i].second;
        window_buckets[w][b] = active_buckets[i];
    }

    // =====================================================================
    // 5. 소프트웨어 bucket reduction
    // =====================================================================
    std::vector<G1_PointT> window_results(WINDOW_COUNT, G1_PointT::zero());

#ifdef MULTICORE
#pragma omp parallel for
#endif
    for (size_t w = 0; w < WINDOW_COUNT; ++w) {
        G1_PointT running_sum = G1_PointT::zero();
        G1_PointT window_sum = G1_PointT::zero();

        bool running_sum_nonzero = false;
        bool window_sum_nonzero = false;

        for (size_t b = BUCKETS_PER_WINDOW - 1; b > 0; --b) {
            if (!window_buckets[w][b].is_zero()) {
                if (running_sum_nonzero) {
                    running_sum = running_sum + window_buckets[w][b];
                } else {
                    running_sum = window_buckets[w][b];
                    running_sum_nonzero = true;
                }
            }

            if (running_sum_nonzero) {
                if (window_sum_nonzero) {
                    window_sum = window_sum + running_sum;
                } else {
                    window_sum = running_sum;
                    window_sum_nonzero = true;
                }
            }
        }

        window_results[w] = window_sum;
    }

    // =====================================================================
    // 6. 최종 aggregation
    // =====================================================================
    G1_PointT final_result = G1_PointT::zero();
    bool final_nonzero = false;

    for (size_t ww = WINDOW_COUNT; ww-- > 0;) {
        if (final_nonzero) {
            for (size_t shift = 0; shift < BITS_PER_WINDOW; ++shift) {
                final_result = final_result.dbl();
            }
        }

        if (!window_results[ww].is_zero()) {
            if (final_nonzero) {
                final_result = final_result + window_results[ww];
            } else {
                final_result = window_results[ww];
                final_nonzero = true;
            }
        }
    }

    return final_result;
}

template<typename T, typename FieldT, multi_exp_method Method>
T multi_exp(typename std::vector<T>::const_iterator vec_start,
            typename std::vector<T>::const_iterator vec_end,
            typename std::vector<FieldT>::const_iterator scalar_start,
            typename std::vector<FieldT>::const_iterator scalar_end,
            const size_t chunks)
{
    const size_t total = vec_end - vec_start;
    if ((total < chunks) || (chunks == 1))
    {
        // no need to split into "chunks", can call implementation directly
        return multi_exp_inner<T, FieldT, Method>(
            vec_start, vec_end, scalar_start, scalar_end);
    }

    const size_t one = total/chunks;

    std::vector<T> partial(chunks, T::zero());

#ifdef MULTICORE
#pragma omp parallel for
#endif
    for (size_t i = 0; i < chunks; ++i)
    {
        partial[i] = multi_exp_inner<T, FieldT, Method>(
             vec_start + i*one,
             (i == chunks-1 ? vec_end : vec_start + (i+1)*one),
             scalar_start + i*one,
             (i == chunks-1 ? scalar_end : scalar_start + (i+1)*one));
    }

    T final = T::zero();

    for (size_t i = 0; i < chunks; ++i)
    {
        final = final + partial[i];
    }

    return final;
}

template<typename T, typename FieldT, multi_exp_method Method>
T multi_exp_with_mixed_addition(typename std::vector<T>::const_iterator vec_start,
                                typename std::vector<T>::const_iterator vec_end,
                                typename std::vector<FieldT>::const_iterator scalar_start,
                                typename std::vector<FieldT>::const_iterator scalar_end,
                                const size_t chunks, 
                                bool useFPGA)
{
#ifndef NDEBUG
    assert(std::distance(vec_start, vec_end) == std::distance(scalar_start, scalar_end));
#else
    libff::UNUSED(vec_end);
#endif
    enter_block("Process scalar vector");
    auto value_it = vec_start;
    auto scalar_it = scalar_start;

    const FieldT zero = FieldT::zero();
    const FieldT one = FieldT::one();
    std::vector<FieldT> p;
    std::vector<T> g;

    T acc = T::zero();

    size_t num_skip = 0;
    size_t num_add = 0;
    size_t num_other = 0;

    for (; scalar_it != scalar_end; ++scalar_it, ++value_it)
    {
        if (*scalar_it == zero)
        {
            // do nothing
            ++num_skip;
        }
        else if (*scalar_it == one)
        {
#ifdef USE_MIXED_ADDITION
            acc = acc.mixed_add(*value_it);
#else
            acc = acc + (*value_it);
#endif
            ++num_add;
        }
        else
        {
            p.emplace_back(*scalar_it);
            g.emplace_back(*value_it);
            ++num_other;
        }
    }
    print_indent(); printf("* Elements of w skipped: %zu (%0.2f%%)\n", num_skip, 100.*num_skip/(num_skip+num_add+num_other));
    print_indent(); printf("* Elements of w processed with special addition: %zu (%0.2f%%)\n", num_add, 100.*num_add/(num_skip+num_add+num_other));
    print_indent(); printf("* Elements of w remaining: %zu (%0.2f%%)\n", num_other, 100.*num_other/(num_skip+num_add+num_other));
    leave_block("Process scalar vector");

    // 하드웨어 라우팅 분기 
    if(useFPGA){
        return acc + multi_exp_g1_prove_fpga<T, FieldT>(g.begin(), g.end(), p.begin(), p.end(),chunks);
    }
    else{
        return acc + multi_exp<T, FieldT, Method>(g.begin(), g.end(), p.begin(), p.end(), chunks);
    }
}

template <typename T>
T inner_product(typename std::vector<T>::const_iterator a_start,
                typename std::vector<T>::const_iterator a_end,
                typename std::vector<T>::const_iterator b_start,
                typename std::vector<T>::const_iterator b_end)
{
    return multi_exp<T, T, multi_exp_method_naive_plain>(
        a_start, a_end,
        b_start, b_end, 1);
}

template<typename T>
size_t get_exp_window_size(const size_t num_scalars)
{
    if (T::fixed_base_exp_window_table.empty())
    {
#ifdef LOWMEM
        return 14;
#else
        return 17;
#endif
    }
    size_t window = 1;
    for (long i = T::fixed_base_exp_window_table.size()-1; i >= 0; --i)
    {
#ifdef DEBUG
        if (!inhibit_profiling_info)
        {
            printf("%ld %zu %zu\n", i, num_scalars, T::fixed_base_exp_window_table[i]);
        }
#endif
        if (T::fixed_base_exp_window_table[i] != 0 && num_scalars >= T::fixed_base_exp_window_table[i])
        {
            window = i+1;
            break;
        }
    }

    if (!inhibit_profiling_info)
    {
        print_indent(); printf("Choosing window size %zu for %zu elements\n", window, num_scalars);
    }

#ifdef LOWMEM
    window = std::min((size_t)14, window);
#endif
    return window;
}

template<typename T>
window_table<T> get_window_table(const size_t scalar_size,
                                 const size_t window,
                                 const T &g)
{
    const size_t in_window = 1ul<<window;
    const size_t outerc = (scalar_size+window-1)/window;
    const size_t last_in_window = 1ul<<(scalar_size - (outerc-1)*window);
#ifdef DEBUG
    if (!inhibit_profiling_info)
    {
        print_indent(); printf("* scalar_size=%zu; window=%zu; in_window=%zu; outerc=%zu\n", scalar_size, window, in_window, outerc);
    }
#endif

    window_table<T> powers_of_g(outerc, std::vector<T>(in_window, T::zero()));

    T gouter = g;

    for (size_t outer = 0; outer < outerc; ++outer)
    {
        T ginner = T::zero();
        size_t cur_in_window = outer == outerc-1 ? last_in_window : in_window;
        for (size_t inner = 0; inner < cur_in_window; ++inner)
        {
            powers_of_g[outer][inner] = ginner;
            ginner = ginner + gouter;
        }

        for (size_t i = 0; i < window; ++i)
        {
            gouter = gouter + gouter;
        }
    }

    return powers_of_g;
}

template<typename T, typename FieldT>
T windowed_exp(const size_t scalar_size,
               const size_t window,
               const window_table<T> &powers_of_g,
               const FieldT &pow)
{
    const size_t outerc = (scalar_size+window-1)/window;
    const bigint<FieldT::num_limbs> pow_val = pow.as_bigint();

    /* exp */
    T res = powers_of_g[0][0];

    for (size_t outer = 0; outer < outerc; ++outer)
    {
        size_t inner = 0;
        for (size_t i = 0; i < window; ++i)
        {
            if (pow_val.test_bit(outer*window + i))
            {
                inner |= 1u << i;
            }
        }

        res = res + powers_of_g[outer][inner];
    }

    return res;
}

template<typename T, typename FieldT>
std::vector<T> batch_exp(const size_t scalar_size,
                         const size_t window,
                         const window_table<T> &table,
                         const std::vector<FieldT> &v)
{
    if (!inhibit_profiling_info)
    {
        print_indent();
    }
    std::vector<T> res(v.size(), table[0][0]);

#ifdef MULTICORE
#pragma omp parallel for
#endif
    for (size_t i = 0; i < v.size(); ++i)
    {
        res[i] = windowed_exp(scalar_size, window, table, v[i]);

        if (!inhibit_profiling_info && (i % 10000 == 0))
        {
            printf(".");
            fflush(stdout);
        }
    }

    if (!inhibit_profiling_info)
    {
        printf(" DONE!\n");
    }

    return res;
}

template<typename T, typename FieldT>
std::vector<T> batch_exp_with_coeff(const size_t scalar_size,
                                    const size_t window,
                                    const window_table<T> &table,
                                    const FieldT &coeff,
                                    const std::vector<FieldT> &v)
{
    if (!inhibit_profiling_info)
    {
        print_indent();
    }
    std::vector<T> res(v.size(), table[0][0]);

#ifdef MULTICORE
#pragma omp parallel for
#endif
    for (size_t i = 0; i < v.size(); ++i)
    {
        res[i] = windowed_exp(scalar_size, window, table, coeff * v[i]);

        if (!inhibit_profiling_info && (i % 10000 == 0))
        {
            printf(".");
            fflush(stdout);
        }
    }

    if (!inhibit_profiling_info)
    {
        printf(" DONE!\n");
    }

    return res;
}

template<typename T>
void batch_to_special(std::vector<T> &vec)
{
    enter_block("Batch-convert elements to special form");

    std::vector<T> non_zero_vec;
    for (size_t i = 0; i < vec.size(); ++i)
    {
        if (!vec[i].is_zero())
        {
            non_zero_vec.emplace_back(vec[i]);
        }
    }

    T::batch_to_special_all_non_zeros(non_zero_vec);
    auto it = non_zero_vec.begin();
    T zero_special = T::zero();
    zero_special.to_special();

    for (size_t i = 0; i < vec.size(); ++i)
    {
        if (!vec[i].is_zero())
        {
            vec[i] = *it;
            ++it;
        }
        else
        {
            vec[i] = zero_special;
        }
    }
    leave_block("Batch-convert elements to special form");
}

} // libff

#endif // MULTIEXP_TCC_

