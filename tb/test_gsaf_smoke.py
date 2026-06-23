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
