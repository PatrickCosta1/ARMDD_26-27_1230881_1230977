# Resultados do Data Profiling - MoreRhythm

## 1. Objetivo e âmbito

Este documento apresenta os resultados das consultas de Data Profiling executadas sobre a base de dados operacional `MoreRhythm`, no SQL Server. O objetivo é caracterizar o volume e a estrutura dos dados, identificar problemas de completude, potenciais duplicados, inconsistências financeiras e verificar a integridade referencial.

Os resultados apresentados correspondem às consultas executadas. A identificação de uma anomalia não significa, por si só, que exista um erro de negócio: alguns casos podem exigir confirmação das regras operacionais, nomeadamente quando existem quantidades ou preços negativos.

## 2. Resultado 01 - Inventário e estrutura da origem

### 2.1. Número de registos por tabela

Foram identificadas 12 tabelas de negócio, com um total de **1 057 registos**. A tabela técnica `sysdiagrams` não foi incluída no total de negócio.

| Tabela | Registos |
|---|---:|
| `categories` | 11 |
| `customers` | 26 |
| `employees` | 6 |
| `families` | 17 |
| `invoices` | 37 |
| `invoices_lines` | 93 |
| `products` | 67 |
| `purchases` | 18 |
| `purchases_lines` | 77 |
| `stocks_movements` | 686 |
| `suplliers` | 14 |
| `zones` | 5 |
| **Total** | **1 057** |

A tabela `stocks_movements` concentra 686 registos, sendo a tabela com maior volume. Os dados incluem entidades de negócio (clientes, funcionários, produtos, fornecedores e zonas), documentos de faturação e compra, linhas documentais e movimentos de stock.

### 2.2. Estrutura, tipos de dados e nulabilidade

A consulta aos metadados devolveu as colunas, posições, tipos, comprimentos, precisão, escala e nulabilidade das tabelas. O inventário detalhado dessa estrutura, incluindo as chaves primárias, está documentado em [`inventario.md`](inventario.md).

Os tipos observados incluem `int`, `numeric`, `decimal`, `char`, `varchar`, `date` e `time`. Os campos monetários utilizam maioritariamente `numeric(19,6)`; as quantidades das linhas de fatura e compra utilizam `numeric(14,4)`, enquanto a quantidade dos movimentos de stock utiliza `decimal(12,3)`. Estas precisões devem ser consideradas no desenho da Staging Area e do modelo dimensional para evitar conversões com perda de precisão.

## 3. Resultado 02 - Chaves estrangeiras e relações

A consulta identificou **16 relações de chave estrangeira** declaradas na origem.

| Tabela de origem | Coluna | Tabela de destino | Coluna de destino |
|---|---|---|---|
| `customers` | `zone` | `zones` | `code` |
| `employees` | `chief` | `employees` | `number` |
| `invoices` | `customer` | `customers` | `number` |
| `invoices` | `employee` | `employees` | `number` |
| `invoices_lines` | `invoice_stamp_id` | `invoices` | `invoice_stamp_id` |
| `invoices_lines` | `product` | `products` | `reference` |
| `products` | `category` | `categories` | `Code` |
| `products` | `family` | `families` | `reference` |
| `products` | `supplyer` | `suplliers` | `number` |
| `purchases` | `supplier` | `suplliers` | `number` |
| `purchases` | `employee` | `employees` | `number` |
| `purchases` | `zone` | `zones` | `code` |
| `purchases_lines` | `purchase_stamp` | `purchases` | `purchase_stamp` |
| `purchases_lines` | `product` | `products` | `reference` |
| `stocks_movements` | `product` | `products` | `reference` |
| `suplliers` | `zone` | `zones` | `code` |

Estas relações documentam as ligações entre documentos e entidades e servem de base aos testes de integridade referencial e ao futuro mapeamento para o Data Mart. O nome `suplliers` é mantido tal como existe na base de dados operacional.

## 4. Resultado 03 - Valores em falta

A consulta verificou a presença de valores nulos nos atributos selecionados. A análise apresentada abaixo é limitada aos campos efetivamente incluídos na consulta; não representa uma verificação exaustiva de todos os atributos da base de dados.

### 4.1. Clientes

| Indicador | Total |
|---|---:|
| Total de clientes | 26 |
| Nome nulo | 0 |
| Número de contribuinte nulo | 1 |
| Zona nula | 2 |
| Email nulo | 12 |
| Telemóvel nulo | 21 |

O resultado indica ausência de valores nulos no nome, mas identifica um cliente sem número de contribuinte, dois sem zona, 12 sem email e 21 sem telemóvel. A consulta contabiliza valores nulos; os campos vazios ou compostos apenas por espaços devem ser avaliados separadamente, caso não tenham sido incluídos na condição SQL.

### 4.2. Produtos

| Indicador | Total |
|---|---:|
| Total de produtos | 67 |
| Designação em falta | 2 |
| Família em falta | 2 |
| Categoria nula | 2 |
| Fornecedor nulo | 12 |
| Stock nulo | 2 |
| Preço de venda nulo | 2 |

