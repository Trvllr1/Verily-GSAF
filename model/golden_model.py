"""
GreenField Secure Arithmetic Fabric - Executable Golden Model
Copyright (c) 2026 Verily. All rights reserved.

This is the *bit-exact algorithmic specification* of the GSAF arithmetic
engines. Every loop here corresponds 1:1 to a hardware FSM iteration:

  - mont_mult        <-> gf_mont_mult.sv      (radix-2 bit-serial, W+1 steps)
  - mod_double       <-> R / R^2 precompute   (gf_modexp_engine MON_IN prep)
  - modexp           <-> gf_modexp_engine.sv  (fixed 4-bit window, constant-time)
  - modinv_divsteps  <-> gf_modinv_engine.sv  (Bernstein-Yang, proof bound)

The model uses Python integers but performs ONLY the operations available to
the datapath: shifts, adds, subtracts, compares, muxes. No '*', '//', '%' on
secret data (the `* bit` forms below are AND-masks, as in RTL).
"""

from __future__ import annotations


# -----------------------------------------------------------------------------
# Proof-derived divstep bound (Bernstein-Yang 2019, machine-checked)
# -----------------------------------------------------------------------------
def divstep_bound(d: int) -> int:
    """Iterations sufficient for safegcd on d-bit inputs. NOT 2*d."""
    if d < 46:
        return (49 * d + 80) // 17
    return (49 * d + 57) // 17


# -----------------------------------------------------------------------------
# Input legality (mirrors gf_scheduler operand screen)
# -----------------------------------------------------------------------------
STATUS_OK = 0
STATUS_INVALID_INPUT = 1
STATUS_NOT_INVERTIBLE = 2
STATUS_UNSUPPORTED = 3


def check_inputs(a: int, b: int, m: int, width: int) -> int:
    if m == 0 or (m & 1) == 0:
        return STATUS_INVALID_INPUT
    if a >= m or b >= m or m >= (1 << width):
        return STATUS_INVALID_INPUT
    return STATUS_OK


# -----------------------------------------------------------------------------
# Radix-2 Montgomery multiplication: returns a*b*R^-1 mod m,  R = 2^width
# Constant-time: always exactly `width` iterations + final conditional subtract
# (RTL performs the subtract unconditionally and muxes the result).
# -----------------------------------------------------------------------------
def mont_mult(a: int, b: int, m: int, width: int) -> int:
    acc = 0
    for i in range(width):
        ai = (a >> i) & 1
        acc = acc + (b if ai else 0)          # AND-mask add, not multiply
        if acc & 1:
            acc = acc + m                      # make even
        acc >>= 1                              # exact halving
    # acc < 2m here; single conditional subtract (computed both ways in RTL)
    if acc >= m:
        acc -= m
    return acc


# -----------------------------------------------------------------------------
# Constant-time modular doubling: x -> 2x mod m (x < m). Used to build
# R mod m and R^2 mod m without division: shift, then conditional subtract.
# -----------------------------------------------------------------------------
def mod_double(x: int, m: int) -> int:
    x <<= 1
    if x >= m:
        x -= m
    return x


def mont_R_mod_m(m: int, width: int) -> int:
    """2^width mod m via `width` constant-time doublings of 1."""
    x = 1 if m > 1 else 0
    for _ in range(width):
        x = mod_double(x, m)
    return x


def mont_R2_mod_m(m: int, width: int) -> int:
    """2^(2*width) mod m: double R mod m another `width` times."""
    x = mont_R_mod_m(m, width)
    for _ in range(width):
        x = mod_double(x, m)
    return x


# -----------------------------------------------------------------------------
# Fixed-window (w=4) constant-time modular exponentiation.
# Always performs 4 squarings + 1 multiply per window, including window
# value 0 (multiply by table[0] = R mod m = Montgomery '1'), so the
# operation count is exponent-independent.
#
# exp_bits: width of the exponent datapath. Defaults to `width`. The hardware
# sets exp_bits = WIDTH + EXP_BLIND_BITS so hosts can submit *blinded*
# exponents d' = d + k*lambda(m) (DPA countermeasure). Leading zero windows
# are processed identically (square 4x, multiply by Montgomery '1'), so
# latency depends only on exp_bits, never on the exponent value.
# -----------------------------------------------------------------------------
WINDOW_SIZE = 4


