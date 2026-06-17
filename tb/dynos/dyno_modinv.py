"""
Dyno test for gf_modinv_engine — verifies ModInv through gf_engine_if.

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
from golden_model import modinv_divsteps, STATUS_OK, STATUS_NOT_INVERTIBLE


@cocotb.test()
async def test_modinv_basic(dut):
    """Basic ModInv: 3^-1 mod 7 = 5 (since 3*5=15=1 mod 7)"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 3, 7
    _, expected = modinv_divsteps(a, m, width)

    await drive_command(dut, get_opcode("modinv"), 0x10, a, 0, m, width)
    txn_id, status, result = await collect_result(dut)

    assert txn_id == 0x10, f"txn_id: got {txn_id:#x} want 0x10"
    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info(f"ModInv({a} mod {m}) = {result} [PASS]")


@cocotb.test()
async def test_modinv_larger(dut):
    """ModInv with larger modulus: 123^-1 mod 997"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 123, 997
    _, expected = modinv_divsteps(a, m, width)

    await drive_command(dut, get_opcode("modinv"), 0x11, a, 0, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info(f"ModInv({a} mod {m}) = {result} [PASS]")


@cocotb.test()
async def test_modinv_non_invertible(dut):
    """Non-invertible: gcd(3, 9) = 3 != 1"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 3, 9

    await drive_command(dut, get_opcode("modinv"), 0x12, a, 0, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == STATUS_NOT_INVERTIBLE, f"status: got {status} want STATUS_NOT_INVERTIBLE"

    dut._log.info(f"Non-invertible ({a}, {m}) correctly rejected [PASS]")


@cocotb.test()
async def test_modinv_invalid_modulus(dut):
    """Error path: m=0 should return STATUS_INVALID_INPUT"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 3, 0

    await drive_command(dut, get_opcode("modinv"), 0x13, a, 0, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == 1, f"status: got {status} want STATUS_INVALID_INPUT"

    dut._log.info("Invalid modulus (m=0) correctly rejected [PASS]")


@cocotb.test()
async def test_modinv_identity(dut):
    """ModInv identity: 1^-1 mod m = 1"""
    width = get_width()
    await setup_clock(dut)
    await reset_dut(dut)

    a, m = 1, 1000
    _, expected = modinv_divsteps(a, m, width)

    await drive_command(dut, get_opcode("modinv"), 0x14, a, 0, m, width)
    txn_id, status, result = await collect_result(dut)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"
    assert result == expected, f"result: got {result:#x} want {expected:#x}"

    dut._log.info(f"ModInv(1 mod {m}) = {result} [PASS]")
