"""
GSAF RSA-CRT Engine Golden Model
Copyright (c) 2026 Verily. All rights reserved.

This is the executable algorithmic specification for the gf_rsa_crt_engine
(reserved opcode OP_RSA_CRT). It implements RSA private key operation using
Chinese Remainder Theorem (CRT) optimization with Bellcore-attack hardening.

Algorithm:
  Given: m (message), d (private exponent), n = p*q (modulus)
  Precomputed: dp = d mod (p-1), dq = d mod (q-1), qinv = q^-1 mod p

  CRT computation:
    s1 = m^dp mod p
    s2 = m^dq mod q
    h = qinv * (s1 - s2) mod p
    s = s2 + q * h

  Bellcore-attack hardening (verify-after-sign):
    Verify: s^e mod n == m
    If not, report STATUS_FAULT

Security properties:
  - Constant-time: all operations have fixed latency
  - Fault detection: verify-after-sign prevents Bellcore attack
  - No silent faults: any error reports STATUS_FAULT

Self-test: verifies CRT result against direct modular exponentiation.
Run: python model/rsa_crt_model.py
"""

from __future__ import annotations


# -----------------------------------------------------------------------------
# Modular exponentiation (for verification and direct comparison)
# -----------------------------------------------------------------------------
def modexp(base: int, exp: int, mod: int) -> int:
    """Standard modular exponentiation for verification."""
    result = 1
    base = base % mod
    while exp > 0:
        if exp & 1:
            result = (result * base) % mod
        exp >>= 1
        base = (base * base) % mod
    return result


# -----------------------------------------------------------------------------
# Extended Euclidean Algorithm for modular inverse
# -----------------------------------------------------------------------------
def modinv(a: int, m: int) -> int:
    """Compute modular inverse a^-1 mod m using extended Euclidean algorithm."""
    if m == 1:
        return 0
    m0, x0, x1 = m, 0, 1
    while a > 1:
        q = a // m
        m, a = a % m, m
        x0, x1 = x1 - q * x0, x0
    if x1 < 0:
        x1 += m0
    return x1


# -----------------------------------------------------------------------------
# RSA-CRT computation
# -----------------------------------------------------------------------------
def rsa_crt(m: int, p: int, q: int, dp: int, dq: int, qinv: int,
            e: int = 65537) -> tuple[int, int]:
    """
    RSA-CRT private key operation with Bellcore-attack hardening.

    Args:
        m: message (0 <= m < n where n = p*q)
        p, q: prime factors of n
        dp: d mod (p-1)
        dq: d mod (q-1)
        qinv: q^-1 mod p
        e: public exponent (for verification)

    Returns:
        (status, signature)
        status: 0 = OK, 7 = FAULT (verification failed)
        signature: computed signature (valid only if status == 0)
    """
    n = p * q

    # Input validation
    if m < 0 or m >= n:
        return (1, 0)  # STATUS_INVALID_INPUT
    if p <= 1 or q <= 1:
        return (1, 0)  # STATUS_INVALID_INPUT
    if p == q:
        return (1, 0)  # p and q must be distinct

    # CRT computation
    s1 = modexp(m, dp, p)
    s2 = modexp(m, dq, q)

    # h = qinv * (s1 - s2) mod p
    h = (qinv * ((s1 - s2) % p)) % p

    # s = s2 + q * h
    s = s2 + q * h

    # Bellcore-attack hardening: verify s^e mod n == m
    # This prevents fault injection attacks that could reveal factorization
    verification = modexp(s, e, n)
    if verification != m:
        return (7, 0)  # STATUS_FAULT

    return (0, s)  # STATUS_OK


# -----------------------------------------------------------------------------
# Key generation helper
# -----------------------------------------------------------------------------
def generate_rsa_crt_params(p: int, q: int, e: int = 65537) -> dict:
    """
    Generate RSA-CRT parameters from primes.

    Args:
        p, q: distinct primes
        e: public exponent

    Returns:
        Dictionary with n, d, dp, dq, qinv
    """
    n = p * q
    phi_n = (p - 1) * (q - 1)

    # Compute private exponent
    d = modinv(e, phi_n)

    # Compute CRT parameters
    dp = d % (p - 1)
    dq = d % (q - 1)
    qinv = modinv(q, p)

    return {
        'n': n,
        'd': d,
        'dp': dp,
        'dq': dq,
        'qinv': qinv,
        'e': e,
    }


