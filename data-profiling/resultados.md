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


O resultado indica ausência de nomes em falta segundo o critério utilizado, mas identifica um cliente sem número de contribuinte, dois sem zona, 12 sem email e 21 sem telemóvel. Para o nome, número de contribuinte, email e telemóvel, a consulta considera tanto valores nulos como cadeias vazias ou compostas apenas por espaços. Para a zona, contabiliza os valores nulos.

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

### 4.5. Validação de formato e de domínio

Os valores em falta foram completados com verificações de formato e de domínio ([`07_dominio_e_duplicados.sql`](sql/07_dominio_e_duplicados.sql), parte A). Um valor composto só por espaços é tratado como ausente.

| Atributo | Regra de validação | Resultado |
|---|---|---|
| NIF de cliente | 9 dígitos, não composto só por zeros | 4 de 26 clientes não identificam: 20 (vazio), 24 (`0`), 25 (`00`) e 2 (`000000000`, «Vendas a Dinheiro») |
| NIF de fornecedor | 9 dígitos | Fornecedor 13 vazio; fornecedor 3 com `111111111` («Compras a Dinheiro») |
| Email | um só `@`, texto antes e um `.` depois, sem espaços | Clientes: 12 ausentes e 1 inválido (cliente 5, `coro.sapo.pt`); fornecedores: 6 ausentes; funcionários: 2 inválidos (2 e 5, com dois `@`) |
| Código postal | `NNNN-NNN` e localidade | Vazio em 2 clientes (2 e 20) e em 2 fornecedores (3 e 13); fora do formato português em 1 cliente (21, Madrid, zona Espanha) e 1 fornecedor (10, Itália) |
| Taxa de IVA | valores distintos e coerência com as linhas | `products.vat_rate`: 23 em 65 produtos e nula em 2 (`Z001`, `CORSR`, sem classificação, família nem categoria); nas 93 linhas de fatura a taxa implícita (`line_vat / line_total`) é 23,00 em todas |
| Listas de valores | valores distintos | Tipo de cliente: Cliente Final (11), Revendedor (11), Interno (3), Funcionário (1); segmento: Alto, Médio, Baixo; prazo de pagamento 0, 15 ou 30 dias; sem valores fora destes conjuntos |
| Auditoria | `last_update_date >= create_date` | Violada em 8 de 67 produtos e em 8 de 14 fornecedores; sem violações em clientes, funcionários e faturas |
| Datas de faturas | intervalo e ordem | Faturas de 2025-01-31 a 2025-05-01; `payment_date` nunca anterior a `invoice_date` (0 a 334 dias depois) |

Consequências: um email inválido é tratado como ausente na coluna transformada (o valor original fica preservado); os contribuintes não identificativos não entram na deteção de duplicados; só existe uma taxa de IVA (23 %), pelo que a taxa deve ser guardada por produto e não assumida como constante, dado que a expansão a outros países obriga a taxas diferentes; as datas de auditoria invertidas obrigam a que a carga incremental não dependa só de `last_update_date` para decidir se um registo mudou (usa também o hash dos valores).

## 5. Resultado 04 - Duplicados de clientes

O enunciado indica que o mesmo cliente pode ter sido introduzido mais de uma vez, com identificadores diferentes, e que a repetição pode não ser rigorosamente igual. A análise foi feita em dois passos: igualdade exata dos atributos normalizados (§5.1) e semelhança entre atributos (§5.2 a §5.5).

### 5.1. Igualdade exata

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

A igualdade exata só encontra este par. Como a comparação por igualdade não deteta variações de escrita, aplicou-se de seguida a comparação por semelhança.

### 5.2. Semelhança entre atributos

Para os 325 pares possíveis entre os 26 clientes calcularam-se os indicadores seguintes, sobre cópias normalizadas dos atributos (a origem não é alterada):

