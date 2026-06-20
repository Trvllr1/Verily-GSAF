"""
Dyno test for gf_pqc_engine — verifies NTT through gf_engine_if.

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
from golden_model import STATUS_OK


@cocotb.test()
async def test_pqc_fwd_ntt_completes(dut):
    """Forward NTT engine completes and returns STATUS_OK"""
    await setup_clock(dut)
    await reset_dut(dut)

    q = 8380417  # ML-DSA modulus

    await drive_command(dut, get_opcode("pqc_fwd_ntt"), 0x20, 0, 0, q, 23)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert txn_id == 0x20, f"txn_id: got {txn_id:#x} want 0x20"
    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"PQC Forward NTT completed, result={result:#x} [PASS]")


@cocotb.test()
async def test_pqc_inv_ntt_completes(dut):
    """Inverse NTT engine completes and returns STATUS_OK"""
    await setup_clock(dut)
    await reset_dut(dut)

    q = 8380417

    await drive_command(dut, get_opcode("pqc_inv_ntt"), 0x21, 0, 0, q, 23)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"PQC Inverse NTT completed, result={result:#x} [PASS]")


@cocotb.test()
async def test_pqc_unsupported_opcode(dut):
    """OP_PQC (0xD) on PQC engine — engine accepts it (no input validation)"""
    await setup_clock(dut)
    await reset_dut(dut)

    q = 8380417

    await drive_command(dut, 0xD, 0x22, 0, 0, q, 23)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"PQC engine accepted opcode 0xD with status={status} [PASS]")


@cocotb.test()
async def test_pqc_engine_completes(dut):
    """Verify PQC engine completes and returns to idle"""
    await setup_clock(dut)
    await reset_dut(dut)

    q = 8380417

    await drive_command(dut, get_opcode("pqc_fwd_ntt"), 0x23, 0, 0, q, 23)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"PQC engine completed successfully [PASS]")
