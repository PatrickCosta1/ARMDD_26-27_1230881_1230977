# Relatório em LaTeX: como gerar e compilar (Overleaf)

O texto vive nos ficheiros Markdown do repositório (`relatorio/relatorio_parte1.md` e os que ele inclui com `@@include`).
**Não se edita o `.tex`**: edita-se o Markdown e volta-se a gerar. O conversor não precisa de Pandoc nem de LaTeX
instalados; a compilação faz-se no Overleaf.

## O que está nesta pasta

| Ficheiro | Função |
|---|---|
| `md2tex.py` | Converte o Markdown (com `@@include`) em `conteudo.tex`, converte os SVG em PDF vetorial (com o Edge ou o Chrome) e copia os PNG |
| `main.tex` | Modelo: capa, índice com páginas, numeração, cabeçalho e rodapé |
| `check_tex.py` | Verificação estrutural do `.tex` gerado (chaves, ambientes, caracteres sem escape, figuras em falta, colunas das tabelas) |

Os ficheiros gerados (`saida/` e `overleaf_projeto.zip`) não entram no git (ver `.gitignore`).

## Passos (cada vez que o texto mudar)

1. Atualizar o repositório (`git pull` na `main`) e entrar nesta pasta (`relatorio/latex`).

2. Gerar o `.tex` e o zip para o Overleaf (requer Python 3.10 ou superior e o Edge ou o Chrome instalados):

   ```bash
   python -I md2tex.py --zip
   ```

3. Verificar. Tem de terminar com `OK: sem erros estruturais`:

   ```bash
   python -I check_tex.py
   ```

4. Preencher a capa em `main.tex`: `\NomeA`, `\NomeB` e `\DataEntrega` (os números dos alunos já lá estão).
   Fazê-lo **antes** de gerar o zip, para ficar no projeto.

5. No Overleaf: *New Project → Upload Project* e escolher `overleaf_projeto.zip`. Em *Menu*, compilador **pdfLaTeX**,
   documento principal `main.tex`, e *Recompile*.

6. Descarregar o PDF e renomeá-lo `1230881_1230977.pdf`.

## Se a compilação der erro

Copiar a primeira mensagem de erro (a vermelho no registo) e a linha do `.tex` a que se refere. Corrige-se no conversor
(`md2tex.py`), não no `.tex`, e volta-se ao passo 2.

## Notas

- Se o Edge ou o Chrome não estiverem nos caminhos habituais do Windows, definir a variável de ambiente `BROWSER`
  com o caminho do executável.
- Os `@@include` aceitam `from="…"`, `to="…"`, `shift=N` e `drop_heading=1`, como no `build_relatorio.py`.
- Um ficheiro incluído que comece por `# Anexo X` mantém esse título e passa a ser um anexo do relatório.
- O PDF alternativo (sem LaTeX) gera-se com `relatorio/build_relatorio.py`.