Existem valores em falta em vários atributos de produto. O fornecedor é o campo com mais ocorrências nulas (12). Estes casos devem ser avaliados à luz dos requisitos analíticos e das regras de negócio, sem inventar valores para preencher os campos.

### 4.3. Linhas de fatura

| Indicador | Total |
|---|---:|
| Total de linhas de fatura | 93 |
| Produto em falta | 0 |
| Quantidade nula | 0 |
| Preço unitário nulo | 0 |
| Total da linha nulo | 0 |

Não foram identificados valores nulos nos quatro campos analisados para as linhas de fatura. Isto não exclui outras anomalias, como as inconsistências entre quantidade, preço unitário e total da linha descritas na secção 6.

### 4.4. Linhas de compra

| Indicador | Total |
|---|---:|
| Total de linhas de compra | 77 |
| Produto em falta | 12 |
| Quantidade nula | 0 |
| Preço unitário nulo | 0 |
| Total da linha nulo | 0 |

Foram identificadas **12 linhas de compra sem produto**. Em conjunto, estas linhas representam uma quantidade total de **319,0000** e um valor total de **12 615,300000**.

Estas linhas têm informação quantitativa e financeira, mas não permitem identificar o produto associado. Devem ser preservadas na Staging Area e sinalizadas para análise; não deverá ser inventada uma referência de produto nem carregadas como compras de um produto arbitrário.

## 5. Resultado 04 - Potenciais duplicados de clientes

A consulta identificou dois registos que coincidem tanto no número de contribuinte normalizado como no nome normalizado.

| Critério | Valor normalizado | Ocorrências | Números de cliente |
|---|---|---:|---|
| Número de contribuinte | `502323434` | 2 | 10, 18 |
| Nome | `EIRA E BEIRA, LDA` | 2 | 10, 18 |

Os registos apresentam os mesmos valores nos principais atributos de identificação e contacto apresentados pela consulta: nome, contribuinte, telefone, contacto, email, morada, localidade, código postal, zona, tipo, vendedor, condições de pagamento, BBAN e segmento. Diferem nos atributos de auditoria: o cliente 10 foi criado em 2025-03-31 e tem última atualização em 2025-07-07; o cliente 18 foi criado em 2025-05-31 e tem última atualização em 2025-11-11.

A consulta às faturas associadas devolveu os seguintes resultados:

| Número de cliente | Número de faturas | Total faturado | Primeira fatura | Última fatura |
|---:|---:|---:|---|---|
| 10 | 1 | 90,360000 | 2025-03-31 | 2025-03-31 |
| 18 | 1 | 471,880000 | 2025-03-31 | 2025-03-31 |

Estes resultados sustentam a classificação dos registos 10 e 18 como **potenciais duplicados**. A consolidação não deve ser automática nesta fase: é necessário definir qual a referência a manter e garantir que as faturas e restantes relações continuam rastreáveis. Os valores faturados devem ser preservados e não somados ou descartados sem uma regra explícita de consolidação.

## 6. Resultado 05 - Inconsistências financeiras

### 6.1. Divergência entre quantidade × preço unitário e total da linha

A consulta identificou quatro linhas de fatura em que `line_total` difere do cálculo `quantity × unit_price`.

| Identificador da linha | Quantidade | Preço unitário | Total registado | Quantidade × preço | Diferença |
|---|---:|---:|---:|---:|---:|
| `ADM06013159093,4010000-3` | -2 | 473,00 | 946,00 | -946,00 | 1 892,00 |
| `ADM06022868091,8280000-3` | -1 | 662,00 | 662,00 | -662,00 | 1 324,00 |
| `ADM06013159092,6190000-3` | 1 | -140,00 | 140,00 | -140,00 | 280,00 |
| `ADM06033159385,9470000-3` | 10 | -13,00 | 130,00 | -130,00 | 260,00 |

Nas quatro linhas, o total registado corresponde ao valor absoluto do produto entre quantidade e preço unitário, enquanto o cálculo com sinal produz um valor negativo. O padrão é compatível com uma possível regra de sinal aplicada aos valores da linha, mas a consulta, por si só, não permite confirmar se é uma convenção de negócio ou um erro de dados.

Por isso, não se deverá substituir automaticamente o total registado, inverter sinais ou aplicar valores absolutos a todos os registos. Os quatro casos devem ser sinalizados para validação da regra de negócio.

### 6.2. Divergência entre o total do cabeçalho e a soma das linhas

Foram identificadas duas faturas em que o total de produtos do cabeçalho difere da soma dos totais das linhas.

| Identificador da fatura | Data | Total de produtos no cabeçalho | N.º de linhas | Soma dos totais das linhas | Diferença (cabeçalho − linhas) |
|---|---|---:|---:|---:|---:|
| `ADM06013159092,572514309` | 2025-01-31 | 145,00 | 1 | 140,00 | 5,00 |
| `ADM06022859337,463265852` | 2025-02-28 | 234,00 | 3 | 239,00 | -5,00 |

