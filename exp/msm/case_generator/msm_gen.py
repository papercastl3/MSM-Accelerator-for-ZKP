#!/usr/bin/env python3

import argparse
import random
import secrets
from pathlib import Path

from ecc_add import FPGA_ECC_point_adder


# ------------------------------------------------------------
# BN254 / alt_bn128 G1
# Curve: y^2 = x^3 + 3 over Fp
# Generator: (1, 2)
# ------------------------------------------------------------

N = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
CURVE_R = 21888242871839275222246405745257275088548364400416034343698204186575808495617

A = 0
B = 3
G = (1, 2)

# Hardware Montgomery radix
R = 2 ** 255
R_INV = pow(R, -1, N)

# 네가 준 Z1 값.
# Affine Montgomery point를 Jacobian처럼 넣을 때 Z = R mod N.
Z1_MONT = 0x1f37631a3d9cbfac8f5f7492fcfd4f44d0fd2add2f1c6ae587bee7d24f060572

WINDOWS = [11] * 14 + [10] * 10
NUM_WINDOWS = len(WINDOWS)
BUCKETS_PER_WINDOW = 2048


def to_hex256(x: int) -> str:
    if not (0 <= x < (1 << 256)):
        raise ValueError(f"value does not fit in 256 bits: 0x{x:x}")
    return f"{x:064x}"


def inv_mod(x: int, p: int = N) -> int:
    if x == 0:
        raise ZeroDivisionError("inverse of zero")
    return pow(x % p, p - 2, p)


def is_on_curve(pt) -> bool:
    if pt is None:
        return True

    x, y = pt
    return (y * y - (x * x * x + B)) % N == 0


def point_add_affine(p1, p2):
    if p1 is None:
        return p2

    if p2 is None:
        return p1

    x1, y1 = p1
    x2, y2 = p2

    if x1 == x2 and (y1 + y2) % N == 0:
        return None

    if p1 == p2:
        if y1 == 0:
            return None
        lam = (3 * x1 * x1 + A) * inv_mod(2 * y1) % N
    else:
        lam = (y2 - y1) * inv_mod(x2 - x1) % N

    x3 = (lam * lam - x1 - x2) % N
    y3 = (lam * (x1 - x3) - y1) % N

    return x3, y3


def scalar_mul(k: int, pt):
    result = None
    addend = pt

    while k > 0:
        if k & 1:
            result = point_add_affine(result, addend)
        addend = point_add_affine(addend, addend)
        k >>= 1

    return result


def mont_domain_conversion(x: int) -> int:
    """
    Normal field value -> Montgomery domain.
    x * R mod N.
    """
    return (x * R) % N


def mont_domain_exit(x: int) -> int:
    """
    Montgomery domain -> normal field value.
    """
    return (x * R_INV) % N


def affine_to_mont_pair(pt):
    x, y = pt
    return mont_domain_conversion(x), mont_domain_conversion(y)


def random_scalar_254(rng=None) -> int:
    if rng is None:
        return secrets.randbits(254)
    return rng.getrandbits(254)


def random_g1_point(rng=None):
    if rng is None:
        k = secrets.randbelow(CURVE_R - 1) + 1
    else:
        k = rng.randrange(1, CURVE_R)

    pt = scalar_mul(k, G)

    if not is_on_curve(pt):
        raise RuntimeError("generated point is not on curve")

    return pt


def split_scalar_windows(scalar: int):
    """
    MSB side부터 [11bit * 14, 10bit * 10]으로 분해.

    총 254bit:
      14 * 11 + 10 * 10 = 254
    """
    values = []
    bit_pos = 254

    for width in WINDOWS:
        bit_pos -= width
        mask = (1 << width) - 1
        values.append((scalar >> bit_pos) & mask)

    assert bit_pos == 0
    return values


def jacobian_inf():
    return 0, 0, 0


def point_line(point_mont) -> str:
    x_m, y_m = point_mont
    return f"{to_hex256(x_m)}_{to_hex256(y_m)}"


def scalar_line(scalar: int) -> str:
    return to_hex256(scalar)


def bucket_line(bucket) -> str:
    x, y, z = bucket
    return f"{to_hex256(x)}_{to_hex256(y)}_{to_hex256(z)}"


