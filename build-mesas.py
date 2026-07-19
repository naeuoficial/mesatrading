#!/usr/bin/env python3
"""
Embute dados/mesas-normalizado.json dentro de index.html.

Existe porque a página é um arquivo único, sem servidor e sem build:
um `fetch` de arquivo local falha em file:// e num artefato publicado.
Rode este script sempre que atualizar o levantamento das mesas.

    python3 build-mesas.py
"""
import json, re, sys, pathlib

RAIZ = pathlib.Path(__file__).parent
FONTE = RAIZ / "dados" / "mesas-normalizado.json"
ALVO = RAIZ / "index.html"

INI = "/* <<<MESAS-DADOS>>> */"
FIM = "/* <<<FIM-MESAS-DADOS>>> */"


def main() -> int:
    if not FONTE.exists():
        print(f"erro: {FONTE} não encontrado", file=sys.stderr)
        return 1

    d = json.loads(FONTE.read_text(encoding="utf-8"))
    firmas, alertas, meta = d["firmas"], d["alertas"], d["meta"]

    j = lambda o: json.dumps(o, ensure_ascii=False, separators=(",", ":"))
    bloco = "\n".join([
        INI,
        "/* Gerado por build-mesas.py a partir de dados/mesas-normalizado.json.",
        "   Não edite à mão: altere o JSON e rode o script de novo. */",
        f"const MS_META={j(meta)};",
        f"const MESAS={j(firmas)};",
        f"const ALERTAS={j(alertas)};",
        FIM,
    ])

    html = ALVO.read_text(encoding="utf-8")

    if INI in html:
        html = re.sub(re.escape(INI) + r".*?" + re.escape(FIM), lambda _: bloco,
                      html, flags=re.S)
        acao = "substituído"
    else:
        marca = "/* ═══════════════ VARREDURA DE MESAS PROPRIETÁRIAS"
        if marca not in html:
            print("erro: bloco da varredura não encontrado em index.html", file=sys.stderr)
            return 1
        html = html.replace(marca, f"{bloco}\n\n{marca}", 1)
        acao = "inserido"

    ALVO.write_text(html, encoding="utf-8")
    kb = len(bloco.encode()) / 1024
    print(f"{acao}: {len(firmas)} mesas, {len(alertas)} alertas ({kb:.1f} kB)")
    print(f"levantamento de {meta.get('gerado')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