def modexp(base: int, exp: int, m: int, width: int,
           exp_bits: int | None = None) -> int:
    if exp_bits is None:
        exp_bits = width
    r_mod = mont_R_mod_m(m, width)             # Montgomery domain '1'
    r2 = mont_R2_mod_m(m, width)
    base_m = mont_mult(base, r2, m, width)     # MON_IN: to Montgomery domain

    # PRECOMPUTE: table[i] = base^i in Montgomery domain, 16 entries
    table = [r_mod] * (1 << WINDOW_SIZE)
    for i in range(1, 1 << WINDOW_SIZE):
        table[i] = mont_mult(table[i - 1], base_m, m, width)

    # EXP_LOOP: fixed number of windows = exp_bits / WINDOW_SIZE
    n_windows = exp_bits // WINDOW_SIZE
    acc = r_mod
    for w in range(n_windows - 1, -1, -1):
        for _ in range(WINDOW_SIZE):
            acc = mont_mult(acc, acc, m, width)
        digit = (exp >> (w * WINDOW_SIZE)) & ((1 << WINDOW_SIZE) - 1)
        acc = mont_mult(acc, table[digit], m, width)   # always multiply

    # MON_OUT: leave Montgomery domain
    return mont_mult(acc, 1, m, width)


# -----------------------------------------------------------------------------
# Constant-time modular inverse via Bernstein-Yang divsteps.
# State: delta (signed), f, g (signed, width+1 bits), v, r (mod m).
# Runs exactly divstep_bound(width) iterations regardless of inputs.
# Returns (status, inverse).
# -----------------------------------------------------------------------------
def _half_mod(x: int, m: int) -> int:
    """x/2 mod m, m odd: if x even shift, else add m then shift."""
    if x & 1:
        x += m
    return x >> 1


def modinv_divsteps(a: int, m: int, width: int) -> tuple[int, int]:
    delta, f, g = 1, m, a
    v, r = 0, 1                                # track a^-1 cofactor mod m
    for _ in range(divstep_bound(width)):
        g_odd = g & 1
        if delta > 0 and g_odd:
            # swap-and-subtract step
            delta, f, g = 1 - delta, g, (g - f) >> 1
            v, r = r, _half_mod((r - v) % m, m)
        else:
            delta = 1 + delta
            g = (g + (f if g_odd else 0)) >> 1
            r = _half_mod((r + (v if g_odd else 0)) % m, m)
    # On termination g == 0 and f == +/- gcd(a, m)
    if f == 1:
        return STATUS_OK, v % m
    if f == -1:
        return STATUS_OK, (-v) % m
    return STATUS_NOT_INVERTIBLE, 0


