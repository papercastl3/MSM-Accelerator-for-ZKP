// msm_fpga_raw_bucket_test.cpp
#include <algorithm>
#include <array>
#include <cerrno>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <vector>

// ============================================================
// Driver ioctl interface
// ============================================================

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

// ============================================================
// DMA constants
// ============================================================

constexpr size_t PT_BYTES = 64;   // X 32B + Y 32B
constexpr size_t SC_BYTES = 32;   // scalar 32B
constexpr size_t RX_BYTES = 96;   // X 32B + Y 32B + Z 32B

constexpr size_t WINDOW_COUNT = 24;
constexpr size_t MAX_BITS_PER_WINDOW = 11;
constexpr size_t BUCKETS_PER_WINDOW = 1 << MAX_BITS_PER_WINDOW; // 2048

constexpr size_t OUT_ZONES_PER_ITER = 8;
constexpr size_t DMA_ITERATIONS = 3;
constexpr size_t OUT_COUNT_PER_ITER = BUCKETS_PER_WINDOW * OUT_ZONES_PER_ITER; // 16384
constexpr size_t RX_BYTES_PER_ITER = OUT_COUNT_PER_ITER * RX_BYTES;            // 0x180000
constexpr size_t TOTAL_RX_BYTES = RX_BYTES_PER_ITER * DMA_ITERATIONS;          // 0x480000

/*
 * Driver mmap layout.
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
constexpr size_t DESC_CH_DESC_COUNT = DESC_CH_SIZE / 64;
constexpr size_t MAX_DESC_COUNT = DESC_CH_SIZE / 64;

constexpr off_t PT_MMAP_OFFSET   = 0x0000000;
constexpr off_t SC_MMAP_OFFSET   = 0x0700000;
constexpr off_t RX_MMAP_OFFSET   = 0x0B00000;
constexpr off_t DESC_MMAP_OFFSET = 0x1000000;

constexpr uint32_t BD_CTRL_TXSOF = 0x08000000;
constexpr uint32_t BD_CTRL_TXEOF = 0x04000000;

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

static_assert(sizeof(local_sg_descriptor_t) == 64, "Descriptor must be 64 bytes");

// ============================================================
// Hex parsing helpers
// ============================================================

static std::string normalize_hex_line(const std::string &line)
{
    std::string out;
    out.reserve(line.size());

    for (char c : line) {
        if (std::isxdigit(static_cast<unsigned char>(c))) {
            out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
        }
    }

    return out;
}

static uint8_t hex_pair_to_byte(char hi, char lo)
{
    auto val = [](char c) -> uint8_t {
        if (c >= '0' && c <= '9') return static_cast<uint8_t>(c - '0');
        if (c >= 'a' && c <= 'f') return static_cast<uint8_t>(10 + c - 'a');
        if (c >= 'A' && c <= 'F') return static_cast<uint8_t>(10 + c - 'A');

        std::cerr << "Invalid hex character: " << c << std::endl;
        std::exit(1);
    };

    return static_cast<uint8_t>((val(hi) << 4) | val(lo));
}

/*
 * Input:
 *   normal big-endian hex string, 64 hex chars for 256-bit value.
 *
 * Output:
 *   little-endian byte array.
 *
 * Reason:
 *   기존 libff bigint를 memcpy로 DMA 버퍼에 넣던 방식은
 *   메모리상 little-endian limb layout일 가능성이 높다.
 *   따라서 파일은 사람이 보는 big-endian으로 두고,
 *   DMA 버퍼에 넣을 때 byte reverse한다.
 */
static std::array<uint8_t, 32> parse_u256_hex_to_le_bytes(const std::string &raw)
{
    std::string hex = normalize_hex_line(raw);

    if (hex.rfind("0x", 0) == 0) {
        hex = hex.substr(2);
    }

    if (hex.size() > 64) {
        std::cerr << "u256 hex too long: " << hex.size() << " chars" << std::endl;
        std::exit(1);
    }

    if (hex.size() < 64) {
        hex = std::string(64 - hex.size(), '0') + hex;
    }

    std::array<uint8_t, 32> le{};

    for (size_t be_i = 0; be_i < 32; ++be_i) {
        const uint8_t byte = hex_pair_to_byte(hex[be_i * 2], hex[be_i * 2 + 1]);
        le[31 - be_i] = byte;
    }

    return le;
}

static std::string le_bytes_to_be_hex(const uint8_t *le, size_t n)
{
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');

    for (size_t i = 0; i < n; ++i) {
        const uint8_t byte = le[n - 1 - i];
        oss << std::setw(2) << static_cast<unsigned int>(byte);
    }

    return oss.str();
}

