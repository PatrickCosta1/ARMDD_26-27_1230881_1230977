# Mapeamento da Base de Dados Operacional para a Staging Area

## 1. Objetivo

Este documento define o mapeamento entre as tabelas da base de dados operacional `MoreRhythm` e as estruturas previstas para a Staging Area do Data Mart.

A Staging Area funcionará como uma camada intermédia entre a origem dos dados e o Data Warehouse, permitindo preservar os dados extraídos, analisar a sua qualidade, identificar inconsistências e preparar os registos para as transformações seguintes.

## 2. Princípios de desenho

O processo de extração para a Staging Area deverá respeitar os seguintes princípios:

- **Preservação dos dados de origem:** os valores extraídos devem ser conservados antes da aplicação de regras de transformação ou limpeza.
- **Rastreabilidade:** cada registo deverá poder ser associado à tabela de origem e à execução de extração correspondente.
- **Validação:** os registos deverão ser analisados quanto à completude, validade, consistência e integridade referencial.
- **Tratamento explícito de erros:** os registos problemáticos não deverão ser eliminados silenciosamente. Quando não puderem ser corrigidos com segurança, deverão permanecer disponíveis para análise e ser excluídos do carregamento final até resolução.
- **Separação de responsabilidades:** a extração, a validação, a transformação e o carregamento para o Data Warehouse deverão constituir etapas distintas.

## 3. Estruturas de destino propostas

Propõe-se uma correspondência inicial de uma tabela operacional para uma tabela de Staging, mantendo os nomes das entidades reconhecíveis e utilizando o prefixo `stg_`.

| Tabela de origem | Tabela de Staging proposta | Descrição |
|---|---|---|
| `categories` | `stg_categories` | Categorias de produtos |
| `customers` | `stg_customers` | Clientes |
| `employees` | `stg_employees` | Funcionários |
| `families` | `stg_families` | Famílias de produtos |
| `invoices` | `stg_invoices` | Cabeçalhos de faturas |
| `invoices_lines` | `stg_invoices_lines` | Linhas de faturas |
| `products` | `stg_products` | Produtos |
| `purchases` | `stg_purchases` | Cabeçalhos de compras |
| `purchases_lines` | `stg_purchases_lines` | Linhas de compras |
| `stocks_movements` | `stg_stocks_movements` | Movimentos de stock |
| `suplliers` | `stg_suplliers` | Fornecedores |
| `zones` | `stg_zones` | Zonas geográficas |

A tabela `sysdiagrams`, por ser uma estrutura técnica do SQL Server e não uma entidade de negócio, não será incluída no mapeamento inicial.

A designação `suplliers` será preservada nesta fase para refletir o nome efetivo da tabela de origem. Uma eventual correção do nome deverá ser realizada apenas na camada de Data Warehouse ou na documentação lógica, sem comprometer a rastreabilidade.

## 4. Política de tipos de dados

A primeira carga para a Staging Area deverá preservar, tanto quanto possível, os tipos e valores existentes na origem.

Não se deverão converter automaticamente valores problemáticos durante a extração. As conversões para os tipos de dados definidos no modelo dimensional deverão ser realizadas nas etapas de transformação, depois da validação.

Os tipos identificados no inventário incluem `int`, `numeric`, `decimal`, `char`, `varchar`, `date` e `time`. Estes tipos deverão ser considerados na definição das estruturas de destino.

Sempre que necessário para preservar valores originais ou identificar erros de conversão, poderão ser utilizadas colunas auxiliares de texto bruto ou mecanismos equivalentes de rejeição controlada. Esta decisão deverá ser confirmada na definição física da Staging Area.

## 5. Colunas técnicas

Além das colunas de negócio provenientes da origem, cada tabela `stg_<origem>` tem nove colunas técnicas, descritas no contrato físico do §9:

| Coluna | Finalidade |
|---|---|
| `stg_row_id` | Identificar a cópia na Staging |
| `load_id` | Identificar a execução de carregamento |
| `source_table` | Identificar a tabela operacional de origem |
| `source_pk` | Chave primária da origem, serializada |
| `extraction_timestamp` | Registar a data e hora da extração |
| `validation_status` | Registar o resultado da validação do registo |
| `validation_rule` | Identificar a regra (R01 a R11) aplicada ao registo |
| `validation_message` | Descrever erros ou problemas detetados |
| `raw_row_hash` | Detetar registos já carregados (idempotência) |

O estado de validação distingue registos válidos (`VALID`), com problema corrigido automaticamente (`CORRIGIDO`), por validar (`PENDING`) e rejeitados (`REJECTED`). Só os dois primeiros seguem para o Data Warehouse.

## 6. Regras gerais de mapeamento

1. Cada tabela de origem será associada à estrutura de Staging correspondente.
2. As chaves primárias da origem serão preservadas, de modo a permitir a identificação dos registos e a análise das relações entre entidades.
3. As colunas opcionais deverão manter a possibilidade de representar valores nulos.
4. Os valores em falta, os valores em branco e os valores inválidos deverão ser avaliados de acordo com regras específicas para cada atributo.
5. As relações entre cabeçalhos e linhas de documentos deverão ser preservadas para permitir validar a integridade dos dados.
6. As regras de transformação não deverão alterar os dados originais de forma irreversível durante a extração.
7. Os registos que não cumpram regras obrigatórias de qualidade deverão ser identificados e mantidos disponíveis para análise, em vez de serem descartados sem registo.