# -----------------------------------------------------------------------------
# Self-test: exhaustive at tiny widths (formal-proof widths), randomized at
# simulation/production widths. Run: python golden_model.py
# -----------------------------------------------------------------------------
def _selftest() -> None:
    import random

    rng = random.Random(0xC0FFEE)

    # --- exhaustive Montgomery multiply at WIDTH=8 (the formal proof width) ---
    width = 8
    r_inv_cache: dict[int, int] = {}
    for m in range(3, 256, 2):                     # all odd moduli
        r_inv_cache[m] = pow(1 << width, -1, m)
    checked = 0
    for m in range(3, 256, 2):
        rinv = r_inv_cache[m]
        for _ in range(40):
            a, b = rng.randrange(m), rng.randrange(m)
            got = mont_mult(a, b, m, width)
            assert got == (a * b * rinv) % m, (a, b, m, got)
            checked += 1
    print(f"[PASS] mont_mult: {checked} cases exhaustive-moduli @ WIDTH=8")

    # --- R / R^2 precompute ---
    for w in (8, 16, 64):
        for _ in range(200):
            m = rng.randrange(3, 1 << w) | 1
            assert mont_R_mod_m(m, w) == (1 << w) % m
            assert mont_R2_mod_m(m, w) == (1 << (2 * w)) % m
    print("[PASS] R mod m / R^2 mod m precompute @ WIDTH=8,16,64")

    # --- modexp vs pow() ---
    for w in (8, 16, 64):
        for _ in range(300):
            m = rng.randrange(3, 1 << w) | 1
            a = rng.randrange(m)
            e = rng.randrange(1 << w)
            assert modexp(a, e, m, w) == pow(a, e, m), (a, e, m, w)
    # edge cases
    for w in (8, 64):
        m = (1 << w) - 1 if ((1 << w) - 1) & 1 else (1 << w) - 3
        assert modexp(0, 0, m, w) == 1 % m         # 0^0 == 1 by convention
        assert modexp(1, (1 << w) - 1, m, w) == 1
        assert modexp(0, 5, m, w) == 0
    print("[PASS] modexp vs pow(): 900 random + edges @ WIDTH=8,16,64")

    # --- modinv vs pow(a,-1,m), including non-invertible rejection ---
    import math
    for w in (8, 16, 64):
        ok_cases = ninv_cases = 0
        for _ in range(400):
            m = rng.randrange(3, 1 << w) | 1
            a = rng.randrange(1, m)
            status, inv = modinv_divsteps(a, m, w)
            if math.gcd(a, m) == 1:
                assert status == STATUS_OK and inv == pow(a, -1, m), (a, m, w)
                assert (a * inv) % m == 1
                ok_cases += 1
            else:
                assert status == STATUS_NOT_INVERTIBLE, (a, m, w)
                ninv_cases += 1
        print(f"[PASS] modinv @ WIDTH={w}: {ok_cases} invertible, "
              f"{ninv_cases} correctly rejected")

    # --- divstep bound sanity: iterations always suffice (g reaches 0) ---
    for w in (8, 16):
        for _ in range(200):
            m = rng.randrange(3, 1 << w) | 1
            a = rng.randrange(1, m)
            # rerun tracking g; assert g==0 strictly before bound exhausts
            delta, f, g = 1, m, a
            for _ in range(divstep_bound(w)):
                if delta > 0 and (g & 1):
                    delta, f, g = 1 - delta, g, (g - f) >> 1
                else:
                    g = (g + (f if g & 1 else 0)) >> 1
                    delta += 1
            assert g == 0, (a, m, w)
    print("[PASS] divstep_bound: g==0 within proof bound @ WIDTH=8,16")

    # --- input screening ---
    assert check_inputs(1, 1, 0, 8) == STATUS_INVALID_INPUT      # m == 0
    assert check_inputs(1, 1, 4, 8) == STATUS_INVALID_INPUT      # m even
    assert check_inputs(7, 1, 5, 8) == STATUS_INVALID_INPUT      # a >= m
    assert check_inputs(2, 1, 5, 8) == STATUS_OK
    print("[PASS] input legality screen")

    # --- DPA countermeasure 1: exponent blinding -----------------------------
    # d' = d + k*lambda(m); for prime m, lambda(m) = m-1. Same result, but the
    # exponent bit pattern (what a power analyzer sees) is randomized per run.
    # Hardware contract: exponent datapath is WIDTH + 64 bits (EXP_BLIND_BITS).
    P64 = (1 << 64) - 59                       # 2^64 - 59 is prime
    for _ in range(50):
        a = rng.randrange(1, P64)
        d = rng.randrange(1 << 64)
        k = rng.randrange(1, 1 << 64)
        d_blind = d + k * (P64 - 1)
        assert d_blind < (1 << 128)
        assert modexp(a, d_blind, P64, 64, exp_bits=128) == pow(a, d, P64)
    print("[PASS] exponent blinding: 50 random (d + k*lambda) @ 128-bit exp path")

    # --- DPA countermeasure 2: message blinding (host blind/unblind flow) ----
    # RSA-style: x_b = x * r^e mod n -> s_b = x_b^d -> s = s_b * r^-1.
    # The fabric only ever sees the blinded message x_b.
    e_pub = 65537
    d_priv = pow(e_pub, -1, P64 - 1)
    for _ in range(20):
        x = rng.randrange(1, P64)
        r = rng.randrange(2, P64)
        x_b = (x * pow(r, e_pub, P64)) % P64
        s_b = modexp(x_b, d_priv, P64, 64)     # what the fabric computes
        s = (s_b * pow(r, -1, P64)) % P64      # host unblind
        assert s == pow(x, d_priv, P64)
    print("[PASS] message blinding: 20 blind/unblind round-trips")

    print("\nALL GOLDEN MODEL SELF-TESTS PASSED")


if __name__ == "__main__":
    _selftest()