- semelhança do nome e da morada: 1 menos a distância de Levenshtein dividida pelo comprimento da maior cadeia (0 a 1); o nome é comparado em maiúsculas, sem pontuação e sem as formas jurídicas «LDA» e «SA», e na morada «R» inicial é expandido para «RUA»;
- distância de Levenshtein entre números de contribuinte válidos (9 dígitos, não compostos só por zeros);
- igualdade do código postal, do telefone ou telemóvel, do email válido e do BBAN.

Um par é classificado como duplicado quando a semelhança do nome é pelo menos 0,80 e existem pelo menos dois atributos corroborantes (mesmo código postal; semelhança da morada pelo menos 0,80; mesmo telefone; mesmo email válido; mesmo BBAN; contribuintes a distância não superior a 2). A exigência de corroboração evita que o nome sozinho decida: os clientes internos 24 e 25 («MaisRitmo - Filial Lisboa/Porto (interno)») têm semelhança de nome de 0,85 mas nenhum atributo corroborante, e ficam distintos.

| Clientes | Nome | Semelhança do nome | Semelhança da morada | Distância NIF | Atributos corroborantes |
|---|---|---:|---:|---:|---:|
| 10 e 18 | Eira e Beira, lda | 1,00 | 1,00 | 0 | 6 de 6 |
| 8 e 22 | Luz e Som, lda / Luz e Som Lda. | 1,00 | 0,91 | 2 | 4 |
| 5 e 26 | Coro Nossa Senhora Assunção / Coro N. Senhora Assunção | 0,85 | 1,00 | 2 | 4 |

Os restantes 322 pares ficam distintos. Fora dos clientes internos, a semelhança de nome mais alta entre pares distintos é 0,59 (clientes 3 e 13, sem qualquer atributo corroborante).

Sensibilidade ao limiar do nome: com limiares de 0,50 a 0,80 o resultado é o mesmo (três pares); com 0,90 o par 5 e 26 deixa de ser detetado (0,85). O nome sozinho não separa os grupos (o par interno 24 e 25 também tem 0,85); a separação resulta da exigência de corroboração, e os três pares duplicados têm pelo menos quatro atributos corroborantes contra nenhum nos restantes.

Os dois pares novos não são visíveis por igualdade exata. Os contribuintes diferem em duas posições (`300455644` e `300456544`; `365564344` e `365564434`), o que é compatível com erro de digitação. O dígito de controlo do NIF não permite decidir qual dos dois está correto: os quatro contribuintes falham a verificação do dígito de controlo (módulo 11), tal como a maior parte dos contribuintes da amostra. No cliente 5 o email `coro.sapo.pt` não tem formato válido; o cliente 26 tem `coro@sapo.pt`.

### 5.3. Atributos com valores válidos e diferentes entre os membros do grupo

| Grupo | Atributo | Cliente 5 / 8 / 18 | Cliente 26 / 22 / 10 |
|---|---|---|---|
| 5 e 26 | NIF | `300455644` | `300456544` |
| 5 e 26 | Nome | Coro Nossa Senhora Assunção | Coro N. Senhora Assunção |
| 5 e 26 | Morada | Rua Sem Nome 514 | Rua Sem Nome, 514 |
| 8 e 22 | NIF | `365564344` | `365564434` |
| 8 e 22 | Nome | Luz e Som, lda | Luz e Som Lda. |
| 8 e 22 | Morada | Rua Almirante Pinheiro de Azevedo | R. Almirante Pinheiro Azevedo |
| 10 e 18 | — | sem divergências | — |

A diferença de NIF é a única divergência que muda a identificação do cliente e não pode ser resolvida com os dados disponíveis.

### 5.4. Impacto na faturação

| Grupo | Clientes | Faturas (cliente a cliente) | Total faturado |
|---|---|---|---:|
| 5 e 26 | 5 e 26 | 3 e 2 | 6 272,49 e 3 412,35 |
| 8 e 22 | 8 e 22 | 1 e 1 | 256,02 e 2 328,03 |
| 10 e 18 | 10 e 18 | 1 e 1 | 90,36 e 471,88 |

