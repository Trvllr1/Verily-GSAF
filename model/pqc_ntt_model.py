"""
GSAF PQC Engine Golden Model - NTT arithmetic for ML-KEM and ML-DSA
Copyright (c) 2026 Verily. All rights reserved.

This is the executable algorithmic specification for the gf_pqc_engine
(reserved opcode OP_PQC). It covers the core primitive both NIST PQC
standards are built on: negacyclic polynomial multiplication in
Z_q[X]/(X^256 + 1) via the Number-Theoretic Transform (NTT).

  - ML-DSA (FIPS 204, Dilithium): q = 8380417, complete 8-layer NTT,
    zeta = 1753 (primitive 512th root of unity mod q)
  - ML-KEM (FIPS 203, Kyber):     q = 3329, incomplete 7-layer NTT,
    zeta = 17 (primitive 256th root), degree-1 base multiplication

Architectural significance: an NTT butterfly unit is a modular
multiply-accumulate -- the same resource class as a Montgomery multiplier
lane. The PQC engine therefore drops onto a reserved GSAF engine slot and a
reserved cluster lane with NO scheduler changes, which is the entire
commercial premise of the fabric ("verify the chassis once, add engines").

Every loop is hardware-shaped: fixed iteration counts, no data-dependent
control flow (NTT is naturally constant-time).

Self-test: verifies fast NTT multiplication against O(n^2) schoolbook
negacyclic convolution. Run: python model/pqc_ntt_model.py
"""

from __future__ import annotations

N = 256

# ML-DSA (Dilithium) parameters
DIL_Q = 8380417
DIL_ZETA = 1753           # primitive 512th root of unity mod DIL_Q

# ML-KEM (Kyber) parameters
KYB_Q = 3329
KYB_ZETA = 17             # primitive 256th root of unity mod KYB_Q


def bitrev(x: int, bits: int) -> int:
    r = 0
    for _ in range(bits):
        r = (r << 1) | (x & 1)
        x >>= 1
    return r


# -----------------------------------------------------------------------------
# Reference: schoolbook negacyclic convolution, c = a*b mod (X^n + 1, q)
# -----------------------------------------------------------------------------
def negacyclic_schoolbook(a: list[int], b: list[int], q: int) -> list[int]:
    n = len(a)
    c = [0] * n
    for i in range(n):
        for j in range(n):
            k = i + j
            if k < n:
                c[k] = (c[k] + a[i] * b[j]) % q
            else:
                c[k - n] = (c[k - n] - a[i] * b[j]) % q
    return c


# -----------------------------------------------------------------------------
# ML-DSA: complete negacyclic NTT (Cooley-Tukey fwd / Gentleman-Sande inv)
# Fixed loop bounds; one butterfly = 1 modmul + 1 add + 1 sub (the hardware
# unit). 8 layers x 128 butterflies = 1024 butterflies per transform.
# -----------------------------------------------------------------------------
def ntt_fwd(a: list[int], q: int, zeta: int) -> list[int]:
    n = len(a)
    lg = n.bit_length() - 1
    psis = [pow(zeta, bitrev(i, lg), q) for i in range(n)]
    A = list(a)
    t, m = n, 1
    while m < n:
        t //= 2
        for i in range(m):
            S = psis[m + i]
            for j in range(2 * i * t, 2 * i * t + t):
                U, V = A[j], A[j + t] * S % q
                A[j], A[j + t] = (U + V) % q, (U - V) % q
        m *= 2
    return A


def ntt_inv(A: list[int], q: int, zeta: int) -> list[int]:
    n = len(A)
    lg = n.bit_length() - 1
    izeta = pow(zeta, q - 2, q)
    ipsis = [pow(izeta, bitrev(i, lg), q) for i in range(n)]
    a = list(A)
    t, m = 1, n
    while m > 1:
        h = m // 2
        j1 = 0
        for i in range(h):
            S = ipsis[h + i]
            for j in range(j1, j1 + t):
                U, V = a[j], a[j + t]
                a[j] = (U + V) % q
                a[j + t] = (U - V) * S % q
            j1 += 2 * t
        t *= 2
        m = h
    ninv = pow(n, q - 2, q)
    return [x * ninv % q for x in a]


def dilithium_polymul(a: list[int], b: list[int]) -> list[int]:
    fa = ntt_fwd(a, DIL_Q, DIL_ZETA)
    fb = ntt_fwd(b, DIL_Q, DIL_ZETA)
    fc = [x * y % DIL_Q for x, y in zip(fa, fb)]    # pointwise
    return ntt_inv(fc, DIL_Q, DIL_ZETA)


