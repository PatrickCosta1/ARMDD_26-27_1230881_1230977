# 01 — Matriz de Requisitos Analíticos

> Responsável: Leonor (A) · Fase 1 · Base: enunciado "Trabalho Prático" (ARMD 2026-27) e BD `MoreRhythm`

## 1. Medidas base (todas ao nível da linha de fatura)

| Medida | Definição | Aditiva? | Origem |
|---|---|---|---|
| **Quantidade** | Unidades vendidas | Sim | `invoices_lines.quantity` |
| **Valor líquido** | Venda sem IVA e sem frete | Sim | `invoices_lines.line_total` |
| **Valor IVA** | IVA da linha | Sim | `invoices_lines.line_vat` |
| **Frete alocado** | Custo de expedição da fatura repartido pelas linhas | Sim | `invoices.shipping_cost` (alocado, ver §4) |
| Preço unitário | Preço de venda da linha | Não (só média) | `invoices_lines.unit_price` |

**Medidas derivadas** (calculadas, não guardadas):

| Medida derivada | Fórmula |
|---|---|
| Vendas com IVA (produtos) | Valor líquido + Valor IVA |
| Vendas sem IVA com frete | Valor líquido + Frete alocado |
| Total faturado | Valor líquido + Frete alocado + Valor IVA (reconcilia com `invoices.final_total`) |
| Nº de faturas | `DISTINCT COUNT` de `numero_fatura` |

> **Confirmar com o Patrick / docente:** no enunciado, "com IVA" é lido como `líquido + IVA` e o frete só entra quando é pedido explicitamente (análises 2 e 9). Na BD, o IVA incide só sobre os produtos, não sobre o frete.

## 2. Matriz das 10 análises do enunciado

Legenda: **DD** = drill down · **RU** = roll up · Todas as análises incluem a dimensão **Data**.

| # | Medidas | Filtros | Agrupar por | Hierarquias / operações | Dimensões |
|---|---|---|---|---|---|
| 1 | Vendas com IVA | Semestre = 1, Ano = 2025 | Zona (cliente), Categoria | Data: Ano > Semestre · Geografia cliente: Zona · Produto: Categoria | Data, Cliente, Produto |
| 2 | Frete alocado | Mês = fev/2025 | Cidade (cliente), Família | Geografia cliente: Cidade · Produto: Família | Data, Cliente, Produto |
| 3 | Quantidade | Trimestre = 1, Ano = 2025 | Fornecedor, Funcionário | — (nível folha) | Data, Fornecedor, Funcionário |
| 4 | Valor líquido, Valor IVA | Ano = 2025 | Cliente, Funcionário | — (nível folha) | Data, Cliente, Funcionário |
| 5 | Vendas com IVA | **Último dia do mês**, Ano = 2025 | Categoria | **DD** Categoria → Produto | Data, Produto |
| 6 | Vendas com IVA | **Semana 6**, Ano = 2025; Zona cliente = Norte | Família | **DD** Família → Produto | Data, Cliente, Produto |
| 7 | Quantidade | **Quadrimestre = 1**, Ano = 2025 | Cliente, Produto | **RU** Cliente → Tipo de cliente (e só até aí) | Data, Cliente, Produto |
| 8 | Valor IVA | **Estação = Primavera**, Ano = 2025 | Cidade (cliente), Família | Geografia cliente: Cidade · Produto: Família | Data, Cliente, Produto |
| 9 | Valor líquido (sem IVA, sem frete) | Ano = 2025; Categoria ∈ {Ar, Cordas, Membranas} | Cliente e Mês | **RU** Cliente → Zona · **RU** Mês → Trimestre | Data, Cliente, Produto |
| 10 | Vendas com IVA, Quantidade | **Fim de semana**, Trimestre = 2, Ano = 2025; Família ∈ {Acessórios, Amplificadores, Teclados} | Zona/Fornecedor e Zona/Cliente | **DD** Zona fornecedor → Fornecedor · **DD** Zona cliente → Cliente | Data, Fornecedor, Cliente, Produto |

### Atributos de dimensão exigidos pelas análises

| Atributo | Dimensão | Análises |
|---|---|---|
| Semestre, Trimestre, Quadrimestre, Mês, Semana do ano, Dia, Estação, Ano | Data | 1–10 |
| Indicador "último dia do mês" | Data | 5 |
| Indicador "fim de semana" | Data | 10 |
| Zona, Cidade, Cliente, Tipo de cliente | Cliente | 1, 2, 4, 6–10 |
| Categoria, Família, Produto | Produto | 1, 2, 5, 6, 7, 8, 9, 10 |
| Fornecedor, Zona do fornecedor | Fornecedor | 3, 10 |
| Funcionário | Funcionário | 3, 4 |

## 3. Análises adicionais suportadas

O modelo não foi desenhado só para as 10 análises acima. Também responde a:

| Análise | Como o modelo a suporta |
|---|---|
| Evolução mensal/anual e comparação com o período homólogo | Dim_Data com hierarquias completas |
| Ranking de produtos, famílias e clientes | Dim_Produto, Dim_Cliente + medidas aditivas |
| Vendas por segmento e por tipo de cliente | `Segmento` e `Tipo_Cliente` em Dim_Cliente |
| Desempenho por funcionário, grupo e departamento, ou por chefe | Dim_Funcionario com hierarquia de chefia |
| Ticket médio e nº de produtos por fatura | `numero_fatura` (dimensão degenerada) |
| Peso do frete nas vendas, por zona, família ou fornecedor | Frete alocado + dimensões |
| Prazo de pagamento (data pagamento − data fatura) | Duas relações a Dim_Data (papéis) |
| Devoluções (quantidade negativa) | Medidas aditivas aceitam sinal |
| Vendas em Espanha vs. Portugal | `Pais` na hierarquia geográfica |
| Vendas em várias moedas (futuro UK) | Valores em moeda original + EUR, `Dim_Moeda` |
| Vendas por cliente na data da venda (histórico) | SCD tipo 2 em Dim_Cliente |

## 4. Nota sobre a amostra

As 37 faturas da amostra têm `invoice_date` entre **31/01/2025 e 01/05/2025**. Algumas análises (por exemplo a 8, primavera, e a 10, 2.º trimestre) vão devolver poucos dados. Isso não é erro do modelo.