Os três grupos abrangem **9 das 37 faturas** e **12 831,12 de 49 341,33** (26,0 % do valor faturado). Se os duplicados forem mantidos, o número de clientes passa a ser 26 em vez de 23 e o de clientes com faturas 20 em vez de 17; as análises por cliente (4, 7, 9 e 10) repartem por dois registos o histórico do mesmo cliente.

### 5.5. Fornecedores

Os fornecedores 8 (`FaroInstrumentos`) e 14 (`FaroInstrumentos II`) têm o mesmo contribuinte (`502199378`), mas diferem na localidade (Faro e Alagoeiros), na zona (3 e 1), no telefone e no email, e fornecem produtos distintos (20 e 3 produtos). Os dados são compatíveis com dois estabelecimentos da mesma entidade e não com um registo repetido. Como a zona do fornecedor é usada na análise 10, os dois registos mantêm-se separados. Não existem outros fornecedores com contribuinte repetido.

### 5.6. Conclusão

Existem três pares de clientes duplicados (10 e 18, 8 e 22, 5 e 26), e não um. Como o enunciado exige a eliminação de redundâncias «iguais ou aproximadamente iguais», os grupos são consolidados no sobrevivente; a regra de escolha do sobrevivente e o mapeamento origem → sobrevivente estão em [`transformacoes-limpeza.md`](../mappings/transformacoes-limpeza.md), regra R01 e §4. A consolidação é feita na Staging: a origem não é alterada e os identificadores originais ficam no mapeamento.

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

### 6.4. Coerência do frete no cabeçalho

Em todas as 37 faturas a diferença `total_for_vat - products_total` é exatamente 2,5 % do total de produtos, e `final_total = total_for_vat + vat_value`. O campo `shipping_cost` coincide com essa diferença em 35 faturas; nas outras duas é superior ([`07_dominio_e_duplicados.sql`](sql/07_dominio_e_duplicados.sql), 7.4.b):

| Fatura (data, cliente) | Total de produtos | `shipping_cost` | Frete incluído no total | Diferença |
|---|---:|---:|---:|---:|
| 2025-03-31, cliente 6 | 1 008,00 | 27,70 (2,75 %) | 25,20 (2,50 %) | 2,50 |
| 2025-04-30, cliente 4 | 851,00 | 26,275 (3,09 %) | 21,275 (2,50 %) | 5,00 |

Estas duas faturas não são apanhadas pelas verificações das linhas nem pela comparação entre cabeçalho e linhas: os totais de produtos coincidem com a soma das linhas. Como o frete alocado às linhas parte de `shipping_cost`, a incoerência afetaria a medida de frete. Não existe informação que permita decidir qual dos dois valores é o frete efetivo.

### 6.5. Faturas afetadas por problemas financeiros

| Regra | Faturas | Valor (`final_total`) |
|---|---:|---:|
| Linha com quantidade × preço diferente do total (4 linhas) | 4 | 2 362,02 |
| Cabeçalho diferente da soma das linhas | 2 | 475,65 |
| Frete incoerente (só esta regra) | 2 | 2 333,05 |
| **Total (sem sobreposição)** | **7** | **4 989,88** |

Das 37 faturas, 7 (18,9 %) e 11 de 93 linhas ficam afetadas; em valor, 4 989,88 de 49 341,33 (10,1 %). Uma fatura é afetada simultaneamente pelas duas primeiras regras, pelo que a soma por regra excede o total sem sobreposição.

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
| Duplicados de clientes | 3 pares: 10 e 18 (iguais), 8 e 22 e 5 e 26 (aproximados); 9 de 37 faturas, 12 831,12 (26,0 % do valor) | Consolidar no sobrevivente na Staging, com mapeamento origem → sobrevivente (R01) |
| Formato e domínio | 4 NIF de clientes não identificativos; 1 email de cliente e 2 de funcionários inválidos; 2 produtos sem taxa de IVA; 8 produtos e 8 fornecedores com `last_update_date` anterior a `create_date` | Tratar como ausentes nas colunas transformadas (R02); a carga incremental não depende só de `last_update_date` |
| Inconsistência de cálculo em linhas de fatura | 4 linhas | Confirmar a regra de sinal antes de corrigir ou rejeitar |
| Divergência entre cabeçalho e linhas | 2 faturas; diferença de 5,00 e -5,00 | Sinalizar e investigar, sem substituir automaticamente os valores |
| Frete incoerente | 2 faturas com `shipping_cost` superior ao frete incluído no total (2,50 e 5,00) | Rejeitar a fatura inteira (R11) |
| Integridade referencial | 0 registos sem correspondência nos testes executados | Resultado favorável limitado às relações e aos testes realizados |

