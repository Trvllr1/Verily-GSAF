#!/usr/bin/env python3
"""Bitwuzla CLI wrapper for yosys-smtbmc."""
import sys, os

sys.path.insert(0, os.path.expanduser("~/.local/lib/python3.14/site-packages"))
from bitwuzla import Bitwuzla, Options

def main():
    opts = Options()
    opts.set("produce-models", True)
    opts.set("incremental", True)
    solver = Bitwuzla(opts)

    input_file = None
    for arg in sys.argv[1:]:
        if not arg.startswith("-") and os.path.isfile(arg):
            input_file = arg
            break

    if input_file:
        with open(input_file) as f:
            lines = f.readlines()
    else:
        lines = sys.stdin.readlines()

    for line in lines:
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("(set-logic"):
            solver.set_logic(line.split()[1].strip(")"))
        elif line.startswith("(declare-fun") or line.startswith("(declare-sort") or line.startswith("(define-fun"):
            solver.parse_term(line)
        elif line.startswith("(assert"):
            solver.assert_formula(solver.parse_term(line))
        elif line.startswith("(check-sat"):
            result = solver.sat()
            print("sat" if result == 1 else "unsat" if result == 0 else "unknown")
            sys.stdout.flush()
        elif line.startswith("(exit"):
            break

if __name__ == "__main__":
    main()
