"""Converte o relatório em Markdown (com @@include) para LaTeX, sem Pandoc.

Uso (a partir de relatorio/latex):
    python -I md2tex.py [--repo CAMINHO_DO_REPO] [--saida PASTA] [--zip]

--repo   pasta que contem relatorio/, modelo-dimensional/ e mappings/
         (por omissao, a raiz do repositorio, dois niveis acima deste script)
--saida  pasta de saida (por omissao "saida"): conteudo.tex, main.tex e figuras/
--zip    cria tambem overleaf_projeto.zip com o conteudo de saida, pronto a carregar no Overleaf

Gera conteudo.tex (corpo do relatório), copia main.tex (modelo) e converte as
figuras: SVG -> PDF vetorial com o Edge/Chrome em modo headless; PNG copiam-se.
A pasta de saida pode ser carregada como projeto no Overleaf (compilador pdfLaTeX).
Sem dependencias externas.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

AQUI = os.path.dirname(os.path.abspath(__file__))

NAVEGADORES = [
    os.environ.get("BROWSER", ""),
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
]


# ------------------------------------------------------------ expansao de @@include
def ler(caminho):
    with open(caminho, encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def eh_titulo(linha):
    return re.match(r"^(#{1,6}) ", linha)


def expandir(texto, base):
    saida = []
    for linha in texto.split("\n"):
        m = re.match(r"^@@include (\S+)(.*)$", linha)
        if not m:
            saida.append(linha)
            continue
        caminho = os.path.normpath(os.path.join(base, m.group(1)))
        opcoes = dict(re.findall(r'(\w+)=("[^"]*"|\S+)', m.group(2)))
        opcoes = {k: v.strip('"') for k, v in opcoes.items()}
        incluido = "\n".join(extrair(ler(caminho), opcoes))
        saida.extend(expandir(incluido, os.path.dirname(caminho)).split("\n"))
    return "\n".join(saida)


def extrair(texto, op):
    linhas = texto.split("\n")
    i = 0
    while i < len(linhas) and (not linhas[i].strip() or (linhas[i].startswith("# ") and not linhas[i].startswith("# Anexo"))
                               or linhas[i].startswith(">")):
        i += 1
    linhas = linhas[i:]
    ini, fim = op.get("from"), op.get("to")
    if ini:
        idx = next(k for k, l in enumerate(linhas) if l.startswith(ini))
        linhas = linhas[idx:]
    if fim:
        idx = next(k for k, l in enumerate(linhas) if k > 0 and l.startswith(fim))
        linhas = linhas[:idx]
    if op.get("drop_heading") and linhas and eh_titulo(linhas[0]):
        linhas = linhas[1:]
    desloc = int(op.get("shift", "0"))
    res, em_codigo, omitir = [], False, False
    for l in linhas:
        if l.startswith("```"):
            if em_codigo:
                em_codigo = False
                if omitir:
                    omitir = False
                    continue
            else:
                em_codigo = True
                omitir = l.strip() == "```mermaid"
            if omitir:
                continue
        elif omitir:
            continue
        if not em_codigo:
            m = eh_titulo(l)
            if m:
                nivel = min(max(len(m.group(1)) + desloc, 1), 6)
                l = "#" * nivel + " " + l[len(m.group(1)) + 1:]
        res.append(l)
    return res + [""]


# ------------------------------------------------------------------- escape LaTeX
# Caracteres Unicode fora do Latin-1 que aparecem nos documentos
UNICODE = {
    "\u2014": "---", "\u2013": "--", "\u2192": r"\ensuremath{\rightarrow}", "\u2190": r"\ensuremath{\leftarrow}",
    "\u21d4": r"\ensuremath{\Leftrightarrow}", "\u2260": r"\ensuremath{\neq}", "\u2265": r"\ensuremath{\geq}",
    "\u2264": r"\ensuremath{\leq}", "\u2208": r"\ensuremath{\in}", "\u03a3": r"\ensuremath{\Sigma}",
    "\u00d7": r"\ensuremath{\times}", "\u2212": r"\textminus{}", "\u00b7": r"\textperiodcentered{}",
    "\u00a7": r"\S{}", "\u00aa": r"\textordfeminine{}", "\u00ba": r"\textordmasculine{}",
    "\u00ab": r"\guillemotleft{}", "\u00bb": r"\guillemotright{}", "\u2026": r"\dots{}",
    "\u201c": r"\textquotedblleft{}", "\u201d": r"\textquotedblright{}", "\u20ac": r"\texteuro{}",
    "\u00a3": r"\pounds{}", "\u00a0": "~",
}
ESPECIAIS = {
    "\\": r"\textbackslash{}", "{": r"\{", "}": r"\}", "&": r"\&", "%": r"\%", "$": r"\$", "#": r"\#",
    "_": r"\_", "^": r"\textasciicircum{}", "~": r"\textasciitilde{}",
}


def esc(t, codigo=False):
    saida = []
    for c in t:
        if c in ESPECIAIS:
            saida.append(ESPECIAIS[c])
            if c == "_":
                saida.append(r"\allowbreak{}")
        elif c in UNICODE:
            saida.append(UNICODE[c])
        elif c == '"':
            saida.append(r"\textquotedbl{}")
        elif c == "<":
            saida.append(r"\textless{}")
        elif c == ">":
            saida.append(r"\textgreater{}")
        elif c == "|":
            saida.append(r"\textbar{}")
        elif codigo and c in "./,=":
            saida.append(c + r"\allowbreak{}")
        else:
            saida.append(c)
    return "".join(saida)


SIMBOLO_PDF = {"rightarrow": "->", "leftarrow": "<-", "Leftrightarrow": "<->", "neq": "!=", "geq": ">=", "leq": "<=",
               "in": "em", "Sigma": "soma", "times": "x"}


def para_titulo(t):
    """Nos titulos, os simbolos matematicos levam \\texorpdfstring para os marcadores do PDF."""
    return re.sub(r"\\ensuremath\{\\(\w+)\}",
                  lambda m: r"\texorpdfstring{\ensuremath{\%s}}{%s}" % (m.group(1), SIMBOLO_PDF.get(m.group(1), "")), t)


def aspas(t):
    """Aspas retas "x" -> aspas tipograficas, antes do escape."""
    return re.sub(r'"([^"\n]+)"', "\u201c\\1\u201d", t)


def inline(t):
    codigos = []

    def guarda(m):
        codigos.append(r"\texttt{" + esc(m.group(1), codigo=True) + "}")
        return "\x00%d\x00" % (len(codigos) - 1)

    t = re.sub(r"`([^`]+)`", guarda, t)
    t = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", t)
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", t)       # ligacoes: so o texto
    t = aspas(t)
    t = esc(t)
    t = re.sub(r"\*\*(.+?)\*\*", r"\\textbf{\1}", t)
    t = re.sub(r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])", r"\\emph{\1}", t)
    t = re.sub(r"\x00(\d+)\x00", lambda m: codigos[int(m.group(1))], t)
    return t


# ----------------------------------------------------------------------- figuras
def navegador():
    return next((n for n in NAVEGADORES if n and os.path.exists(n)), None)


def dimensoes_svg(texto):
    m = re.search(r'viewBox="\s*[\d.]+\s+[\d.]+\s+([\d.]+)\s+([\d.]+)', texto)
    if not m:
        raise SystemExit("SVG sem viewBox")
    return float(m.group(1)), float(m.group(2))


def svg_para_pdf(svg, pdf):
    nav = navegador()
    if not nav:
        raise SystemExit("Navegador (Edge/Chrome) nao encontrado; defina BROWSER.")
    conteudo = ler(svg)
    w, h = dimensoes_svg(conteudo)
    html = ('<!DOCTYPE html><html><head><meta charset="utf-8"><style>'
            '@page{size:%.0fpx %.0fpx;margin:0}html,body{margin:0;padding:0;overflow:hidden;width:%.0fpx;height:%.0fpx}'
            'svg{display:block;width:%.0fpx;height:%.0fpx}</style></head><body>%s</body></html>') % (w, h, w, h, w, h, conteudo)
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        h_path = os.path.join(tmp, "f.html")
        with open(h_path, "w", encoding="utf-8") as f:
            f.write(html)
        r = subprocess.run([nav, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--user-data-dir=" + os.path.join(tmp, "p"),
                            "--print-to-pdf=" + pdf, "file:///" + h_path.replace("\\", "/")],
                           capture_output=True, timeout=120)
        # esperar que o PDF exista antes de apagar o perfil temporario do navegador
        for _ in range(40):
            if os.path.exists(pdf) and os.path.getsize(pdf) > 0:
                break
            time.sleep(0.5)
        if not os.path.exists(pdf):
            raise SystemExit("O navegador nao gerou %s (codigo %s): %s" % (pdf, r.returncode, r.stderr.decode(errors="replace")[:400]))
    # o navegador escreve o PDF de forma assincrona: esperar que exista e que o tamanho estabilize
    anterior, estavel = -1, 0
    for _ in range(60):
        tamanho = os.path.getsize(pdf) if os.path.exists(pdf) else -1
        if tamanho > 0 and tamanho == anterior:
            estavel += 1
            if estavel >= 3:
                break
        else:
            estavel = 0
        anterior = tamanho
        time.sleep(0.5)
    if not os.path.exists(pdf) or os.path.getsize(pdf) == 0:
        raise SystemExit("O navegador nao gerou " + pdf)
    with open(pdf, "rb") as f:
        paginas = len(re.findall(rb"/Type\s*/Page[^s]", f.read()))
    return paginas


def preparar_figura(src, base, pasta_fig):
    caminho = os.path.normpath(os.path.join(base, src))
    nome, ext = os.path.splitext(os.path.basename(caminho))
    os.makedirs(pasta_fig, exist_ok=True)
    if ext.lower() == ".svg":
        destino = os.path.join(pasta_fig, nome + ".pdf")
        paginas = svg_para_pdf(caminho, destino)
        if paginas != 1:
            print("AVISO: %s gerou %d paginas (esperava 1)" % (destino, paginas), file=sys.stderr)
        return "figuras/" + nome
    destino = os.path.join(pasta_fig, nome + ext.lower())
    shutil.copyfile(caminho, destino)
    return "figuras/" + nome


# ------------------------------------------------------------------------ tabelas
def celulas(linha):
    linha = linha.strip()
    if linha.startswith("|"):
        linha = linha[1:]
    if linha.endswith("|") and not linha.endswith("\\|"):
        linha = linha[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", linha)]


LARGURA_TEXTO = 461.0     # pt: A4 (21 cm) menos 2 x 2,4 cm de margem


def pedacos(texto):
    """Comprimentos dos pedacos que nao se podem partir: palavras e, nos codigos, segmentos entre _ . / , = ("""
    res = []
    for palavra in re.split(r"\s+", texto):
        for pedaco in re.split(r"(?<=[_./,=(])", palavra):
            res.append(len(pedaco))
    return res


def larguras(cab, corpo):
    """Devolve (fracoes da largura, tamanho da letra). Cada coluna tem pelo menos a largura do seu
    pedaco mais comprido; o que sobra reparte-se pelo peso do conteudo."""
    n = len(cab)
    comp = []
    maior = []
    for j in range(n):
        textos = [re.sub(r"[`*]", "", cab[j])] + [re.sub(r"[`*]", "", r[j]) for r in corpo]
        mx = max(len(t) for t in textos)
        med = sum(len(t) for t in textos) / len(textos)
        comp.append(max(4.0, min(mx, 70) * 0.35 + min(med, 70) * 0.65))
        maior.append(min(24, max(max(pedacos(t), default=0) for t in textos)))
    for tam, unidade in (("footnotesize", 5.4), ("scriptsize", 4.7)):
        minimos = [(m * unidade + 8.0) / LARGURA_TEXTO for m in maior]
        if sum(minimos) <= 0.97:
            break
    sobra = max(0.0, 0.995 - sum(minimos))
    total = sum(comp)
    fr = [m + sobra * c / total for m, c in zip(minimos, comp)]
    if sum(fr) > 0.9951:
        fr = [f / sum(fr) * 0.995 for f in fr]
        print("AVISO: tabela com %d colunas demasiado larga para a pagina (%s)" % (n, cab[0][:30]), file=sys.stderr)
    return fr, tam


def tabela_latex(linhas):
    cab = celulas(linhas[0])
    corpo = [celulas(l) for l in linhas[2:]]
    n = len(cab)
    corpo = [(r + [""] * n)[:n] for r in corpo]
    fr, tam = larguras(cab, corpo)
    cols = "".join(r">{\raggedright\arraybackslash}p{\dimexpr %.4f\linewidth-6pt\relax}" % f for f in fr)

    def linha(cs, negrito=False):
        pecas = []
        for c in cs:
            t = inline(c)
            if negrito and t:
                t = r"\textbf{" + t + "}"
            pecas.append("{}" + t)         # {} evita que um "[" inicial seja lido como argumento opcional
        return " & ".join(pecas) + r" \\ \hline"

    s = ["{\\" + tam + r"\setlength{\tabcolsep}{3pt}\renewcommand{\arraystretch}{1.15}",
         r"\begin{longtable}{" + cols + "}",
         r"\hline", linha(cab, True), r"\endfirsthead",
         r"\hline", linha(cab, True), r"\endhead"]
    s += [linha(r) for r in corpo]
    s += [r"\end{longtable}}", ""]
    return "\n".join(s)


# --------------------------------------------------------------------- documento
def converter(md, base, pasta_fig):
    linhas = md.split("\n")
    out, i = [], 0
    em_anexo = False
    figura_n = 0
    while i < len(linhas):
        l = linhas[i]
        if l.startswith("```"):
            j = i + 1
            while j < len(linhas) and not linhas[j].startswith("```"):
                j += 1
            out.append(r"\begin{Verbatim}[breaklines=true,fontsize=\footnotesize]")
            out.extend(linhas[i + 1:j])
            out.append(r"\end{Verbatim}")
            i = j + 1
            continue
        m = eh_titulo(l)
        if m:
            nivel = len(m.group(1))
            texto = l[nivel + 1:].strip()
            texto = re.sub(r"^(?:[A-Z]\.)?\d+(?:\.\d+)*\.?\s+", "", texto)   # numeracao propria do LaTeX
            if nivel == 1 and texto.startswith("Anexo"):
                texto = re.sub(r"^Anexo\s+[A-Z]\s*[\u2014\u2013-]\s*", "", texto)
                if not em_anexo:
                    out.append(r"\appendix")
                    out.append(r"\titleformat{\section}{\Large\bfseries\color{azul}}{Anexo~\thesection}{0.6em}{}[\titlerule]")
                    em_anexo = True
            cmd = {1: r"\section", 2: r"\subsection", 3: r"\subsubsection", 4: r"\paragraph"}.get(nivel, r"\subparagraph")
            out.append(cmd + "{" + para_titulo(inline(texto)) + "}")
            out.append("")
            i += 1
            continue
        mi = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)\s*$", l)
        if mi:
            figura_n += 1
            ficheiro = preparar_figura(mi.group(2), base, pasta_fig)
            out += [r"\begin{figure}[htbp]", r"\centering",
                    r"\includegraphics[width=\linewidth,height=0.78\textheight,keepaspectratio]{" + ficheiro + "}",
                    r"\caption{" + inline(mi.group(1)) + "}", r"\end{figure}", ""]
            i += 1
            continue
        if l.startswith("|") and i + 1 < len(linhas) and re.match(r"^\|[\s:|-]+\|?\s*$", linhas[i + 1]):
            j = i
            bloco = []
            while j < len(linhas) and linhas[j].startswith("|"):
                bloco.append(linhas[j])
                j += 1
            out.append(tabela_latex(bloco))
            i = j
            continue
        ml = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", l)
        if ml:
            itens = []
            while i < len(linhas):
                mm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", linhas[i])
                if mm:
                    itens.append([len(mm.group(1)) // 2, mm.group(2)[0].isdigit(), mm.group(3)])
                    i += 1
                elif linhas[i].startswith("  ") and linhas[i].strip() and itens:
                    itens[-1][2] += " " + linhas[i].strip()
                    i += 1
                else:
                    break
            out.extend(lista_latex(itens))
            continue
        if l.startswith(">"):
            blocos = []
            while i < len(linhas) and linhas[i].startswith(">"):
                blocos.append(linhas[i].lstrip("> "))
                i += 1
            out += [r"\begin{quote}", inline(" ".join(blocos)), r"\end{quote}", ""]
            continue
        if not l.strip() or re.match(r"^-{3,}\s*$", l):
            i += 1
            continue
        par = [l]
        i += 1
        while i < len(linhas) and linhas[i].strip() and not re.match(r"^(#|\||```|>|\s*([-*]|\d+\.)\s|!\[)", linhas[i]):
            par.append(linhas[i])
            i += 1
        out += [inline(" ".join(par)), ""]
    return "\n".join(out)


def lista_latex(itens):
    """Listas aninhadas por indentacao (2 espacos por nivel)."""
    out, pilha = [], []                      # pilha de (nivel, ambiente)
    for nivel, ordenada, texto in itens:
        amb = "enumerate" if ordenada else "itemize"
        while pilha and pilha[-1][0] > nivel:
            out.append(r"\end{" + pilha.pop()[1] + "}")
        if not pilha or pilha[-1][0] < nivel:
            pilha.append((nivel, amb))
            out.append(r"\begin{" + amb + "}")
        out.append(r"\item " + inline(texto))
    while pilha:
        out.append(r"\end{" + pilha.pop()[1] + "}")
    out.append("")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.normpath(os.path.join(AQUI, "..", "..")))
    ap.add_argument("--saida", default=os.path.join(AQUI, "saida"))
    ap.add_argument("--zip", action="store_true", help="criar overleaf_projeto.zip")
    a = ap.parse_args()
    fonte = os.path.join(a.repo, "relatorio", "relatorio_parte1.md")
    base = os.path.dirname(fonte)
    os.makedirs(a.saida, exist_ok=True)
    md = expandir(ler(fonte), base)
    tex = converter(md, base, os.path.join(a.saida, "figuras"))
    with open(os.path.join(a.saida, "conteudo.tex"), "w", encoding="utf-8", newline="\n") as f:
        f.write("% Gerado por md2tex.py a partir de relatorio_parte1.md (nao editar a mao: voltar a gerar)\n" + tex + "\n")
    shutil.copyfile(os.path.join(AQUI, "main.tex"), os.path.join(a.saida, "main.tex"))
    print("OK:", os.path.join(a.saida, "conteudo.tex"))
    if a.zip:
        import zipfile
        destino = os.path.join(os.path.dirname(os.path.abspath(a.saida)), "overleaf_projeto.zip")
        with zipfile.ZipFile(destino, "w", zipfile.ZIP_DEFLATED) as z:
            for nome in ("main.tex", "conteudo.tex"):
                z.write(os.path.join(a.saida, nome), nome)
            pasta_fig = os.path.join(a.saida, "figuras")
            for f in sorted(os.listdir(pasta_fig)):
                z.write(os.path.join(pasta_fig, f), "figuras/" + f)
        print("ZIP:", destino)


if __name__ == "__main__":
    main()
