#!/usr/bin/env python3
"""Shape of an mSecure CSV export, with no contents (N1: safe to paste into an AI session).
Prints, for every row with fewer than 3 fields: its row number, how many fields, each field's
length and whether it is only whitespace, and the mSecure type of the row before it.
Usage: scripts/csvshape.py path/to/mSecure.csv"""
import csv, sys
from collections import Counter
rows = list(csv.reader(open(sys.argv[1], encoding="utf-8-sig", newline="")))
rows = [r for r in rows if r != [] and r != [""]]
print(f"rows (excluding blank lines): {len(rows)}  (first is the title line)")
print("types:", dict(Counter(r[1] for r in rows[1:] if len(r) > 1)))
multiline = sum(1 for r in rows for f in r if "\n" in f)
print(f"fields containing a line break inside quotes: {multiline}")
for n, r in enumerate(rows[1:], start=2):
    if len(r) < 3:
        prev = rows[n - 2]
        shape = ", ".join(f"len {len(f)}{' blank' if not f.strip() else ''}" for f in r)
        print(f"row {n}: {len(r)} field(s) [{shape}]; row before is type "
              f"'{prev[1] if len(prev) > 1 else '?'}' with {len(prev)} fields")
