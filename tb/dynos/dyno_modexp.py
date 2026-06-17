"""
Dyno test for gf_modexp_engine — verifies ModExp through gf_engine_if.

This is a minimal test harness that connects directly to the engine
through the formally specified interface, verifying the engine in isolation.
"""
import cocotb
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dyno_common import (
    setup_clock, reset_dut, drive_command, collect_result,
    get_width, get_opcode
)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "model"))
from golden_model import modexp


@cocotb.test()
async def test_modexp_basic(dut):
    """Basic ModExp: 2^10 mod 1000 = 1024 mod 1000 = 24"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, e, m = 2, 10, 1000
    expected = modexp(a, e, m, width)

    # Extend exponent to EXP_W if needed
    exp_w = int(os.environ.get("EXP_W", str(width)))
    if exp_w > width:
        e = e << (exp_w - width)

    await drive_command(dut, get_opcode("modexp"), 0x01, a, e, m, width)
    txn_id, status, result = await collect_result(dut)

    assert txn_id == 0x01, f"txn_id: got {txn_id:#x} want 0x01"
    assert status == 0, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info(f"ModExp({a}^{e} mod {m}) = {result} [PASS]")


@cocotb.test()
async def test_modexp_identity(dut):
    """ModExp identity: a^1 mod m = a"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 42, 1000
    exp_w = int(os.environ.get("EXP_W", str(width)))
    e = 1
    if exp_w > width:
        e = e << (exp_w - width)

    expected = modexp(a, e, m, width)

    await drive_command(dut, get_opcode("modexp"), 0x02, a, e, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == 0, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info(f"ModExp({a}^1 mod {m}) = {result} [PASS]")


@cocotb.test()
async def test_modexp_zero_exponent(dut):
    """ModExp: a^0 mod m = 1"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 42, 1000
    exp_w = int(os.environ.get("EXP_W", str(width)))
    e = 0

    expected = modexp(a, e, m, width)

    await drive_command(dut, get_opcode("modexp"), 0x03, a, e, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == 0, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info(f"ModExp({a}^0 mod {m}) = {result} [PASS]")


@cocotb.test()
async def test_modexp_invalid_modulus(dut):
    """Error path: m=0 should return STATUS_INVALID_INPUT"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, e, m = 2, 10, 0

    await drive_command(dut, get_opcode("modexp"), 0x04, a, e, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == 1, f"status: got {status} want STATUS_INVALID_INPUT"

    dut._log.info("Invalid modulus (m=0) correctly rejected [PASS]")


@cocotb.test()
async def test_modexp_backpressure(dut):
    """Verify engine completes even with delayed result read"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, e, m = 3, 7, 100
    exp_w = int(os.environ.get("EXP_W", str(width)))
    if exp_w > width:
        e = e << (exp_w - width)

    expected = modexp(a, e, m, width)

    await drive_command(dut, get_opcode("modexp"), 0x05, a, e, m, width)

    # Wait several cycles before reading (backpressure)
    for _ in range(50):
        await RisingEdge(dut.clk_i)

    txn_id, status, result = await collect_result(dut)

    assert status == 0, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info("Backpressure test passed [PASS]")