// ============================================================
// Input file format
// ============================================================
//
// affine_point_mont.hex:
//   one line per point
//   X || Y
//   256-bit X + 256-bit Y = 512-bit = 128 hex chars
//
// scalar.hex:
//   one line per scalar
//   256-bit scalar = 64 hex chars
//
// Both files are assumed to be normal big-endian hex text.
// This program converts them to little-endian bytes before writing DMA buffers.

struct InputPoint {
    std::array<uint8_t, 32> x_le;
    std::array<uint8_t, 32> y_le;
};

static std::vector<InputPoint> load_points_mont_hex(const std::string &path)
{
    std::ifstream file(path);
    if (!file) {
        std::perror(("open " + path).c_str());
        std::exit(1);
    }

    std::vector<InputPoint> points;
    std::string line;
    size_t line_no = 0;

    while (std::getline(file, line)) {
        ++line_no;

        std::string hex = normalize_hex_line(line);
        if (hex.empty()) {
            continue;
        }

        if (hex.rfind("0x", 0) == 0) {
            hex = hex.substr(2);
        }

        if (hex.size() != 128) {
            std::cerr << path << ":" << line_no
                      << " invalid point hex length. expected 128, got "
                      << hex.size() << std::endl;
            std::exit(1);
        }

        const std::string x_hex = hex.substr(0, 64);
        const std::string y_hex = hex.substr(64, 64);

        InputPoint p;
        p.x_le = parse_u256_hex_to_le_bytes(x_hex);
        p.y_le = parse_u256_hex_to_le_bytes(y_hex);
        points.push_back(p);
    }

    return points;
}

static std::vector<std::array<uint8_t, 32>> load_scalars_hex(const std::string &path)
{
    std::ifstream file(path);
    if (!file) {
        std::perror(("open " + path).c_str());
        std::exit(1);
    }

    std::vector<std::array<uint8_t, 32>> scalars;
    std::string line;
    size_t line_no = 0;

    while (std::getline(file, line)) {
        ++line_no;

        std::string hex = normalize_hex_line(line);
        if (hex.empty()) {
            continue;
        }

        if (hex.rfind("0x", 0) == 0) {
            hex = hex.substr(2);
        }

        if (hex.size() > 64) {
            std::cerr << path << ":" << line_no
                      << " invalid scalar hex length. expected <=64, got "
                      << hex.size() << std::endl;
            std::exit(1);
        }

        scalars.push_back(parse_u256_hex_to_le_bytes(hex));
    }

    return scalars;
}

// ============================================================
// Main
// ============================================================