# -----------------------------------------------------------------------------
# ML-KEM: incomplete 7-layer NTT + degree-1 base multiplication
# (q-1 = 3328 is divisible by 256 but not 512, so the transform stops at
# 128 pairs; products are computed pairwise mod (X^2 - gamma_i))
# -----------------------------------------------------------------------------
KYB_ZETAS = [pow(KYB_ZETA, bitrev(i, 7), KYB_Q) for i in range(128)]


def kyber_ntt(f: list[int]) -> list[int]:
    a = list(f)
    k = 1
    ln = 128
    while ln >= 2:
        for start in range(0, N, 2 * ln):
            z = KYB_ZETAS[k]
            k += 1
            for j in range(start, start + ln):
                t = z * a[j + ln] % KYB_Q
                a[j + ln] = (a[j] - t) % KYB_Q
                a[j] = (a[j] + t) % KYB_Q
        ln //= 2
    return a


def kyber_intt(fhat: list[int]) -> list[int]:
    a = list(fhat)
    ln = 2
    while ln <= 128:
        kbase = 128 // ln
        for bi, start in enumerate(range(0, N, 2 * ln)):
            zinv = pow(KYB_ZETAS[kbase + bi], KYB_Q - 2, KYB_Q)
            for j in range(start, start + ln):
                t = a[j]
                a[j] = (t + a[j + ln]) % KYB_Q
                a[j + ln] = zinv * (t - a[j + ln]) % KYB_Q
        ln *= 2
    ninv = pow(128, KYB_Q - 2, KYB_Q)
    return [x * ninv % KYB_Q for x in a]


def kyber_basemul(fa: list[int], fb: list[int]) -> list[int]:
    """128 independent degree-1 products mod (X^2 - gamma_i)."""
    h = [0] * N
    for i in range(128):
        gamma = pow(KYB_ZETA, 2 * bitrev(i, 7) + 1, KYB_Q)
        a0, a1 = fa[2 * i], fa[2 * i + 1]
        b0, b1 = fb[2 * i], fb[2 * i + 1]
        h[2 * i] = (a0 * b0 + a1 * b1 % KYB_Q * gamma) % KYB_Q
        h[2 * i + 1] = (a0 * b1 + a1 * b0) % KYB_Q
    return h


def kyber_polymul(a: list[int], b: list[int]) -> list[int]:
    return kyber_intt(kyber_basemul(kyber_ntt(a), kyber_ntt(b)))


# -----------------------------------------------------------------------------
# Self-test
# -----------------------------------------------------------------------------
def _selftest() -> None:
    import random
    rng = random.Random(0x70C)

    # root-of-unity sanity
    assert pow(DIL_ZETA, 512, DIL_Q) == 1 and pow(DIL_ZETA, 256, DIL_Q) != 1
    assert pow(KYB_ZETA, 256, KYB_Q) == 1 and pow(KYB_ZETA, 128, KYB_Q) != 1
    print("[PASS] zeta = primitive 512th (ML-DSA) / 256th (ML-KEM) root of unity")

    # ML-DSA: fwd/inv round-trip + polymul vs schoolbook
    for trial in range(10):
        a = [rng.randrange(DIL_Q) for _ in range(N)]
        b = [rng.randrange(DIL_Q) for _ in range(N)]
        assert ntt_inv(ntt_fwd(a, DIL_Q, DIL_ZETA), DIL_Q, DIL_ZETA) == a
        assert dilithium_polymul(a, b) == negacyclic_schoolbook(a, b, DIL_Q)
    print("[PASS] ML-DSA (FIPS 204): 10 NTT round-trips + polymuls vs schoolbook")

    # ML-KEM: round-trip + polymul vs schoolbook
    for trial in range(10):
        a = [rng.randrange(KYB_Q) for _ in range(N)]
        b = [rng.randrange(KYB_Q) for _ in range(N)]
        assert kyber_intt(kyber_ntt(a)) == a
        assert kyber_polymul(a, b) == negacyclic_schoolbook(a, b, KYB_Q)
    print("[PASS] ML-KEM (FIPS 203): 10 NTT round-trips + basemul polymuls vs schoolbook")

    # edge: zero / unit polynomials
    one = [1] + [0] * (N - 1)
    a = [rng.randrange(KYB_Q) for _ in range(N)]
    assert kyber_polymul(a, one) == a
    d = [rng.randrange(DIL_Q) for _ in range(N)]
    assert dilithium_polymul(d, one) == d
    assert kyber_polymul(a, [0] * N) == [0] * N
    print("[PASS] identity / zero polynomial edges")

    print("\nALL PQC NTT GOLDEN MODEL SELF-TESTS PASSED")


if __name__ == "__main__":
    _selftest()