## 9. Conclusões e implicações para a Staging Area

O profiling revelou que a base de dados possui relações referenciais consistentes nos testes realizados, mas contém problemas de completude, potenciais duplicados e divergências financeiras que devem ser considerados no desenho do processo de preparação dos dados.

As prioridades identificadas são:

1. Preservar e sinalizar as 12 linhas de compra sem produto identificado.
2. Consolidar os três pares de clientes duplicados (10 e 18, 8 e 22, 5 e 26) num sobrevivente, sem perder a rastreabilidade das faturas.
3. Investigar as quatro linhas de fatura com discrepâncias entre quantidade, preço e total.
4. Investigar as duas faturas cujo total de produtos diverge da soma das linhas e as duas cujo `shipping_cost` não coincide com o frete incluído no total.
5. Definir regras para atributos em falta com base na sua obrigatoriedade e utilização no modelo dimensional.

De acordo com os requisitos do trabalho, os registos com problemas de qualidade cuja correção não possa ser automatizada devem ser armazenados em estruturas próprias da Staging Area e não carregados no Data Mart. A correção manual e o posterior carregamento desses registos ficam fora do âmbito definido para o trabalho.

## 10. Consultas de origem

Os resultados foram obtidos através dos scripts SQL guardados na pasta [`sql/`](sql/):

- [`01_inventario.sql`](sql/01_inventario.sql) - contagem de registos e metadados da origem;
- [`02_chaves_relacoes.sql`](sql/02_chaves_relacoes.sql) - chaves e relações;
- [`03_qualidade_dados.sql`](sql/03_qualidade_dados.sql) - valores em falta;
- [`04_duplicados_clientes.sql`](sql/04_duplicados_clientes.sql) - potenciais duplicados de clientes;
- [`05_inconsistencias_financeiras.sql`](sql/05_inconsistencias_financeiras.sql) - discrepâncias financeiras;
- [`06_integridade_referencial.sql`](sql/06_integridade_referencial.sql) - testes de integridade referencial;
- [`07_dominio_e_duplicados.sql`](sql/07_dominio_e_duplicados.sql) - validação de formato e de domínio e duplicados aproximados de clientes (cria e remove uma função auxiliar em `tempdb`; não altera a `MoreRhythm`).

## 11. Decisões de qualidade adotadas

Os resultados anteriores justificam as regras de carregamento documentadas em
[`transformacoes-limpeza.md`](../mappings/transformacoes-limpeza.md):

- os três pares de clientes duplicados (10 e 18, 8 e 22, 5 e 26) são consolidados no sobrevivente, com mapeamento origem → sobrevivente (R01);
- as 12 linhas de compras sem produto ficam rejeitadas na Staging e fora do Data Mart de vendas;
- as quatro linhas com quantidade ou preço negativo ficam rejeitadas até ser confirmada a sua semântica;
- as duas faturas com divergência entre cabeçalho e linhas ficam rejeitadas integralmente;
- as duas faturas com frete incoerente (R11) ficam rejeitadas integralmente; no total são rejeitadas 7 faturas de 37 (4 989,88 de 49 341,33, 10,1 % do valor);
- contactos e atributos descritivos ausentes podem usar `NULL` ou membro `Desconhecido`, mas nunca substituem chaves ou medidas inválidas;
- a comparação financeira usa tolerância de `0,01` e preserva os valores originais.

Assim, o profiling deixa de ser apenas inventário de anomalias e passa a justificar diretamente as regras R01–R10, as estruturas de rejeição e o critério de exclusão do Data Mart.
