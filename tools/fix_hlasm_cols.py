#!/usr/bin/env python3
"""Enforce classic HLASM fixed format: cols 1-71 statement, col 72 continuation."""
from __future__ import annotations

import re
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"


def pad72(s: str, cont: str = "X") -> str:
    if len(s) > 71:
        raise ValueError(f"segment longer than 71: {len(s)} {s!r}")
    return s.ljust(71) + cont


def wrap_star_comment(line: str) -> list[str]:
    body = line.rstrip()
    out: list[str] = []
    while len(body) > 71:
        chunk = body[:71]
        sp = chunk.rfind(" ")
        if sp < 2:
            sp = 71
        out.append(body[:sp].rstrip())
        rest = body[sp:].lstrip()
        body = ("* " + rest) if rest else ""
        if not rest:
            break
    if body:
        out.append(body[:71])
    return out


def fix_statement(line: str) -> list[str]:
    line = line.rstrip()
    if len(line) <= 71:
        return [line]

    m = re.match(r"^(\s+TITLE\s+)'(.*)'\s*$", line)
    if m:
        prefix, title = m.group(1), m.group(2)
        max_t = max(10, 71 - len(prefix) - 2)
        t = title if len(title) <= max_t else title[: max_t - 3] + "..."
        return [(prefix + "'" + t + "'")[:71]]

    # EQU / DS with trailing * comment
    m = re.match(r"^(.*?\S)(\s+\*\s+)(.*)$", line)
    if m and "*" in line and len(m.group(1).rstrip()) <= 71:
        stmt = m.group(1).rstrip()
        # don't treat continued operand * as comment
        if " *" in line or re.search(r"\s+\*", line):
            cmt = m.group(3).strip()
            return wrap_star_comment("* " + cmt) + [stmt[:71]]
    # statement then 2+ spaces then trailing remark (not * form)
    m = re.match(r"^(.+?)(\s{2,})(\S.*)$", line)
    if m:
        stmt = m.group(1).rstrip()
        cmt = m.group(3).strip()
        # only treat as remark if statement alone fits
        if len(stmt) <= 71 and not stmt.lstrip().startswith("*"):
            # avoid splitting operand lists that use spaces oddly
            if "," in stmt or re.search(
                r"\b(EQU|DS|DC|LR|L|LA|LT|LG|ST|STM|MVC|XC|TM|POST|WAIT|"
                r"BALR|CDS|CS|GETMAIN|FREEMAIN|ATTACH|IARV64|LLH|LRA|LTR|"
                r"JNZ|JZ|JO|JE|JNE|JNH|JNL|BCT|USING|ENTRY|EXTRN|CSECT|"
                r"AMODE|RMODE|PRINT|OPTABLE|COPY|END|DROP|CNOP|ORG|"
                r"MPMCQ_|SAM64|SAM31|MVCL|XR|CR|SR|AR|ALR|LAAL|LHI|LCR|"
                r"MACRO|MEND|AIF|ANOP|AGO|SETA|SETC|SETB)\b",
                stmt,
            ):
                return wrap_star_comment("* " + cmt) + [stmt[:71]]

    # Break after last comma in first 71 columns
    head = line[:71]
    idx = head.rfind(",")
    if idx >= 20 and not line.lstrip().startswith("*"):
        first = pad72(line[: idx + 1])
        cont = "               " + line[idx + 1 :].lstrip()
        return [first] + fix_statement(cont)

    # Last resort truncate
    return [line[:71]]


def process(path: Path) -> None:
    raw = path.read_text(encoding="utf-8", errors="replace").splitlines()
    out: list[str] = []
    for line in raw:
        line = line.replace("\t", " ").rstrip("\r\n")
        if line.startswith("*") or line.startswith(".*"):
            # .* is macro remark — keep under 71
            if line.startswith(".*"):
                out.extend(wrap_star_comment("*" + line[1:]) if False else [line[:71]])
                # better: wrap .* remarks
                body = line
                while len(body) > 71:
                    chunk = body[:71]
                    sp = max(chunk.rfind(" "), 2)
                    out.append(body[:sp].rstrip())
                    rest = body[sp:].lstrip()
                    body = (".* " + rest) if rest else ""
                if body:
                    out.append(body[:71])
            else:
                out.extend(wrap_star_comment(line))
        elif len(line) <= 71:
            out.append(line)
        else:
            out.extend(fix_statement(line))

    # Hard clamp any remaining >72
    final: list[str] = []
    for l in out:
        if len(l) > 72:
            final.append(l[:72])
        else:
            final.append(l)

    path.write_text("\n".join(final) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    for p in sorted(SRC.iterdir()):
        if p.suffix.lower() not in {".asm", ".mac", ".inc"}:
            continue
        process(p)
        long = [
            (i + 1, len(l), l)
            for i, l in enumerate(p.read_text(encoding="utf-8").splitlines())
            if len(l) > 71
        ]
        cont = sum(1 for _, n, _ in long if n == 72)
        print(f"{p.name}: >71={len(long)} (len72={cont})")
        for i, n, l in long:
            flag = l[71] if n >= 72 else " "
            print(f"  {i}:{n}:col72={flag!r}:{l}")


if __name__ == "__main__":
    main()