int main(int argc, char **argv)
{
    const std::string point_file  = (argc >= 2) ? argv[1] : "point.hex";
    const std::string scalar_file = (argc >= 3) ? argv[2] : "scalar.hex";
    // const std::string dump_file   = (argc >= 4) ? argv[3] : "fpga_window_buckets_raw.hex";

    std::cerr << "[MSM TEST] point file  = " << point_file << std::endl;
    std::cerr << "[MSM TEST] scalar file = " << scalar_file << std::endl;
    // std::cerr << "[MSM TEST] dump file   = " << dump_file << std::endl;

    const auto points = load_points_mont_hex(point_file);
    const auto scalars = load_scalars_hex(scalar_file);

    if (points.empty()) {
        std::cerr << "[MSM TEST] no input points" << std::endl;
        return 1;
    }

    if (points.size() != scalars.size()) {
        std::cerr << "[MSM TEST] point/scalar count mismatch. points="
                  << points.size()
                  << " scalars=" << scalars.size()
                  << std::endl;
        return 1;
    }

    const size_t in_count = points.size();

    // std::cerr << "[MSM TEST] input count = " << in_count << std::endl;

    if (in_count > MAX_DESC_COUNT ||
        in_count * PT_BYTES > PT_MAP_SIZE ||
        in_count * SC_BYTES > SC_MAP_SIZE ||
        TOTAL_RX_BYTES > RX_MAP_SIZE) {

        std::cerr << "[MSM TEST] size/count overflow. "
                  << "in_count=" << in_count
                  << " max_desc=" << MAX_DESC_COUNT
                  << " PT_need=0x" << std::hex << (in_count * PT_BYTES)
                  << " SC_need=0x" << (in_count * SC_BYTES)
                  << " RX_need=0x" << TOTAL_RX_BYTES
                  << " PT_MAP=0x" << PT_MAP_SIZE
                  << " SC_MAP=0x" << SC_MAP_SIZE
                  << " RX_MAP=0x" << RX_MAP_SIZE
                  << std::dec << std::endl;
        return 1;
    }

    int fd = open("/dev/msm_dma", O_RDWR);
    if (fd < 0) {
        std::perror("[MSM TEST] open /dev/msm_dma");
        return 1;
    }

    uint32_t phys_pt = 0;
    uint32_t phys_sc = 0;
    uint32_t phys_rx = 0;
    uint32_t phys_desc = 0;

    if (ioctl(fd, MSM_DMA_IOC_GET_PT_PHYS, &phys_pt) < 0 ||
        ioctl(fd, MSM_DMA_IOC_GET_SC_PHYS, &phys_sc) < 0 ||
        ioctl(fd, MSM_DMA_IOC_GET_RX_PHYS, &phys_rx) < 0 ||
        ioctl(fd, MSM_DMA_IOC_GET_DESC_PHYS, &phys_desc) < 0) {

        std::perror("[MSM TEST] GET_PHYS ioctl");
        close(fd);
        return 1;
    }

    std::cerr << "[MSM TEST] phys_pt   = 0x" << std::hex << phys_pt << std::endl;
    std::cerr << "[MSM TEST] phys_sc   = 0x" << std::hex << phys_sc << std::endl;
    std::cerr << "[MSM TEST] phys_rx   = 0x" << std::hex << phys_rx << std::endl;
    std::cerr << "[MSM TEST] phys_desc = 0x" << std::hex << phys_desc << std::dec << std::endl;

    uint8_t *pt_buf = static_cast<uint8_t *>(
        mmap(nullptr, PT_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, PT_MMAP_OFFSET));

    uint8_t *sc_buf = static_cast<uint8_t *>(
        mmap(nullptr, SC_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, SC_MMAP_OFFSET));

    uint8_t *rx_buf = static_cast<uint8_t *>(
        mmap(nullptr, RX_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, RX_MMAP_OFFSET));

    auto *desc_pool = static_cast<local_sg_descriptor_t *>(
        mmap(nullptr, DESC_MAP_SIZE, PROT_READ | PROT_WRITE,
             MAP_SHARED, fd, DESC_MMAP_OFFSET));

    if (pt_buf == MAP_FAILED ||
        sc_buf == MAP_FAILED ||
        rx_buf == MAP_FAILED ||
        desc_pool == MAP_FAILED) {

        std::perror("[MSM TEST] mmap");

        if (pt_buf != MAP_FAILED) {
            munmap(pt_buf, PT_MAP_SIZE);
        }
        if (sc_buf != MAP_FAILED) {
            munmap(sc_buf, SC_MAP_SIZE);
        }
        if (rx_buf != MAP_FAILED) {
            munmap(rx_buf, RX_MAP_SIZE);
        }
        if (desc_pool != MAP_FAILED) {
            munmap(desc_pool, DESC_MAP_SIZE);
        }

        close(fd);
        return 1;
    }

    std::memset(pt_buf, 0, PT_MAP_SIZE);
    std::memset(sc_buf, 0, SC_MAP_SIZE);
    std::memset(rx_buf, 0, RX_MAP_SIZE);
    std::memset(desc_pool, 0, DESC_MAP_SIZE);

    // ------------------------------------------------------------
    // Copy input files to DMA buffers
    //
    // PT layout per input:
    //   offset + 0  : X[255:0], little-endian bytes
    //   offset + 32 : Y[255:0], little-endian bytes
    //
    // SC layout per input:
    //   offset + 0  : scalar[255:0], little-endian bytes
    // ------------------------------------------------------------

    for (size_t i = 0; i < in_count; ++i) {
        uint8_t *pt = pt_buf + i * PT_BYTES;
        uint8_t *sc = sc_buf + i * SC_BYTES;

        /*
        * PL currently interprets:
        *   tdata[511:256] as X
        *   tdata[255:0]   as Y
        *
        * AXI DMA places lower DDR address into lower tdata bits.
        * Therefore write Y first, X second in memory.
        */
        std::memcpy(pt,      points[i].y_le.data(), 32);
        std::memcpy(pt + 32, points[i].x_le.data(), 32);

        std::memcpy(sc,      scalars[i].data(),     32);
    }

    bool dma_error = false;

    // ------------------------------------------------------------
    // DMA 3 iterations
    //
    // iter 0 -> window 0~7
    // iter 1 -> window 8~15
    // iter 2 -> window 16~23
    //
    // MM2S0: point stream
    // MM2S1: scalar stream
    // S2MM0: bucket result stream
    // ------------------------------------------------------------

    for (size_t iter = 0; iter < DMA_ITERATIONS; ++iter) {
        std::memset(desc_pool, 0, DESC_MAP_SIZE);

        local_sg_descriptor_t *mm2s0 = desc_pool;
        local_sg_descriptor_t *s2mm0 = desc_pool + DESC_CH_DESC_COUNT;
        local_sg_descriptor_t *mm2s1 = desc_pool + DESC_CH_DESC_COUNT * 2;

        const size_t rx_iter_base = iter * RX_BYTES_PER_ITER;

        for (size_t i = 0; i < in_count; ++i) {
            const bool is_first = (i == 0);
            const bool is_last  = (i == in_count - 1);

            uint32_t pt_ctrl = PT_BYTES;
            if (is_first) {
                pt_ctrl |= BD_CTRL_TXSOF;
            }
            if (is_last) {
                pt_ctrl |= BD_CTRL_TXEOF;
            }

            mm2s0[i].next_desc =
                phys_desc + (is_last ? 0 : static_cast<uint32_t>((i + 1) * 64));

            mm2s0[i].buffer_address =
                phys_pt + static_cast<uint32_t>(i * PT_BYTES);

            mm2s0[i].control = pt_ctrl;

            uint32_t sc_ctrl = SC_BYTES;
            if (is_first) {
                sc_ctrl |= BD_CTRL_TXSOF;
            }
            if (is_last) {
                sc_ctrl |= BD_CTRL_TXEOF;
            }

            mm2s1[i].next_desc =
                phys_desc + DESC_CH_SIZE * 2 +
                (is_last ? 0 : static_cast<uint32_t>((i + 1) * 64));

            mm2s1[i].buffer_address =
                phys_sc + static_cast<uint32_t>(i * SC_BYTES);

            mm2s1[i].control = sc_ctrl;
        }

        s2mm0[0].next_desc =
            phys_desc + DESC_CH_SIZE;

        s2mm0[0].buffer_address =
            phys_rx + static_cast<uint32_t>(rx_iter_base);

        s2mm0[0].control =
            static_cast<uint32_t>(RX_BYTES_PER_ITER);

        msm_dma_xfer_req req{};
        req.in_count = static_cast<uint32_t>(in_count);
        req.out_count = 1;

        // std::cerr << "[MSM TEST] DMA iter=" << iter
        //           << " in_count=" << req.in_count
        //           << " out_count=" << req.out_count
        //           << " rx_base=0x" << std::hex << rx_iter_base
        //           << std::dec << std::endl;

        if (ioctl(fd, MSM_DMA_IOC_XFER, &req) < 0) {
            std::perror("[MSM TEST] XFER ioctl");
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
        return 1;
    }

    // ------------------------------------------------------------
    // Dump raw buckets
    //
    // Output:
    //   24 * 2048 lines
    //
    // Line order:
    //   window 0 bucket 0
    //   window 0 bucket 1
    //   ...
    //   window 23 bucket 2047
    //
    // Each line:
    //   X || Y || Z
    //   256-bit X + 256-bit Y + 256-bit Z
    //   768-bit = 192 hex chars
    //
    // RX memory is assumed little-endian per 256-bit coordinate.
    // Dump file is written as normal big-endian hex text.
    // ------------------------------------------------------------

    // std::ofstream out(dump_file);
    if (!out) {
        std::perror(("[MSM TEST] open output " + dump_file).c_str());

        munmap(pt_buf, PT_MAP_SIZE);
        munmap(sc_buf, SC_MAP_SIZE);
        munmap(rx_buf, RX_MAP_SIZE);
        munmap(desc_pool, DESC_MAP_SIZE);
        close(fd);
        return 1;
    }

    // for (size_t iter = 0; iter < DMA_ITERATIONS; ++iter) {
    //     const size_t rx_iter_base = iter * RX_BYTES_PER_ITER;

    //     for (size_t local_w = 0; local_w < OUT_ZONES_PER_ITER; ++local_w) {
    //         const size_t global_w = iter * OUT_ZONES_PER_ITER + local_w;
    //         (void)global_w;

    //         for (size_t b = 0; b < BUCKETS_PER_WINDOW; ++b) {
    //             const size_t local_idx = local_w * BUCKETS_PER_WINDOW + b;
    //             const uint8_t *rx = rx_buf + rx_iter_base + local_idx * RX_BYTES;

    //             /*
    //             * Actual RX memory layout from FPGA appears to be:
    //             *   rx + 0  : Z
    //             *   rx + 32 : Y
    //             *   rx + 64 : X
    //             *
    //             * Dump output format remains:
    //             *   X || Y || Z
    //             */
    //             const uint8_t *z = rx;
    //             const uint8_t *y = rx + 32;
    //             const uint8_t *x = rx + 64;

    //             out << le_bytes_to_be_hex(x, 32)
    //                 << '_'
    //                 << le_bytes_to_be_hex(y, 32)
    //                 << '_'
    //                 << le_bytes_to_be_hex(z, 32)
    //                 << '\n';
    //         }
    //     }
    // }

    // out.close();

    // std::cerr << "[MSM TEST] raw bucket dump written: "
    //           << dump_file
    //           << ", lines=" << (WINDOW_COUNT * BUCKETS_PER_WINDOW)
    //           << std::endl;

    munmap(pt_buf, PT_MAP_SIZE);
    munmap(sc_buf, SC_MAP_SIZE);
    munmap(rx_buf, RX_MAP_SIZE);
    munmap(desc_pool, DESC_MAP_SIZE);
    close(fd);

    return 0;
}