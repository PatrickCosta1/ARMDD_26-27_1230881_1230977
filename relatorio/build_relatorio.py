"""Monta o relatório da 1.ª parte: expande os @@include, converte Markdown em HTML
e imprime o PDF com o Edge/Chrome em modo headless.

Uso:  python -I build_relatorio.py [--sem-pdf]
Saída: relatorio/relatorio_parte1.html e relatorio/relatorio_parte1.pdf
Sem dependências externas; o navegador é procurado nos caminhos habituais do Windows
ou na variável de ambiente BROWSER.
"""
import base64
import html
import mimetypes
import os
import re
import subprocess
import sys
import tempfile

AQUI = os.path.dirname(os.path.abspath(__file__))
FONTE = os.path.join(AQUI, "relatorio_parte1.md")
SAIDA_HTML = os.path.join(AQUI, "relatorio_parte1.html")
SAIDA_PDF = os.path.join(AQUI, "relatorio_parte1.pdf")
ALUNOS = "1230881 · 1230977"

NAVEGADORES = [
    os.environ.get("BROWSER", ""),
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
]


# ------------------------------------------------------------------ includes
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
        saida.extend(extrair(ler(caminho), opcoes))
    return "\n".join(saida)


def extrair(texto, op):
    linhas = texto.split("\n")
    # remove o título H1 e os blocos ">" iniciais (metadados do repositório)
    i = 0
    while i < len(linhas) and (not linhas[i].strip() or linhas[i].startswith("# ") or linhas[i].startswith(">")):
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
                omitir = l.strip() == "```mermaid"   # o diagrama é inserido como imagem
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


# ---------------------------------------------------------------- markdown
def inline(t):
    t = html.escape(t, quote=False)
    cods = []

    def guarda(m):
        cods.append(m.group(1))
        return "\x00%d\x00" % (len(cods) - 1)

    t = re.sub(r"`([^`]+)`", guarda, t)
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1", t)          # ligações relativas: só o texto
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*([^*\s][^*]*?)\*(?![\w*])", r"<em>\1</em>", t)
    t = re.sub(r"\x00(\d+)\x00", lambda m: "<code>%s</code>" % cods[int(m.group(1))].replace("\\|", "|"), t)
    return t


