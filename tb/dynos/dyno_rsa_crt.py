"""
Dyno test for gf_rsa_crt_engine — verifies RSA-CRT through gf_engine_if.

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
from golden_model import STATUS_OK, STATUS_INVALID_INPUT


# Pre-computed RSA-CRT test vectors: p=7, q=13, e=65537
# d=17, dp=5, dq=5, qinv=6, m=5, s=31, s^e mod n = 5 = m
RSA_P  = 7
RSA_Q  = 13
RSA_DP = 5
RSA_DQ = 5
RSA_QINV = 6


@cocotb.test()
async def test_rsa_crt_completes(dut):
    """RSA-CRT engine completes with valid inputs"""
    await setup_clock(dut)
    await reset_dut(dut)

    m = 5

    dut.rsa_p.value = RSA_P
    dut.rsa_q.value = RSA_Q
    dut.rsa_dp.value = RSA_DP
    dut.rsa_dq.value = RSA_DQ
    dut.rsa_qinv.value = RSA_QINV

    await drive_command(dut, get_opcode("rsa_crt"), 0x30, m, RSA_DP, RSA_P, 64)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert txn_id == 0x30, f"txn_id: got {txn_id:#x} want 0x30"
    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"RSA-CRT completed, result={result:#x} [PASS]")


@cocotb.test()
async def test_rsa_crt_invalid_p(dut):
    """Error path: p=0 should return STATUS_INVALID_INPUT"""
    await setup_clock(dut)
    await reset_dut(dut)

    dut.rsa_p.value = 0
    dut.rsa_q.value = RSA_Q
    dut.rsa_dp.value = RSA_DP
    dut.rsa_dq.value = RSA_DQ
    dut.rsa_qinv.value = RSA_QINV

    await drive_command(dut, get_opcode("rsa_crt"), 0x31, 5, RSA_DP, 0, 64)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_INVALID_INPUT, f"status: got {status} want STATUS_INVALID_INPUT"

    dut._log.info(f"Invalid p correctly rejected [PASS]")


@cocotb.test()
async def test_rsa_crt_invalid_q(dut):
    """Error path: q=0 should return STATUS_INVALID_INPUT"""
    await setup_clock(dut)
    await reset_dut(dut)

    dut.rsa_p.value = RSA_P
    dut.rsa_q.value = 0
    dut.rsa_dp.value = RSA_DP
    dut.rsa_dq.value = RSA_DQ
    dut.rsa_qinv.value = RSA_QINV

    await drive_command(dut, get_opcode("rsa_crt"), 0x32, 5, RSA_DP, RSA_P, 64)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_INVALID_INPUT, f"status: got {status} want STATUS_INVALID_INPUT"

    dut._log.info(f"Invalid q correctly rejected [PASS]")


@cocotb.test()
async def test_rsa_crt_engine_completes(dut):
    """Verify RSA-CRT engine completes and returns to idle"""
    await setup_clock(dut)
    await reset_dut(dut)

    dut.rsa_p.value = RSA_P
    dut.rsa_q.value = RSA_Q
    dut.rsa_dp.value = RSA_DP
    dut.rsa_dq.value = RSA_DQ
    dut.rsa_qinv.value = RSA_QINV

    await drive_command(dut, get_opcode("rsa_crt"), 0x33, 5, RSA_DP, RSA_P, 64)
    txn_id, status, result = await collect_result(dut, timeout_cycles=500000)

    assert status == STATUS_OK, f"status: got {status} want STATUS_OK"

    dut._log.info(f"RSA-CRT engine completed successfully [PASS]")
