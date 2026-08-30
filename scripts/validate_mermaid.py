#!/usr/bin/env python3
"""Valida bloques Mermaid de un archivo o carpeta contra el parser oficial de Mermaid.

Extrae todo bloque ```mermaid de archivos .md y valida también archivos .mmd sueltos.
Usa mermaid + jsdom bajo Node (sin navegador). Instala las dependencias en una caché local
la primera vez. Sale con código 0 si todo es válido, 1 si hay al menos un error.

Uso:
    python scripts/validate_mermaid.py <archivo.md | archivo.mmd | carpeta>
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

CACHE = Path.home() / ".cache" / "ai-dlc-mermaid"
FENCE = re.compile(r"^```mermaid[ \t]*\n(.*?)^```", re.S | re.M)


def collect(target: Path):
    blocks = []
    if target.is_dir():
        files = sorted([*target.rglob("*.md"), *target.rglob("*.mmd")])
    else:
        files = [target]
    for f in files:
        text = f.read_text(encoding="utf-8")
        if f.suffix == ".mmd":
            blocks.append((str(f), text))
        else:
            for i, m in enumerate(FENCE.findall(text)):
                blocks.append((f"{f}#mermaid[{i}]", m))
    return blocks


def ensure_deps() -> bool:
    node_modules = CACHE / "node_modules" / "mermaid"
    if node_modules.exists():
        return True
    CACHE.mkdir(parents=True, exist_ok=True)
    print("Instalando mermaid + jsdom (una sola vez)...", file=sys.stderr)
    r = subprocess.run(
        ["npm", "install", "mermaid", "jsdom", "--no-audit", "--no-fund", "--prefix", str(CACHE)],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        print(r.stderr[-800:], file=sys.stderr)
    return node_modules.exists()


NODE_SRC = r"""
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!DOCTYPE html><body></body>', { pretendToBeVisual: true });
global.window = dom.window; global.document = dom.window.document;
import fs from 'fs';
const mermaid = (await import('mermaid')).default;
mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' });
const items = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const results = [];
for (const it of items) {
  try { await mermaid.parse(it.text); results.push({ label: it.label, ok: true }); }
  catch (e) { results.push({ label: it.label, ok: false, err: String(e.message || e).split('\n')[0] }); }
}
fs.writeFileSync(process.argv[3], JSON.stringify(results));
"""


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    target = Path(sys.argv[1]).expanduser()
    if not target.exists():
        print(f"No existe: {target}", file=sys.stderr)
        return 2
    blocks = collect(target)
    if not blocks:
        print("No se encontraron bloques Mermaid.")
        return 0
    if not ensure_deps():
        print("No se pudieron instalar las dependencias (mermaid/jsdom).", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory():
        (CACHE / "val.mjs").write_text(NODE_SRC, encoding="utf-8")
        items = [{"label": lbl, "text": txt} for lbl, txt in blocks]
        inp = CACHE / "_in.json"
        outp = CACHE / "_out.json"
        inp.write_text(json.dumps(items), encoding="utf-8")
        r = subprocess.run(["node", str(CACHE / "val.mjs"), str(inp), str(outp)],
                           capture_output=True, text=True, cwd=str(CACHE))
        if r.returncode != 0:
            print(r.stderr[-800:], file=sys.stderr)
            return 2
        results = json.loads(outp.read_text(encoding="utf-8"))

    ok = sum(1 for x in results if x["ok"])
    bad = len(results) - ok
    for x in results:
        print(("OK   " if x["ok"] else "FAIL ") + x["label"] + ("" if x["ok"] else " :: " + x.get("err", "")))
    print(f"\n== {ok} ok / {bad} fail ==")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