As divergências são de 5,00 em ambos os documentos, com sinais opostos. Os valores devem ser mantidos e as faturas sinalizadas para análise. Não existe informação suficiente nesta consulta para determinar qual dos valores é o correto ou explicar a diferença.

### 6.3. Moeda e valores dos cabeçalhos

Na listagem devolvida pela consulta, os registos apresentados usam a moeda `EURO`. Os cabeçalhos incluem total de produtos, custo de expedição, total para IVA, valor de IVA e total final. Esta observação deve ser interpretada de acordo com o conjunto efetivamente devolvido pela consulta; não deve ser generalizada para registos que não tenham sido incluídos no resultado.

## 7. Resultado 06 - Integridade referencial

Os testes executados não identificaram registos sem correspondência nas relações verificadas.

| Teste | Registos sem correspondência |
|---|---:|
| Linhas de fatura sem cabeçalho | 0 |
| Linhas de compra sem cabeçalho | 0 |
| Movimentos de stock sem produto | 0 |
| Linhas de fatura sem produto correspondente | 0 |
| Linhas de compra com produto inexistente (produto não nulo) | 0 |
| Faturas com cliente inexistente | 0 |
| Faturas com funcionário inexistente | 0 |

Os resultados indicam que os registos verificados têm correspondência nas entidades relacionadas. Contudo, **integridade referencial e completude são dimensões diferentes da qualidade**: as 12 linhas de compra sem produto não foram classificadas como referências a produtos inexistentes, porque o valor do produto está em falta. A ausência de registos órfãos nos testes realizados também não demonstra que todos os valores financeiros ou atributos estejam corretos.

## 8. Síntese dos problemas identificados

| Problema | Evidência | Implicação para o Data Mart |
|---|---|---|
| Número de contribuinte em falta | 1 cliente | Avaliar se o atributo é obrigatório para a dimensão Cliente e sinalizar o registo |
| Zona de cliente em falta | 2 clientes | Não inferir a zona; definir tratamento compatível com o modelo dimensional |
| Email em falta | 12 clientes | Preservar o valor e avaliar a sua relevância analítica |
| Telemóvel em falta | 21 clientes | Preservar o valor e avaliar a sua relevância analítica |
| Atributos de produto em falta | 2 designações, 2 famílias, 2 categorias, 12 fornecedores, 2 stocks e 2 preços de venda | Validar campos necessários para as análises e sinalizar os casos |
| Linhas de compra sem produto | 12 linhas; quantidade 319; valor 12 615,30 | Manter na Staging Area e não associar a um produto arbitrário |
| Potenciais duplicados de clientes | Clientes 10 e 18 | Definir uma regra de deduplicação e preservar a rastreabilidade |
| Inconsistência de cálculo em linhas de fatura | 4 linhas | Confirmar a regra de sinal antes de corrigir ou rejeitar |
| Divergência entre cabeçalho e linhas | 2 faturas; diferença de 5,00 e -5,00 | Sinalizar e investigar, sem substituir automaticamente os valores |
| Integridade referencial | 0 registos sem correspondência nos testes executados | Resultado favorável limitado às relações e aos testes realizados |

## 9. Conclusões e implicações para a Staging Area

O profiling revelou que a base de dados possui relações referenciais consistentes nos testes realizados, mas contém problemas de completude, potenciais duplicados e divergências financeiras que devem ser considerados no desenho do processo de preparação dos dados.

As prioridades identificadas são:

1. Preservar e sinalizar as 12 linhas de compra sem produto identificado.
2. Definir uma política explícita para os potenciais duplicados de clientes 10 e 18, sem perder a rastreabilidade das faturas.
3. Investigar as quatro linhas de fatura com discrepâncias entre quantidade, preço e total.
4. Investigar as duas faturas cujo total de produtos diverge da soma das linhas.
5. Definir regras para atributos em falta com base na sua obrigatoriedade e utilização no modelo dimensional.

De acordo com os requisitos do trabalho, os registos com problemas de qualidade cuja correção não possa ser automatizada devem ser armazenados em estruturas próprias da Staging Area e não carregados no Data Mart. A correção manual e o posterior carregamento desses registos ficam fora do âmbito definido para o trabalho.

## 10. Consultas de origem

Os resultados foram obtidos através dos scripts SQL guardados na pasta [`sql/`](sql/):

- [`01_inventario.sql`](sql/01_inventario.sql) - contagem de registos e metadados da origem;
- [`02_chaves_relacoes.sql`](sql/02_chaves_relacoes.sql) - chaves e relações;
- [`03_qualidade_dados.sql`](sql/03_qualidade_dados.sql) - valores em falta;
- [`04_duplicados_clientes.sql`](sql/04_duplicados_clientes.sql) - potenciais duplicados de clientes;
- [`05_inconsistencias_financeiras.sql`](sql/05_inconsistencias_financeiras.sql) - discrepâncias financeiras;
- [`06_integridade_referencial.sql`](sql/06_integridade_referencial.sql) - testes de integridade referencial.
