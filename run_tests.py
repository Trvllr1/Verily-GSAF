"""Run PQC and RSA-CRT cocotb tests via Python (no Make needed)."""
import subprocess, sys, os

 RTL_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "rtl")
 RTL_DIR = os.path.abspath(RTL_DIR)

 tests = {
     "pqc": {
         "module": "dyno_pqc",
         "toplevel": "tb_dyno_pqc",
         "sources": [
             "gf_pkg.sv", "gf_mont_mult.sv", "gf_pqc_engine.sv",
             "gf_pqc_engine_wrapper.sv",
         ],
         "tb": "tb_dyno_pqc.sv",
     },
     "rsa_crt": {
         "module": "dyno_rsa_crt",
         "toplevel": "tb_dyno_rsa_crt",
         "sources": [
             "gf_pkg.sv", "gf_mont_mult.sv", "gf_montgomery_cluster.sv",
             "gf_rsa_crt_engine.sv", "gf_rsa_crt_engine_wrapper.sv",
         ],
         "tb": "tb_dyno_rsa_crt.sv",
     },
 }

 for name, cfg in tests.items():
     print(f"\n{'='*50}")
     print(f"Running {name} test...")
     print(f"{'='*50}")

     sources = " ".join(os.path.join(RTL_DIR, s) for s in cfg["sources"])
     tb_path = os.path.join(os.path.dirname(__file__), cfg["tb"])

     env = os.environ.copy()
     env["MODULE"] = cfg["module"]
     env["TOPLEVEL"] = cfg["toplevel"]
     env["SIM"] = "verilator"
     env["VERILOG_SOURCES"] = f"{sources} {tb_path}"
     env["COMPILE_ARGS"] = "-I" + RTL_DIR + " --timing"
     # Point to Windows Python's cocotb
     env["PATH"] = os.path.dirname(sys.executable) + ";" + env.get("PATH", "")

     # Use cocotb's makefiles from the Windows install
     import cocotb
     mk_dir = os.path.join(os.path.dirname(cocotb.__file__), "share", "makefiles")
     mk_sim = os.path.join(mk_dir, "Makefile.sim")

     if not os.path.exists(mk_sim):
         print(f"  SKIP: Makefile.sim not found at {mk_sim}")
         print(f"  cocotb {cocotb.__version__} Windows install lacks Makefiles")
         continue

     result = subprocess.run(
         ["make", "-f", mk_sim, "sim"],
         cwd=os.path.dirname(__file__),
         env=env,
         capture_output=True, text=True, timeout=300
     )
     print(result.stdout[-2000:] if len(result.stdout) > 2000 else result.stdout)
     if result.returncode != 0:
         print(f"  FAIL (exit code {result.returncode})")
         print(result.stderr[-1000:] if result.stderr else "")
     else:
         print(f"  PASS")
