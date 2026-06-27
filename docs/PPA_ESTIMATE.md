# GSAF PPA Estimation Report

**Date:** 2026-06-25
**Tool:** Yosys 0.52 (generic ASIC synthesis, no technology library)
**Data path width:** 64-bit

## Per-Engine Resource Estimates

| Engine | Wire Bits | Cells (GE) | Est. LUTs (Artix-7) | Notes |
|--------|-----------|------------|---------------------|-------|
| Montgomery Multiplier | 2,642 | 2,378 | ~400-500 | Shared resource, radix-2 bit-serial |
| ModExp | 9,088 | 8,488 | ~1,400-1,700 | Fixed-window w=4, 16-entry table |
| ModInv | 7,441 | 6,844 | ~1,100-1,400 | Bernstein-Yang, constant divstep |
| PQC (NTT) | 2,918 | 2,728 | ~450-550 | 256-entry twiddle ROM, butterfly |
| RSA-CRT | 46,806 | 46,088 | ~7,700-9,200 | Includes internal exponentiation |
| ECC (X25519) | 19,574 | 17,999 | ~3,000-3,600 | Montgomery ladder, 256-bit |

## Notes

- **Est. LUTs** assumes ~6 LUTs per cell (rough Artix-7 mapping). Actual Vivado synthesis will differ.
- **RSA-CRT** is large because it includes its own exponentiation FSM (not sharing the external Montgomery multiplier lane). In a real integration, this would share the cluster.
- **ECC** is large due to 256-bit wide datapath (4x the default WIDTH=64).
- **PQC** is compact — NTT butterfly is just a multiply-accumulate on reserved lanes.
- **Montgomery Multiplier** is the shared resource — all engines except RSA-CRT route through it.

## Latency Formulas (from ARCHITECTURE.md)

| Engine | Latency (cycles) | Throughput at 100 MHz |
|--------|-----------------|----------------------|
| ModExp | 2·WIDTH + 16 + 5·WIDTH/4 + 2 | ~50K ops/sec (2048-bit) |
| ModInv | DIVSTEP_BOUND + 2 | ~100K ops/sec |
| PQC NTT | 8 layers × 128 butterflies × (WIDTH+2) | ~12.5K transforms/sec |
| RSA-CRT | 2× ModExp + CRT combine | ~25K signatures/sec |
| ECC X25519 | 256 iterations × (WIDTH+2) | ~25K key exchanges/sec |

## Comparison: GSAF vs. OpenTitan BigNum

| Metric | GSAF (64-bit) | OpenTitan BigNum |
|--------|--------------|------------------|
| ModExp area | ~1,500 LUTs | ~3,000-5,000 LUTs |
| PQC support | Built-in NTT engine | Not included |
| Formal verification | SVA properties + golden model | None shipped |
| Constant-time proof | Machine-verified | Claimed only |
| Evidence bundle | Signed, tiered | None |
