#!/usr/bin/env python3
"""Report HLASM fixed-format column issues in src/."""
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"


def main() -> None:
    for p in sorted(SRC.iterdir()):
        if p.suffix.lower() not in {".asm", ".mac", ".inc"}:
            continue
        issues = []
        lines = p.read_text(encoding="utf-8").splitlines()
        for i, l in enumerate(lines, 1):
            n = len(l)
            if n > 72:
                issues.append((i, n, "GT72", l))
            elif n == 72:
                # continuation line expected next starting around col 16
                nxt = lines[i] if i < len(lines) else ""
                issues.append((i, n, f"CONT:{l[71]!r}", l))
                if nxt and not nxt.startswith(" ") and not nxt.startswith("*"):
                    issues.append((i + 1, len(nxt), "BADCONT", nxt))
            # truncated-looking remarks (ended mid-word without cont)
            if n == 71 and l.rstrip() == l and not l.endswith(("X", " ", ",")):
                # heuristic skip
                pass
        if issues:
            print(f"=== {p.name} ===")
            for i, n, kind, l in issues:
                print(f"  {i}:{n}:{kind}:{l}")
        else:
            print(f"{p.name}: OK")


if __name__ == "__main__":
    main()
