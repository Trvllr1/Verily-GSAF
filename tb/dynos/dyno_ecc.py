"""
Dyno test for gf_ecc_engine — verifies ECC operations through gf_engine_if.

This is a minimal test harness that connects directly to the engine
through the formally specified interface, verifying the engine in isolation.
"""
import cocotb
from cocotb.triggers import RisingEdge
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from dyno_common import (
    setup_clock, reset_dut, drive_command, collect_result,
    get_opcode
)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "model"))
from golden_model import STATUS_OK, STATUS_UNSUPPORTED


@cocotb.test()
async def test_x25519_completes(dut):
    """X25519 engine completes and returns STATUS_OK"""
    await setup_clock(dut)
    await reset_dut(dut)

    scalar = 9
    base_u = 9

    await drive_command(dut, get_opcode("ecc_x25519"), 0x40, scalar, base_u, 0, 255)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert txn_id == 0x40, f"txn_id: got {txn_id:#x} want 0x40"
    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"X25519({scalar}, {base_u}) completed, result={result:#x} [PASS]")


@cocotb.test()
async def test_x25519_base_point(dut):
    """X25519 with base point u=1"""
    await setup_clock(dut)
    await reset_dut(dut)

    scalar = 0x77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a
    base_u = 1

    await drive_command(dut, get_opcode("ecc_x25519"), 0x41, scalar, base_u, 0, 255)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"X25519(scalar, 1) completed, result={result:#x} [PASS]")


@cocotb.test()
async def test_ecc_unsupported_opcode(dut):
    """Error path: OP_MODEXP (0x0) on ECC engine should return STATUS_UNSUPPORTED"""
    await setup_clock(dut)
    await reset_dut(dut)

    await drive_command(dut, 0x0, 0x43, 0, 0, 0, 255)
    txn_id, status, result = await collect_result(dut)

    assert status == STATUS_UNSUPPORTED, f"status: got {status} want STATUS_UNSUPPORTED"

    dut._log.info(f"Unsupported opcode correctly rejected [PASS]")


@cocotb.test()
async def test_ecc_engine_completes(dut):
    """Verify engine completes and returns to idle"""
    await setup_clock(dut)
    await reset_dut(dut)

    scalar = 1
    base_u = 9

    await drive_command(dut, get_opcode("ecc_x25519"), 0x44, scalar, base_u, 0, 255)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"Engine completed successfully, result={result:#x} [PASS]")
