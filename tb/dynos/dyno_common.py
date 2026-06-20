"""
Shared infrastructure for GSAF dyno test harnesses.

A "dyno" is a minimal test harness that mimics the chassis — it connects to
a single engine through gf_engine_if.sv and verifies the engine in isolation.

This module provides:
- Clock generation
- Reset sequencing
- AXI-Lite bus driver (simplified for dyno use)
- Golden model bridge for result checking
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, FallingEdge
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "model"))


async def setup_clock(dut, period_ns=10):
    """Start clock generation."""
    clock = Clock(dut.clk_i, period_ns, units="ns")
    cocotb.start_soon(clock.start())
    return clock


async def reset_dut(dut, cycles=5):
    """Apply reset sequence."""
    dut.rst_ni.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)


async def wait_idle(dut, timeout_cycles=10000):
    """Wait for engine to become idle."""
    for _ in range(timeout_cycles):
        if dut.engine_if.engine_idle.value:
            return True
        await RisingEdge(dut.clk_i)
    raise AssertionError(f"Timeout waiting for idle after {timeout_cycles} cycles")


async def drive_command(dut, opcode, txn_id, base, exp, m, width=64):
    """Drive a command through the engine interface."""
    dut.engine_if.cmd_valid.value = 1
    dut.engine_if.cmd_opcode.value = opcode
    dut.engine_if.cmd_txn_id.value = txn_id
    dut.engine_if.cmd_base.value = base
    dut.engine_if.cmd_exp.value = exp
    dut.engine_if.cmd_m.value = m

    # Wait for command accepted
    while not dut.engine_if.cmd_ready.value:
        await RisingEdge(dut.clk_i)

    await RisingEdge(dut.clk_i)
    dut.engine_if.cmd_valid.value = 0


async def collect_result(dut, timeout_cycles=100000):
    """Wait for and collect a result from the engine."""
    dut.engine_if.rsp_ready.value = 0
    for _ in range(timeout_cycles):
        if dut.engine_if.rsp_valid.value:
            # Present ready
            dut.engine_if.rsp_ready.value = 1
            await RisingEdge(dut.clk_i)

            result = int(dut.engine_if.rsp_result.value)
            status = int(dut.engine_if.rsp_status.value)
            txn_id = int(dut.engine_if.rsp_txn_id.value)

            dut.engine_if.rsp_ready.value = 0
            return txn_id, status, result

        await RisingEdge(dut.clk_i)

    raise AssertionError(f"Timeout waiting for result after {timeout_cycles} cycles")


def get_width():
    """Get WIDTH from environment or default."""
    return int(os.environ.get("WIDTH", "64"))


def get_opcode(name):
    """Map opcode name to value."""
    opcodes = {
        "modexp": 0x0,
        "modinv": 0x1,
        "ecc_padd": 0x8,
        "ecc_pdbl": 0x9,
        "ecc_x25519": 0xB,
        "rsa_crt": 0xC,
        "pqc": 0xD,
        "pqc_fwd_ntt": 0xE,
        "pqc_inv_ntt": 0xF,
    }
    return opcodes.get(name, 0x0)