def imagem(alt, src, base):
    caminho = os.path.normpath(os.path.join(base, src))
    tipo = mimetypes.guess_type(caminho)[0] or "image/png"
    if caminho.endswith(".svg"):
        tipo = "image/svg+xml"
    with open(caminho, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    return '<figure><img alt="%s" src="data:%s;base64,%s"><figcaption>%s</figcaption></figure>' % (
        html.escape(alt), tipo, b64, html.escape(alt))


def celulas(linha):
    linha = linha.strip()
    if linha.startswith("|"):
        linha = linha[1:]
    if linha.endswith("|") and not linha.endswith("\\|"):
        linha = linha[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", linha)]


def converter(md, base):
    linhas = md.split("\n")
    out, num, em_anexo = [], [0, 0, 0], False
    i = 0
    while i < len(linhas):
        l = linhas[i]
        if l.startswith("```"):
            j = i + 1
            while j < len(linhas) and not linhas[j].startswith("```"):
                j += 1
            out.append("<pre>%s</pre>" % html.escape("\n".join(linhas[i + 1:j])))
            i = j + 1
            continue
        m = eh_titulo(l)
        if m:
            nivel = len(m.group(1))
            texto = re.sub(r"^\d+(\.\d+)*\.?\s+", "", l[nivel + 1:]).strip()
            if nivel == 1 and texto.startswith("Anexo"):
                em_anexo, rotulo = True, ""
                out.append('<h1 class="anexo">%s</h1>' % inline(texto))
            else:
                rotulo = ""
                if not em_anexo and nivel <= 3:
                    num[nivel - 1] += 1
                    for k in range(nivel, 3):
                        num[k] = 0
                    rotulo = ".".join(str(n) for n in num[:nivel]) + " "
                out.append("<h%d>%s%s</h%d>" % (nivel, rotulo, inline(texto), nivel))
            i += 1
            continue
        mi = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)\s*$", l)
        if mi:
            out.append(imagem(mi.group(1), mi.group(2), base))
            i += 1
            continue
        if l.startswith("|") and i + 1 < len(linhas) and re.match(r"^\|[\s:|-]+\|?\s*$", linhas[i + 1]):
            cab = celulas(l)
            j = i + 2
            corpo = []
            while j < len(linhas) and linhas[j].startswith("|"):
                corpo.append(celulas(linhas[j]))
                j += 1
            classe = ' class="num"' if cab[0] in ("#", "Nº") else ""
            t = ["<table%s><thead><tr>%s</tr></thead><tbody>" % (classe, "".join("<th>%s</th>" % inline(c) for c in cab))]
            for r in corpo:
                t.append("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in r))
            t.append("</tbody></table>")
            out.append("".join(t))
            i = j
            continue
        ml = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", l)
        if ml:
            ordenada = ml.group(2)[0].isdigit()
            itens = []
            while i < len(linhas):
                mm = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)$", linhas[i])
                if mm:
                    itens.append("<li class=\"n%d\">%s</li>" % (min(len(mm.group(1)) // 2, 2), inline(mm.group(3))))
                    i += 1
                elif linhas[i].startswith("  ") and linhas[i].strip():
                    itens[-1] = itens[-1][:-5] + " " + inline(linhas[i].strip()) + "</li>"
                    i += 1
                else:
                    break
            tag = "ol" if ordenada else "ul"
            out.append("<%s>%s</%s>" % (tag, "".join(itens), tag))
            continue
        if l.startswith(">"):
            blocos = []
            while i < len(linhas) and linhas[i].startswith(">"):
                blocos.append(linhas[i].lstrip("> "))
                i += 1
            out.append("<blockquote>%s</blockquote>" % inline(" ".join(blocos)))
            continue
        if not l.strip():
            i += 1
            continue
        par = [l]
        i += 1
        while i < len(linhas) and linhas[i].strip() and not re.match(r"^(#|\||```|>|\s*([-*]|\d+\.)\s|!\[)", linhas[i]):
            par.append(linhas[i])
            i += 1
        out.append("<p>%s</p>" % inline(" ".join(par)))
    return "\n".join(out)


CSS = """
@page { size: A4; margin: 18mm 15mm 18mm 15mm; }
body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 10pt; line-height: 1.42; color: #1c1c1c; }
h1 { font-size: 17pt; margin: 22pt 0 8pt; padding-bottom: 3pt; border-bottom: 2px solid #2c6fa8; color: #17426b; page-break-before: always; }
h1:first-of-type { page-break-before: avoid; }
h1.anexo { color: #444; border-color: #888; }
h2 { font-size: 13pt; margin: 15pt 0 5pt; color: #17426b; }
h3 { font-size: 11pt; margin: 11pt 0 4pt; color: #2a2a2a; }
h1, h2, h3 { page-break-after: avoid; }
p { margin: 5pt 0; text-align: justify; }
code { font-family: Consolas, 'Courier New', monospace; font-size: 8.6pt; background: #f1f3f5; padding: 0 2px; border-radius: 2px; word-break: break-word; }
pre { background: #f1f3f5; padding: 6pt; font-size: 8pt; white-space: pre-wrap; }
table { border-collapse: collapse; width: 100%; margin: 7pt 0; font-size: 8.4pt; }
th, td { border: 1px solid #b9c0c7; padding: 2.5pt 4pt; vertical-align: top; text-align: left; word-break: break-word; }
th { background: #e6edf4; }
table.num td:first-child, table.num th:first-child { white-space: nowrap; }
tr { page-break-inside: avoid; }
thead { display: table-header-group; }
ul, ol { margin: 4pt 0 4pt 16pt; padding: 0; }
li { margin: 2pt 0; }
ul.sem-marca { list-style: none; margin-left: 4pt; }
li.n1 { margin-left: 14pt; } li.n2 { margin-left: 28pt; }
blockquote { margin: 6pt 0; padding: 2pt 9pt; border-left: 3px solid #b9c0c7; color: #444; }
figure { margin: 9pt 0; text-align: center; page-break-inside: avoid; }
figure img { max-width: 100%; max-height: 215mm; }
figcaption { font-size: 8.5pt; color: #555; margin-top: 3pt; }
.capa { height: 235mm; display: flex; flex-direction: column; justify-content: center; text-align: center; }
.capa .inst { font-size: 12pt; color: #444; }
.capa h1 { border: none; font-size: 26pt; margin: 22pt 0 8pt; page-break-before: avoid; }
.capa .sub { font-size: 14pt; color: #2c6fa8; }
.capa .meta { margin-top: 44pt; font-size: 11pt; color: #333; line-height: 1.8; }
.indice { page-break-after: always; }
.indice h1 { page-break-before: avoid; }
"""


def capa():
    return (
        '<section class="capa"><div class="inst">Mestrado em Engenharia Informática<br>Armazéns de Dados · 1.º Semestre 2026-2027</div>'
        '<h1>Data Mart de Vendas da More Rhythm, SA</h1><div class="sub">Trabalho Prático — 1.ª parte: arquitetura, modelo dimensional, '
        'Staging Area e mapeamentos</div>'
        '<div class="meta">Grupo: alunos n.º %s<br>Entrega: 15 de novembro de 2026</div></section>' % ALUNOS
    )


def indice(corpo):
    itens = re.findall(r"<h1(?: class=\"anexo\")?>(.*?)</h1>", corpo)
    return '<section class="indice"><h1 class="anexo">Índice</h1><ul class="sem-marca">%s</ul></section>' % "".join(
        "<li>%s</li>" % t for t in itens)


def montar():
    md = expandir(ler(FONTE), AQUI)
    corpo = converter(md, AQUI)
    doc = '<!DOCTYPE html><html lang="pt"><head><meta charset="utf-8"><title>Data Mart de Vendas — More Rhythm</title><style>%s</style></head><body>%s%s%s</body></html>' % (
        CSS, capa(), indice(corpo), corpo)
    with open(SAIDA_HTML, "w", encoding="utf-8") as f:
        f.write(doc)
    print("HTML:", SAIDA_HTML)


def imprimir_pdf():
    nav = next((n for n in NAVEGADORES if n and os.path.exists(n)), None)
    if not nav:
        sys.exit("Navegador não encontrado; defina BROWSER ou abra o HTML e imprima para PDF.")
    with tempfile.TemporaryDirectory() as perfil:
        subprocess.run([nav, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--user-data-dir=" + perfil,
                        "--print-to-pdf=" + SAIDA_PDF, "file:///" + SAIDA_HTML.replace("\\", "/")],
                       check=True, capture_output=True, timeout=180)
    print("PDF:", SAIDA_PDF)


if __name__ == "__main__":
    montar()
    if "--sem-pdf" not in sys.argv:
        imprimir_pdf()