## 7. Casos identificados no profiling

Os resultados da análise exploratória da base de dados `MoreRhythm` permitem identificar situações que deverão ser acompanhadas na Staging Area.

### 7.1. Linhas de compras sem produto identificado

Foram identificadas 12 linhas na tabela `purchases_lines` sem produto identificado. Estas linhas representam uma quantidade total de 319 unidades e um valor agregado de 12 615,30.

Os registos deverão ser extraídos e preservados na Staging Area, assinalados como problemáticos e analisados antes de qualquer carregamento para estruturas dimensionais que exijam a identificação do produto.

Não deverá ser atribuída uma referência de produto fictícia nem descartado o valor financeiro sem uma regra de negócio devidamente justificada.

### 7.2. Clientes duplicados

A comparação por semelhança (ver [`resultados.md`](../data-profiling/resultados.md), §5) identificou três pares de clientes duplicados: 10 e 18 (registos iguais), 8 e 22 e 5 e 26 (registos aproximados, com contribuintes que diferem em duas posições). Os três abrangem 9 das 37 faturas.

Todos os registos são extraídos e preservados na Staging. Cada grupo é consolidado no sobrevivente (regra R01), com o mapeamento origem → sobrevivente guardado em `stg_customer_duplicate_groups`; a consolidação é feita na Staging e a origem não é alterada.

### 7.3. Inconsistências financeiras

Foram identificadas quatro linhas de faturas em que o valor registado não coincide com o produto da quantidade pelo preço unitário (R06), duas faturas em que o total de produtos do cabeçalho difere da soma das linhas (R07) e duas faturas em que o total final não coincide com a soma de produtos, frete e IVA (R11).

A origem não permite confirmar se os sinais negativos correspondem a notas de crédito ou devoluções, nem qual dos valores é o correto nas faturas divergentes. Como o enunciado exclui do Data Mart o que não pode ser corrigido automaticamente, as faturas afetadas (7 de 37, 10,1 % do valor) ficam rejeitadas na Staging, nas tabelas `dqp_invoices` e `dqp_invoices_lines` (ver §9.1).

### 7.4. Valores em falta

O profiling identificou valores em falta em atributos de clientes, produtos e linhas de compras. Estes casos deverão ser tratados segundo regras específicas por atributo, distinguindo campos opcionais de campos obrigatórios para o processo analítico.

## 8. Resultado esperado

A implementação deste mapeamento deverá permitir obter uma cópia rastreável dos dados operacionais na Staging Area, preparada para a execução das regras de qualidade e transformação.

O mapeamento constitui a especificação da Fase 1. As estruturas de apoio (lotes, rejeições e clientes duplicados) estão em [`03_ddl_staging_area.sql`](03_ddl_staging_area.sql) e as 12 tabelas tipadas `stg_<origem>` em [`05_ddl_staging_tabelas_tipadas.sql`](05_ddl_staging_tabelas_tipadas.sql); os testes da estrutura estão em [`06_testes_staging.sql`](06_testes_staging.sql).

## 9. Contrato físico da Staging Area

Cada tabela `stg_<origem>` mantém as colunas de negócio da origem, sem conversão destrutiva, e acrescenta os metadados seguintes:

| Coluna | Tipo SQL Server | Regra |
|---|---|---|
| `stg_row_id` | `bigint IDENTITY` | Identificador técnico da cópia |
| `load_id` | `bigint` | Identifica a execução em `stg_load_control` |
| `source_table` | `sysname` | Nome da tabela de origem |
| `source_pk` | `nvarchar(250)` | Chave primária serializada de forma estável |
| `extraction_timestamp` | `datetime2(3)` | Instante UTC da extração |
| `validation_status` | `varchar(20)` | `VALID`, `CORRIGIDO`, `PENDING` ou `REJECTED` |
| `validation_rule` | `varchar(10)` | Regra R01–R11, quando aplicável |
| `validation_message` | `nvarchar(1000)` | Mensagem legível da validação |
| `raw_row_hash` | `varbinary(32)` | Hash dos valores de origem, para idempotência |

O `source_pk` é composto por `coluna=valor` em ordem alfabética das colunas da chave, usando `|` como separador. A chave não depende da ordem física da tabela. A tabela de origem nunca é atualizada pelo processo.

### 9.1. Controlo de lotes, rejeições e clientes duplicados

A Staging tem 20 tabelas: as 12 `stg_<origem>`, as 6 tabelas de rejeição `dqp_<origem>` e duas de apoio.