def build_buckets_with_fpga_adder(scalars, points_affine_normal):
    """
    buckets[window][bucket] 생성.

    입력 point:
      normal affine point

    내부 변환:
      point -> Montgomery affine (X_m, Y_m, Z_m=R)

    누적 방식:
      bucket = bucket + point
      실제 호출은 하드웨어 convention에 맞게

        FPGA_ECC_point_adder(
            X1, Y1, Z1,    # incoming affine Montgomery point
            X2, Y2, Z2,    # existing bucket Jacobian Montgomery point
        )

    으로 호출.
    """

    buckets = [
        [jacobian_inf() for _ in range(BUCKETS_PER_WINDOW)]
        for _ in range(NUM_WINDOWS)
    ]

    points_mont = [affine_to_mont_pair(pt) for pt in points_affine_normal]

    for scalar, point_mont in zip(scalars, points_mont):
        digits = split_scalar_windows(scalar)

        x1, y1 = point_mont
        z1 = Z1_MONT

        for win_idx, digit in enumerate(digits):

            width = WINDOWS[win_idx]
            if digit >= (1 << width):
                raise RuntimeError("invalid scalar window digit")

            bucket_idx = digit

            x2, y2, z2 = buckets[win_idx][bucket_idx]

            buckets[win_idx][bucket_idx] = FPGA_ECC_point_adder(
                x1, y1, z1,
                x2, y2, z2,
            )

    return buckets


def write_lines(path: Path, lines):
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def generate(n_power: int, out_dir: Path, seed: int | None):
    count = 1 << n_power
    out_dir.mkdir(parents=True, exist_ok=True)

    expected_z1 = R % N
    if Z1_MONT != expected_z1:
        print("[WARN] Z1_MONT != R mod N")
        print(f"       Z1_MONT      = 0x{Z1_MONT:x}")
        print(f"       expected R%N = 0x{expected_z1:x}")

    if seed is None:
        scalars = [random_scalar_254() for _ in range(count)]
        points = [random_g1_point() for _ in range(count)]
    else:
        rng = random.Random(seed)
        scalars = [random_scalar_254(rng) for _ in range(count)]
        points = [random_g1_point(rng) for _ in range(count)]

    points_mont = [affine_to_mont_pair(pt) for pt in points]
    buckets = build_buckets_with_fpga_adder(scalars, points)

    point_lines = [point_line(p) for p in points_mont]
    scalar_lines = [scalar_line(s) for s in scalars]

    bucket_lines = []

    for win_idx in range(NUM_WINDOWS):
        width = WINDOWS[win_idx]

        for bucket_idx in range(BUCKETS_PER_WINDOW):
            if width == 10 and bucket_idx >= 1024:
                # FPGA도 이 구간을 0으로 내보내야 비교가 깔끔함.
                bucket_lines.append(bucket_line(jacobian_inf()))
            else:
                bucket_lines.append(bucket_line(buckets[win_idx][bucket_idx]))

    write_lines(out_dir / "point.hex", point_lines)
    write_lines(out_dir / "scalar.hex", scalar_lines)
    write_lines(out_dir / "buckets.hex", bucket_lines)

    meta_lines = [
        f"count={count}",
        f"n_power={n_power}",
        f"num_windows={NUM_WINDOWS}",
        f"windows={WINDOWS}",
        f"buckets_per_window={BUCKETS_PER_WINDOW}",
        f"bucket_total_lines={len(bucket_lines)}",
        "point_format=X_Y, each 256-bit Montgomery-domain big-endian hex",
        "scalar_format=256-bit big-endian hex, top 2 bits zero, 254-bit scalar",
        "bucket_format=X_Y_Z, each 256-bit Montgomery-domain Jacobian big-endian hex",
        "bucket_order=window0_bucket0_to_window23_bucket2047",
        "window_order=MSB_to_LSB",
        "adder=FPGA_ECC_point_adder imported from ecc_add.py",
        "adder_input_order=P1_affine_mont_Z_R_plus_P2_bucket_jacobian_mont",
        f"Z1_MONT=0x{Z1_MONT:x}",
        f"R_mod_N=0x{expected_z1:x}",
        "montgomery_R=2^255",
        f"field_p=0x{N:x}",
        f"curve_order={CURVE_R}",
        "curve=y^2=x^3+3",
        "generator=(1,2)",
        f"seed={seed if seed is not None else 'secrets'}",
    ]

    write_lines(out_dir / "meta.txt", meta_lines)

    print(f"Generated {count} scalar/point pairs")
    print(f"Output dir: {out_dir}")
    print(f"- point.hex   : {count} lines")
    print(f"- scalar.hex  : {count} lines")
    print(f"- buckets.hex : {len(bucket_lines)} lines")
    print(f"  = {NUM_WINDOWS} windows * {BUCKETS_PER_WINDOW} buckets")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("n", type=int, help="Generate 2^n scalar/point pairs")
    parser.add_argument("-o", "--out", type=str, default="msm_testdata")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    if args.n < 0:
        raise ValueError("n must be >= 0")

    generate(args.n, Path(args.out), args.seed)


if __name__ == "__main__":
    main()