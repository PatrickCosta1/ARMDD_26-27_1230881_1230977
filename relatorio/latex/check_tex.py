"""Verificacoes estruturais do conteudo.tex gerado (nao substitui compilar no Overleaf).

Uso:  python -I check_tex.py [PASTA_DE_SAIDA]
Apanha: chaves desequilibradas, \\begin/\\end desemparelhados, caracteres especiais sem escape,
Unicode nao tratado, aspas retas, ficheiros de figuras em falta, numero errado de colunas
nas tabelas e titulos vazios.
"""
import os
import re
import sys

pasta = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "saida")
caminho = os.path.join(pasta, "conteudo.tex")
linhas = open(caminho, encoding="utf-8").read().split("\n")
erros, avisos = [], []


def sem_escapes(t):
    t = t.replace("\\\\", "")
    t = t.replace("\\{", "").replace("\\}", "")
    return t


# ---- 1. chaves e ambientes (fora de Verbatim)
em_verb, pilha, profundidade = False, [], 0
for n, l in enumerate(linhas, 1):
    if l.startswith(r"\begin{Verbatim}"):
        em_verb = True
        pilha.append(("Verbatim", n))
        continue
    if l.startswith(r"\end{Verbatim}"):
        em_verb = False
        if not pilha or pilha[-1][0] != "Verbatim":
            erros.append("linha %d: \\end{Verbatim} sem begin" % n)
        else:
            pilha.pop()
        continue
    if em_verb:
        continue
    t = sem_escapes(l)
    profundidade += t.count("{") - t.count("}")
    if profundidade < 0:
        erros.append("linha %d: '}' a mais: %s" % (n, l[:90]))
        profundidade = 0
    if not l.strip() and profundidade != 0:
        erros.append("linha %d: chaves por fechar no bloco anterior (profundidade %d)" % (n, profundidade))
        profundidade = 0
    for m in re.finditer(r"\\(begin|end)\{(\w+\*?)\}", l):
        if m.group(1) == "begin":
            pilha.append((m.group(2), n))
        else:
            if not pilha or pilha[-1][0] != m.group(2):
                erros.append("linha %d: \\end{%s} nao corresponde (topo: %s)" % (n, m.group(2), pilha[-1][0] if pilha else "vazio"))
            else:
                pilha.pop()
if pilha:
    erros.append("ambientes por fechar: %s" % pilha)

# ---- 2. caracteres problematicos (fora de Verbatim e de comentarios/figuras)
em_verb = False
nao_ascii = {}
for n, l in enumerate(linhas, 1):
    if l.startswith(r"\begin{Verbatim}"):
        em_verb = True
        continue
    if l.startswith(r"\end{Verbatim}"):
        em_verb = False
        continue
    if em_verb or l.startswith("%"):
        continue
    for c in l:
        if ord(c) > 127 and not (0xC0 <= ord(c) <= 0xFF):
            nao_ascii.setdefault(c, n)
    if '"' in l:
        erros.append("linha %d: aspas retas sem tratamento: %s" % (n, l[:80]))
    if "includegraphics" in l:
        continue
    t = l.replace("\\\\", "")
    if re.search(r"(?<!\\)[%#$]", t):
        erros.append("linha %d: %%, # ou $ sem escape: %s" % (n, l[:90]))
    if re.search(r"(?<!\\)_", t):
        erros.append("linha %d: '_' sem escape: %s" % (n, l[:90]))
    if re.search(r"(?<!\\)\^", t):
        erros.append("linha %d: '^' sem escape: %s" % (n, l[:90]))
for c, n in nao_ascii.items():
    erros.append("linha %d: caractere Unicode nao tratado U+%04X" % (n, ord(c)))

# ---- 3. tabelas: colunas por linha
i, tabelas = 0, 0
while i < len(linhas):
    if linhas[i].startswith(r"\begin{longtable}"):
        tabelas += 1
        ncols = len(re.findall(r"p\{\\dimexpr", linhas[i]))
        j = i + 1
        while not linhas[j].startswith(r"\end{longtable}"):
            l = linhas[j]
            if l.endswith(r"\\ \hline") and not l.startswith(r"\hline"):
                t = l.replace("\\&", "")
                if t.count("&") != ncols - 1:
                    erros.append("linha %d: tabela com %d colunas mas a linha tem %d celulas: %s" % (j + 1, ncols, t.count("&") + 1, l[:80]))
            j += 1
        i = j
    i += 1

# ---- 4. figuras
figs = 0
for n, l in enumerate(linhas, 1):
    m = re.search(r"\\includegraphics\[[^\]]*\]\{([^}]+)\}", l)
    if m:
        figs += 1
        base = os.path.join(pasta, m.group(1))
        if not any(os.path.exists(base + e) for e in (".pdf", ".png", ".jpg")):
            erros.append("linha %d: figura em falta: %s" % (n, m.group(1)))

# ---- 5. titulos
titulos = []
for n, l in enumerate(linhas, 1):
    m = re.match(r"\\(section|subsection|subsubsection|paragraph)\{(.*)\}\s*$", l)
    if m:
        titulos.append((m.group(1), m.group(2)))
        if not m.group(2).strip():
            erros.append("linha %d: titulo vazio" % n)

secoes = [t for k, t in titulos if k == "section"]
print("linhas: %d | secoes: %d | subsecoes: %d | tabelas: %d | figuras: %d" % (
    len(linhas), len(secoes), sum(1 for k, _ in titulos if k == "subsection"), tabelas, figs))
print("secoes:", " | ".join(re.sub(r"\\[a-zA-Z]+\{?|\}|\{", "", s) for s in secoes))
if avisos:
    print("AVISOS:", *avisos, sep="\n  ")
if erros:
    print("ERROS (%d):" % len(erros))
    for e in erros[:40]:
        print("  -", e)
    sys.exit(1)
print("OK: sem erros estruturais")