- `stg_load_control` regista `load_id`, origem, início e fim, contagens extraídas, válidas e rejeitadas e o estado do lote.
- `dqp_<origem>` (`dqp_customers`, `dqp_suplliers`, `dqp_products`, `dqp_invoices`, `dqp_invoices_lines` e `dqp_purchases_lines`) guarda os registos rejeitados, no padrão DQP (*Data Quality Problems*) das aulas práticas. Cada tabela tem os atributos do registo de origem, o `load_id`, a regra violada (`validation_rule`) e a descrição do problema (`DQP`); um registo que viole várias regras aparece uma vez por regra.
- `stg_customer_duplicate_groups` regista, por cliente de origem que pertence a um grupo de duplicados, o grupo, o sobrevivente, a semelhança do nome e o número de atributos corroborantes, o estado da decisão (`ACTIVE` ou `DISMISSED`), a carga em que foi tomada e a nota com os valores válidos e diferentes entre os membros. A decisão é persistente e só se desfaz por revisão explícita (regra R01, [`transformacoes-limpeza.md`](transformacoes-limpeza.md) §4).

**Rejeição.** O enunciado exige que os registos com problemas de qualidade que não se corrigem automaticamente fiquem em tabelas criadas para o efeito na Staging e não sejam carregados no Data Mart; as tabelas DQP cumprem esse requisito. Os valores de origem também ficam na tabela `stg_<origem>`, com o estado `REJECTED`; não há uma segunda cópia completa dos registos. A idempotência assenta na chave `(load_id, source_pk)` de cada tabela e, nas tabelas sem auditoria fiável, no `raw_row_hash`.

**Regras que rejeitam.** As 12 linhas de compras sem produto usam `R05`; as quatro linhas financeiras usam `R06`; as duas faturas com cabeçalho diferente da soma das linhas usam `R07`; as duas faturas com frete incoerente usam `R11`. Uma rejeição por R06, R07 ou R11 rejeita a fatura inteira, para que o frete só seja alocado sobre um conjunto completo de linhas. No conjunto, são rejeitadas 7 das 37 faturas (4 989,88 de 49 341,33; 10,1 % do valor).

### 9.2. Mapeamento coluna a coluna e validação

| Origem → Staging | Tipo preservado | Transformação de carga | Validação |
|---|---|---|---|
| Todas as colunas de `categories`, `customers`, `employees`, `families`, `invoices`, `invoices_lines`, `products`, `purchases`, `purchases_lines`, `stocks_movements`, `suplliers`, `zones` | Tipo, precisão e escala da origem | Cópia 1:1; `NULL` permanece `NULL`; espaços só são removidos numa coluna de comparação | Chave primária não nula; hash e metadados obrigatórios |
| `customers.taxpayer_number`, nome, email e morada | Tipo da origem + colunas normalizadas | `normalised_*` apenas para comparação; vazio ou formato inválido torna-se `NULL` na coluna transformada | R01: deteção de duplicados por semelhança e consolidação no sobrevivente (`stg_customer_duplicate_groups`) |
| `invoices_lines.quantity`, `unit_price`, `line_total` | `decimal(14,4)` / `decimal(19,6)` | Preservar sinal e precisão | R06 quando `line_total <> quantity * unit_price` |
| `invoices.products_total` e linhas da fatura | `decimal(19,6)` | Calcular `line_sum` e `header_line_difference` | R07 quando `ABS(difference) > 0,01` |
| `invoices.final_total`, `products_total`, `shipping_cost`, `vat_value` | `decimal(19,6)` | Preservar | R11 quando `ABS(final_total - (products_total + shipping_cost + vat_value)) > 0,01` |
| `purchases_lines.product` | Tipo da origem | Nenhuma substituição | R05 quando nulo ou vazio |

### 9.3. Staging → Data Mart

| Staging | Destino | Transformação / chave |
|---|---|---|
| `stg_customers` + `stg_customer_duplicate_groups` | `Dim_Cliente` | BK = número do sobrevivente do grupo (ou o próprio número, se não pertencer a um grupo); atributos consolidados segundo R01; SCD1/SCD2 conforme dicionário; zona desconhecida usa membro técnico |
| `stg_products` + `stg_families` + `stg_categories` | `Dim_Produto` | BK `products.reference`; SCD2 para classificação; fallback de classificação documentado |
| `stg_suplliers` + `stg_zones` | `Dim_Fornecedor` | BK `suplliers.number`; `-1` apenas quando fornecedor é descritivo e nulo |
| `stg_employees` | `Dim_Funcionario` | BK `employees.number`; pesquisa temporal da versão SCD2 |
| `stg_invoices` + `stg_invoices_lines` | `Fact_Vendas` | Uma linha por `invoice_line_stamp_id`; rejeitar a fatura se R06/R07; resolver SK pela data da fatura |
| `stg_load_control` | `Fact_Vendas.ID_Lote_ETL` | Preservar o `load_id` do lote que inseriu ou atualizou |

As chaves substitutas são resolvidas por `BK` e pelo intervalo `Data_Inicio <= invoice_date <= Data_Fim`. A dimensão é carregada antes dos factos. A carga do facto é um upsert por `BK_Linha_Fatura`; o mesmo `raw_row_hash` não é reaplicado. O frete é alocado na Staging, com o resíduo de arredondamento na última linha por identificador estável, e validado antes do insert.