# -----------------------------------------------------------------------------
# Self-test
# -----------------------------------------------------------------------------
def _selftest() -> None:
    import random
    rng = random.Random(0x525341)  # "RSA" in hex

    print("Running RSA-CRT golden model self-tests...")

    # Test 1: Basic RSA-CRT vs direct modexp
    # Use small primes for testing
    p, q = 61, 53
    params = generate_rsa_crt_params(p, q)
    n = params['n']

    for _ in range(100):
        m = rng.randrange(0, n)
        status, s = rsa_crt(m, p, q, params['dp'], params['dq'], params['qinv'])
        assert status == 0, f"RSA-CRT failed for m={m}"
        # Verify against direct modexp
        expected = modexp(m, params['d'], n)
        assert s == expected, f"RSA-CRT mismatch: got {s}, expected {expected}"

    print("[PASS] RSA-CRT vs direct modexp: 100 random messages")

    # Test 2: Verify Bellcore-attack detection
    # Inject a fault: flip a bit in s1
    m = rng.randrange(0, n)
    status, s_correct = rsa_crt(m, p, q, params['dp'], params['dq'], params['qinv'])
    assert status == 0

    # Manually compute with fault
    s1_faulty = modexp(m, params['dp'], p) ^ 1  # flip bit
    h_faulty = (params['qinv'] * ((s1_faulty - modexp(m, params['dq'], q)) % p)) % p
    s_faulty = modexp(m, params['dq'], q) + q * h_faulty
    # Verification should fail
    verification = modexp(s_faulty, params['e'], n)
    assert verification != m, "Bellcore attack detection failed"

    print("[PASS] Bellcore-attack detection: fault correctly detected")

    # Test 3: Edge cases
    # m = 0
    status, s = rsa_crt(0, p, q, params['dp'], params['dq'], params['qinv'])
    assert status == 0
    assert s == 0

    # m = 1
    status, s = rsa_crt(1, p, q, params['dp'], params['dq'], params['qinv'])
    assert status == 0
    assert s == 1

    # m = n - 1
    status, s = rsa_crt(n - 1, p, q, params['dp'], params['dq'], params['qinv'])
    assert status == 0
    expected = modexp(n - 1, params['d'], n)
    assert s == expected

    print("[PASS] Edge cases: m=0, m=1, m=n-1")

    # Test 4: Larger primes
    # Generate 512-bit primes for more realistic testing
    def is_prime(n: int, k: int = 20) -> bool:
        """Miller-Rabin primality test."""
        if n < 2:
            return False
        if n == 2 or n == 3:
            return True
        if n % 2 == 0:
            return False

        r, d = 0, n - 1
        while d % 2 == 0:
            r += 1
            d //= 2

        for _ in range(k):
            a = rng.randrange(2, n - 1)
            x = pow(a, d, n)
            if x == 1 or x == n - 1:
                continue
            for _ in range(r - 1):
                x = pow(x, 2, n)
                if x == n - 1:
                    break
            else:
                return False
        return True

    # Find two 64-bit primes
    while True:
        p_large = rng.getrandbits(64) | 1
        if is_prime(p_large):
            break

    while True:
        q_large = rng.getrandbits(64) | 1
        if is_prime(q_large) and q_large != p_large:
            break

    params_large = generate_rsa_crt_params(p_large, q_large)
    n_large = params_large['n']

    for _ in range(10):
        m_large = rng.randrange(0, n_large)
        status, s_large = rsa_crt(m_large, p_large, q_large,
                                   params_large['dp'], params_large['dq'],
                                   params_large['qinv'])
        assert status == 0
        expected_large = modexp(m_large, params_large['d'], n_large)
        assert s_large == expected_large

    print(f"[PASS] Large primes (64-bit): 10 random messages")

    # Test 5: Input validation
    status, _ = rsa_crt(-1, p, q, params['dp'], params['dq'], params['qinv'])
    assert status == 1, "Should reject negative m"

    status, _ = rsa_crt(n, p, q, params['dp'], params['dq'], params['qinv'])
    assert status == 1, "Should reject m >= n"

    status, _ = rsa_crt(0, 1, q, params['dp'], params['dq'], params['qinv'])
    assert status == 1, "Should reject p=1"

    print("[PASS] Input validation: rejected invalid inputs")

    print("\nALL RSA-CRT GOLDEN MODEL SELF-TESTS PASSED")


if __name__ == "__main__":
    _selftest()
