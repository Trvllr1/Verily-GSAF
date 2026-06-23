"""
cocotb smoke test for GSAF — validates full fabric through AXI4-Lite chassis
Tests ModExp, ModInv, and RSA-CRT against golden model.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.result import TestSuccess, TestFailure
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "model"))
from golden_model import modexp, modinv_divsteps, check_inputs, STATUS_OK, STATUS_INVALID_INPUT


async def reset(dut):
    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)


async def axi_write(dut, addr, data):
    dut.s_axil_awvalid.value = 1
    dut.s_axil_awaddr.value = addr
    dut.s_axil_wvalid.value = 1
    dut.s_axil_wdata.value = data
    dut.s_axil_bready.value = 1
    await RisingEdge(dut.clk_i)
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    while not dut.s_axil_bvalid.value:
        await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.s_axil_bready.value = 0


async def axi_read(dut, addr):
    dut.s_axil_arvalid.value = 1
    dut.s_axil_araddr.value = addr
    dut.s_axil_rready.value = 1
    await RisingEdge(dut.clk_i)
    dut.s_axil_arvalid.value = 0
    while not dut.s_axil_rvalid.value:
        await RisingEdge(dut.clk_i)
    data = dut.s_axil_rdata.value
    await RisingEdge(dut.clk_i)
    dut.s_axil_rready.value = 0
    return int(data)


async def load_operand(dut, bank, region, value, nwords, width=64):
    for w in range(nwords):
        word = (value >> (w * 32)) & 0xFFFFFFFF
        addr = 0x100 + bank * 0x40 + region * 0x10 + w * 4
        await axi_write(dut, addr, word)


async def submit(dut, bank, opcode, txn_id):
    await axi_write(dut, 0x010, (bank << 12) | (opcode << 8) | txn_id)


async def collect(dut, exp_txn, exp_status, exp_result, width=64, words=2):
    guard = 0
    while True:
        resp = await axi_read(dut, 0x014)
        if resp & 0x80000000:
            break
        guard += 1
        if guard > 200000:
            raise TestFailure(f"Timeout waiting for response txn={exp_txn:#x}")
        await RisingEdge(dut.clk_i)

    txn = resp & 0xFF
    status = (resp >> 14) & 0x7
    bank = (resp >> 12) & 0x3

    if txn != exp_txn:
        raise TestFailure(f"txn order: got {txn:#04x} want {exp_txn:#04x}")
    if status != exp_status:
        raise TestFailure(f"txn {txn:#04x} status: got {status} want {exp_status}")

    if exp_status == 0:
        result = 0
        for w in range(words):
            word = await axi_read(dut, 0x100 + bank * 0x40 + 0x30 + w * 4)
            result |= (word << (w * 32))
        if result != exp_result:
            raise TestFailure(f"txn {txn:#04x} result: got {result:#x} want {exp_result:#x}")

    await axi_write(dut, 0x018, 1)


@cocotb.test()
async def test_modexp_basic(dut):
    """Basic ModExp: 2^10 mod 1000 = 1024 mod 1000 = 24"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0

    await reset(dut)

    a, e, m = 2, 10, 1001
    expected = modexp(a, e, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, e, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x0, 0x01)
    await collect(dut, 0x01, STATUS_OK, expected, width, words)

    dut._log.info(f"ModExp({a}^{e} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_modinv_basic(dut):
    """Basic ModInv: 3^-1 mod 7 = 5 (since 3*5=15=1 mod 7)"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0

    await reset(dut)

    a, m = 3, 7
    _, expected = modinv_divsteps(a, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, 0, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x1, 0x02)
    await collect(dut, 0x02, STATUS_OK, expected, width, words)

    dut._log.info(f"ModInv({a} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_invalid_modulus(dut):
    """Error path: m=0 should return STATUS_INVALID_INPUT"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0

    await reset(dut)

    await load_operand(dut, 0, 0, 1, words, width)
    await load_operand(dut, 0, 1, 1, words, width)
    await load_operand(dut, 0, 2, 0, words, width)
    await submit(dut, 0, 0x0, 0x03)
    await collect(dut, 0x03, STATUS_INVALID_INPUT, 0, width, words)

    dut._log.info("Invalid modulus (m=0) correctly rejected [PASS]")


# RSA-CRT register addresses
RSA_P_ADDR   = 0x080
RSA_Q_ADDR   = 0x088
RSA_DP_ADDR  = 0x090
RSA_DQ_ADDR  = 0x098
RSA_QINV_ADDR = 0x0A0


async def write_rsa_param(dut, addr, value, width=64):
    """Write a 64-bit RSA-CRT parameter to two 32-bit registers."""
    await axi_write(dut, addr, value & 0xFFFFFFFF)
    await axi_write(dut, addr + 4, (value >> 32) & 0xFFFFFFFF)


@cocotb.test()
async def test_rsa_crt_basic(dut):
    """RSA-CRT through full chassis: sign m=5 with p=7, q=13, verify result"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())

    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0

    await reset(dut)

    # RSA-CRT parameters: p=7, q=13, dp=5, dq=5, qinv=6, m=5
    # Expected: s = 31 (RSA signature), s^e mod n = 5 = m
    p, q, dp, dq, qinv, m = 7, 13, 5, 5, 6, 5

    # Write RSA-CRT parameters to registers
    await write_rsa_param(dut, RSA_P_ADDR, p, width)
    await write_rsa_param(dut, RSA_Q_ADDR, q, width)
    await write_rsa_param(dut, RSA_DP_ADDR, dp, width)
    await write_rsa_param(dut, RSA_DQ_ADDR, dq, width)
    await write_rsa_param(dut, RSA_QINV_ADDR, qinv, width)

    # Load message into operand bank A (region 0)
    await load_operand(dut, 0, 0, m, words, width)

    # Load dummy modulus into region 2 (scheduler checks it even for RSA-CRT)
    await load_operand(dut, 0, 2, q * p, words, width)

    # Submit RSA-CRT command (opcode 0xC)
    await submit(dut, 0, 0xC, 0x10)

    # Collect result — RSA-CRT returns the signature s
    # The engine computes s = CRT(m, dp, dq, p, q, qinv)
    # For our parameters: s = 31
    await collect(dut, 0x10, STATUS_OK, 31, width, words)

    dut._log.info(f"RSA-CRT({m}, p={p}, q={q}) = 31 [PASS]")


# =============================================================================
# Expanded test coverage — larger values, edge cases, multi-bank
# =============================================================================

@cocotb.test()
async def test_modexp_large(dut):
    """ModExp with larger values: 7^256 mod 999999937 (prime)"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    a, e, m = 7, 256, 999999937
    expected = modexp(a, e, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, e, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x0, 0x04)
    await collect(dut, 0x04, STATUS_OK, expected, width, words)

    dut._log.info(f"ModExp({a}^{e} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_modexp_identity(dut):
    """ModExp identity: a^1 mod m = a mod m"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    a, e, m = 42, 1, 97
    expected = modexp(a, e, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, e, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x0, 0x05)
    await collect(dut, 0x05, STATUS_OK, expected, width, words)

    dut._log.info(f"ModExp({a}^{e} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_modexp_zero_exponent(dut):
    """ModExp: a^0 mod m = 1 mod m"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    a, e, m = 5, 0, 997
    expected = modexp(a, e, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, e, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x0, 0x06)
    await collect(dut, 0x06, STATUS_OK, expected, width, words)

    dut._log.info(f"ModExp({a}^{e} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_modinv_large(dut):
    """ModInv with larger prime: 123456789^-1 mod 1000000007"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    a, m = 123456789, 1000000007
    _, expected = modinv_divsteps(a, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, 0, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x1, 0x07)
    await collect(dut, 0x07, STATUS_OK, expected, width, words)

    dut._log.info(f"ModInv({a} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_modinv_one(dut):
    """ModInv: 1^-1 mod m = 1 for any m"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    a, m = 1, 999983
    _, expected = modinv_divsteps(a, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, 0, words, width)
    await load_operand(dut, 0, 2, m, words, width)
    await submit(dut, 0, 0x1, 0x08)
    await collect(dut, 0x08, STATUS_OK, expected, width, words)

    dut._log.info(f"ModInv({a} mod {m}) = {expected} [PASS]")


@cocotb.test()
async def test_rsa_crt_medium(dut):
    """RSA-CRT with medium primes: p=104729, q=104743, m=42"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    p, q = 104729, 104743
    n = p * q
    e = 65537
    d = pow(e, -1, (p-1)*(q-1))
    dp = d % (p - 1)
    dq = d % (q - 1)
    qinv = pow(q, -1, p)
    m = 42

    await write_rsa_param(dut, RSA_P_ADDR, p, width)
    await write_rsa_param(dut, RSA_Q_ADDR, q, width)
    await write_rsa_param(dut, RSA_DP_ADDR, dp, width)
    await write_rsa_param(dut, RSA_DQ_ADDR, dq, width)
    await write_rsa_param(dut, RSA_QINV_ADDR, qinv, width)

    await load_operand(dut, 0, 0, m, words, width)
    await load_operand(dut, 0, 2, n, words, width)

    await submit(dut, 0, 0xC, 0x09)

    # Compute expected signature
    s1 = pow(m, dp, p)
    s2 = pow(m, dq, q)
    h = (qinv * (s1 - s2)) % p
    expected = s2 + q * h

    await collect(dut, 0x09, STATUS_OK, expected, width, words)

    dut._log.info(f"RSA-CRT({m}, p={p}, q={q}) = {expected} [PASS]")


@cocotb.test()
async def test_multi_bank(dut):
    """Run modexp on bank 0, then modinv on bank 1 — test bank isolation"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    # Bank 0: modexp 2^8 mod 101 = 256 mod 101 = 54
    a, e, m = 2, 8, 101
    expected_exp = modexp(a, e, m, width)

    await load_operand(dut, 0, 0, a, words, width)
    await load_operand(dut, 0, 1, e, words, width)
    await load_operand(dut, 0, 2, m, words, width)

    # Bank 1: modinv 5^-1 mod 11 = 9 (since 5*9=45=1 mod 11)
    a2, m2 = 5, 11
    _, expected_inv = modinv_divsteps(a2, m2, width)

    await load_operand(dut, 1, 0, a2, words, width)
    await load_operand(dut, 1, 1, 0, words, width)
    await load_operand(dut, 1, 2, m2, words, width)

    # Submit both
    await submit(dut, 0, 0x0, 0x0A)
    await submit(dut, 1, 0x1, 0x0B)

    # Collect both — fabric is OOO, modinv completes before modexp
    resp1 = await collect(dut, 0x0B, STATUS_OK, expected_inv, width, words)
    resp2 = await collect(dut, 0x0A, STATUS_OK, expected_exp, width, words)

    dut._log.info(f"Multi-bank: modexp={expected_exp}, modinv={expected_inv} [PASS]")


# =============================================================================
# Randomized / constrained-random testing
# =============================================================================

import random
random.seed(42)  # deterministic for reproducibility


@cocotb.test()
async def test_modexp_random(dut):
    """Randomized ModExp: 5 random valid (a, e, m) triples"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    # Generate 5 random valid triples (a < m, m odd)
    for i in range(5):
        m = random.randrange(3, 1 << min(width, 32), 2)  # odd, fits in 32 bits
        a = random.randrange(1, m)
        e = random.randrange(0, min(width, 32))
        expected = modexp(a, e, m, width)

        await load_operand(dut, 0, 0, a, words, width)
        await load_operand(dut, 0, 1, e, words, width)
        await load_operand(dut, 0, 2, m, words, width)
        await submit(dut, 0, 0x0, 0x20 + i)
        await collect(dut, 0x20 + i, STATUS_OK, expected, width, words)

    dut._log.info(f"ModExp random: 5 cases all PASS")


@cocotb.test()
async def test_modinv_random(dut):
    """Randomized ModInv: 5 random valid (a, m) pairs with gcd(a,m)=1"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    import math
    for i in range(5):
        # Generate random prime-ish modulus (odd, >1)
        m = random.randrange(3, 1 << min(width, 32), 2)
        # Find a coprime to m
        a = random.randrange(1, m)
        while math.gcd(a, m) != 1:
            a = random.randrange(1, m)

        _, expected = modinv_divsteps(a, m, width)

        await load_operand(dut, 0, 0, a, words, width)
        await load_operand(dut, 0, 1, 0, words, width)
        await load_operand(dut, 0, 2, m, words, width)
        await submit(dut, 0, 0x1, 0x30 + i)
        await collect(dut, 0x30 + i, STATUS_OK, expected, width, words)

    dut._log.info(f"ModInv random: 5 cases all PASS")


@cocotb.test()
async def test_rsa_crt_random(dut):
    """Randomized RSA-CRT: 3 random messages with fixed small primes"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    # Fixed medium primes
    p, q = 104729, 104743
    n = p * q
    e = 65537
    d = pow(e, -1, (p-1)*(q-1))
    dp = d % (p - 1)
    dq = d % (q - 1)
    qinv = pow(q, -1, p)

    await write_rsa_param(dut, RSA_P_ADDR, p, width)
    await write_rsa_param(dut, RSA_Q_ADDR, q, width)
    await write_rsa_param(dut, RSA_DP_ADDR, dp, width)
    await write_rsa_param(dut, RSA_DQ_ADDR, dq, width)
    await write_rsa_param(dut, RSA_QINV_ADDR, qinv, width)

    for i in range(3):
        m = random.randrange(2, n)
        s1 = pow(m, dp, p)
        s2 = pow(m, dq, q)
        h = (qinv * (s1 - s2)) % p
        expected = s2 + q * h

        await load_operand(dut, 0, 0, m, words, width)
        await load_operand(dut, 0, 2, n, words, width)
        await submit(dut, 0, 0xC, 0x40 + i)
        await collect(dut, 0x40 + i, STATUS_OK, expected, width, words)

    dut._log.info(f"RSA-CRT random: 3 cases all PASS")


@cocotb.test()
async def test_modexp_random_multi_bank(dut):
    """Randomized ModExp across all 4 banks simultaneously"""
    width = int(os.environ.get("WIDTH", "64"))
    words = width // 32

    clock = Clock(dut.clk_i, 10, units="ns")
    cocotb.start_soon(clock.start())
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value = 0
    dut.s_axil_bready.value = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value = 0
    await reset(dut)

    results = []
    for bank in range(4):
        m = random.randrange(3, 1 << min(width, 32), 2)
        a = random.randrange(1, m)
        e = random.randrange(1, min(width, 32))
        expected = modexp(a, e, m, width)
        results.append((bank, expected))

        await load_operand(dut, bank, 0, a, words, width)
        await load_operand(dut, bank, 1, e, words, width)
        await load_operand(dut, bank, 2, m, words, width)

    # Submit all 4
    for bank in range(4):
        await submit(dut, bank, 0x0, 0x50 + bank)

    # Collect all 4 (OOO order)
    collected = {}
    for _ in range(4):
        guard = 0
        while True:
            resp = await axi_read(dut, 0x014)
            if resp & 0x80000000:
                break
            guard += 1
            if guard > 500000:
                raise TestFailure("Timeout waiting for multi-bank result")
            await RisingEdge(dut.clk_i)

        txn = resp & 0xFF
        status = (resp >> 14) & 0x7
        bnk = (resp >> 12) & 0x3
        assert status == STATUS_OK, f"bank {bnk} status: got {status}"

        result = 0
        for w in range(words):
            word = await axi_read(dut, 0x100 + bnk * 0x40 + 0x30 + w * 4)
            result |= (word << (w * 32))

        collected[bnk] = result
        await axi_write(dut, 0x018, 1)

    # Verify all results
    for bank, expected in results:
        got = collected[bank]
        assert got == expected, f"bank {bank}: got {got:#x} want {expected:#x}"

    dut._log.info(f"ModExp random 4-bank: all PASS")
