# Anexo C — Estruturas da Staging Area

A Staging Area tem 15 tabelas na base de dados `MoreRhythm_STG`: três de apoio (C.1) e as 12 tabelas `stg_<origem>`, uma por tabela de negócio da origem. As tabelas `stg_<origem>` partilham as nove colunas técnicas de C.2; as colunas de negócio de cada uma (C.3) têm o mesmo nome, tipo, precisão e nulabilidade da origem. A definição executável está em `mappings/03_ddl_staging_area.sql` e `mappings/05_ddl_staging_tabelas_tipadas.sql`, e os testes da estrutura em `mappings/06_testes_staging.sql`.

## C.1 Tabelas de apoio

**`stg_load_control`** — Controlo das execuções de carga. Uma linha por execução.

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `load_id` | `bigint` | N | Identificador da execução; chave primária (IDENTITY) |
| `source_system` | `sysname` | N | Sistema de origem |
| `extraction_started_at` | `datetime2(3)` | N | Início da extração |
| `extraction_finished_at` | `datetime2(3)` | S | Fim da extração |
| `status` | `varchar(20)` | N | `RUNNING`, `SUCCEEDED` ou `FAILED` |
| `rows_extracted` | `int` | N | Registos extraídos |
| `rows_validated` | `int` | N | Registos validados |
| `rows_rejected` | `int` | N | Registos rejeitados |
| `error_message` | `nvarchar(2000)` | S | Mensagem de erro, se falhou |

**`stg_rejections`** — Registos rejeitados, com os valores originais em JSON. Uma linha por registo e por regra violada.

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `rejection_id` | `bigint` | N | Identificador; chave primária (IDENTITY) |
| `load_id` | `bigint` | N | Execução de carga (FK para `stg_load_control`) |
| `source_table` | `sysname` | N | Tabela de origem |
| `source_pk` | `nvarchar(250)` | N | Chave primária da origem, serializada |
| `raw_row_json` | `nvarchar(max)` | N | Valores originais do registo, em JSON |
| `validation_rule` | `varchar(10)` | N | Regra violada (R01 a R11) |
| `validation_message` | `nvarchar(1000)` | N | Descrição do problema |
| `rejected_at` | `datetime2(3)` | N | Instante da rejeição |
| `resolution_status` | `varchar(20)` | N | `OPEN` (por omissão), `RESOLVED` ou `CANCELLED` |

**`stg_customer_duplicate_groups`** — Clientes duplicados (R01). Uma linha por cliente de origem que pertence a um grupo; a decisão é persistente.

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `source_customer_number` | `numeric(10,0)` | N | Número do cliente de origem; chave primária |
| `duplicate_group_id` | `int` | N | Grupo (atribuído pelo processo) |
| `survivor_customer_number` | `numeric(10,0)` | N | Sobrevivente do grupo (FK para a própria tabela); no próprio sobrevivente é igual a `source_customer_number` |
| `name_similarity` | `decimal(3,2)` | S | Semelhança do nome com o sobrevivente (0 a 1) |
| `corroborating_attributes` | `tinyint` | S | Atributos corroborantes (0 a 6) |
| `review_status` | `varchar(20)` | N | `ACTIVE` (por omissão) ou `DISMISSED` |
| `decided_load_id` | `bigint` | N | Carga em que a decisão foi tomada (FK) |
| `decided_at` | `datetime2(3)` | N | Instante da decisão |
| `reviewed_at` | `datetime2(3)` | S | Instante da revisão que desfez a decisão |
| `review_note` | `nvarchar(1000)` | S | Valores válidos e diferentes entre os membros |

## C.2 Colunas técnicas comuns às 12 tabelas `stg_<origem>`

| Coluna | Tipo | Nulável | Descrição |
|---|---|---|---|
| `stg_row_id` | `bigint` | N | Identificador técnico da cópia (IDENTITY); chave primária |
| `load_id` | `bigint` | N | Execução de carga (FK para `stg_load_control`) |
| `source_table` | `sysname` | N | Tabela de origem; valor por omissão e restrição CHECK com o nome da tabela |
| `source_pk` | `nvarchar(250)` | N | Chave primária da origem, no formato `coluna=valor` (colunas por ordem alfabética, separadas por `\|`) |
| `extraction_timestamp` | `datetime2(3)` | N | Instante (UTC) da extração |
| `validation_status` | `varchar(20)` | N | `VALID`, `CORRIGIDO`, `PENDING` (por omissão) ou `REJECTED` |
| `validation_rule` | `varchar(10)` | S | Regra (R01 a R11) que originou o estado, quando aplicável |
| `validation_message` | `nvarchar(1000)` | S | Descrição legível do problema |
| `raw_row_hash` | `varbinary(32)` | N | *Hash* SHA2_256 dos valores de origem (idempotência) |

Cada tabela tem ainda a restrição `UNIQUE (load_id, source_pk)`: a mesma chave pode repetir-se em lotes diferentes, mas não no mesmo.

## C.3 Colunas de negócio e auxiliares por tabela

**C.3.1 `stg_zones`** (origem: `zones`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `code` | `numeric(5,0)` | N |  |
| `zone` | `varchar(50)` | S |  |

**C.3.2 `stg_categories`** (origem: `categories`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `Code` | `int` | N |  |
| `Category` | `varchar(35)` | S |  |

**C.3.3 `stg_families`** (origem: `families`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `reference` | `varchar(18)` | N |  |
| `name` | `varchar(60)` | N |  |
| `classification` | `varchar(20)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |

**C.3.4 `stg_suplliers`** (origem: `suplliers`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `number` | `numeric(10,0)` | N |  |
| `name` | `varchar(55)` | N |  |
| `phone` | `varchar(60)` | N |  |
| `contact` | `varchar(30)` | N |  |
| `address` | `varchar(55)` | N |  |
| `city` | `varchar(43)` | N |  |
| `zip_code` | `varchar(45)` | N |  |
| `taxpayer_number` | `varchar(20)` | N |  |
| `zone` | `numeric(5,0)` | S |  |
| `type` | `varchar(20)` | N |  |
| `days_pay_invoices` | `numeric(3,0)` | N |  |
| `contact_position` | `varchar(15)` | N |  |
| `email` | `varchar(45)` | N |  |
| `nationality` | `varchar(20)` | N |  |
| `mobile` | `varchar(45)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |

**C.3.5 `stg_employees`** (origem: `employees`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `number` | `numeric(6,0)` | N |  |
| `code` | `varchar(20)` | N |  |
| `name` | `varchar(30)` | N |  |
| `group` | `varchar(20)` | N |  |
| `departament` | `varchar(20)` | N |  |
| `email` | `varchar(100)` | N |  |
| `chief` | `numeric(6,0)` | S |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |

**C.3.6 `stg_customers`** (origem: `customers`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `number` | `numeric(10,0)` | N |  |
| `name` | `varchar(55)` | N |  |
| `taxpayer_number` | `varchar(20)` | N |  |
| `phone` | `varchar(60)` | N |  |
| `mobile` | `varchar(45)` | N |  |
| `contact` | `varchar(30)` | N |  |
| `email` | `varchar(45)` | N |  |
| `address` | `varchar(55)` | N |  |
| `clity` | `varchar(43)` | N |  |
| `zip_code` | `varchar(45)` | N |  |
| `zone` | `numeric(5,0)` | S |  |
| `type` | `varchar(20)` | N |  |
| `seller` | `numeric(4,0)` | N |  |
| `days_pay_invoices` | `numeric(3,0)` | N |  |
| `BBAN` | `varchar(28)` | N |  |
| `segment` | `varchar(25)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |
| `normalised_name` | `varchar(55)` | S | Auxiliar: nome normalizado, só para comparação (R01) |
| `normalised_taxpayer` | `varchar(20)` | S | Auxiliar: NIF sem separadores, só para comparação (R01) |
| `normalised_email` | `varchar(45)` | S | Auxiliar: email normalizado, só para comparação |
| `normalised_address` | `varchar(55)` | S | Auxiliar: morada normalizada, só para comparação (R01) |

**C.3.7 `stg_products`** (origem: `products`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `reference` | `char(18)` | N |  |
| `designation` | `char(60)` | S |  |
| `family` | `varchar(18)` | S |  |
| `stock` | `numeric(13,3)` | S |  |
| `current_sell_price` | `numeric(19,6)` | S |  |
| `supplyer` | `numeric(10,0)` | S |  |
| `minimum_stock` | `numeric(13,3)` | S |  |
| `category` | `int` | S |  |
| `classification` | `varchar(20)` | S |  |
| `last_cost_price` | `numeric(19,6)` | S |  |
| `vat_rate` | `numeric(2,0)` | S |  |
| `create_date` | `date` | S |  |
| `create_time` | `time(7)` | S |  |
| `last_update_date` | `date` | S |  |
| `last_update_time` | `time(7)` | S |  |
| `classification_fallback` | `bit` | N | Auxiliar: 1 se a classificação veio da família (*fallback*) |

**C.3.8 `stg_invoices`** (origem: `invoices`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `invoice_stamp_id` | `char(25)` | N |  |
| `invoice_date` | `date` | N |  |
| `customer` | `numeric(10,0)` | N |  |
| `employee` | `numeric(6,0)` | N |  |
| `payment_date` | `date` | N |  |
| `currency` | `varchar(11)` | N |  |
| `products_total` | `numeric(19,6)` | N |  |
| `shipping_cost` | `numeric(19,6)` | N |  |
| `total_for_vat` | `numeric(19,6)` | N |  |
| `vat_value` | `numeric(19,6)` | N |  |
| `final_total` | `numeric(19,6)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |
| `line_sum` | `numeric(19,6)` | S | Auxiliar: soma de `line_total` das linhas da fatura (R07) |
| `header_line_difference` | `numeric(19,6)` | S | Auxiliar: `products_total` menos `line_sum` (R07) |

**C.3.9 `stg_invoices_lines`** (origem: `invoices_lines`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `invoice_line_stamp_id` | `char(25)` | N |  |
| `invoice_stamp_id` | `char(25)` | N |  |
| `product` | `char(18)` | N |  |
| `quantity` | `numeric(14,4)` | N |  |
| `unit_price` | `numeric(19,6)` | N |  |
| `line_total` | `numeric(19,6)` | N |  |
| `line_vat` | `numeric(19,6)` | S |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |
| `frete_alocado` | `numeric(19,6)` | S | Auxiliar: frete da fatura alocado à linha |

**C.3.10 `stg_purchases`** (origem: `purchases`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `purchase_stamp` | `char(25)` | N |  |
| `document_name` | `varchar(20)` | N |  |
| `document_number` | `varchar(20)` | N |  |
| `document_date` | `date` | N |  |
| `supplier` | `numeric(10,0)` | N |  |
| `employee` | `numeric(6,0)` | N |  |
| `payment_date` | `date` | N |  |
| `zone` | `numeric(5,0)` | N |  |
| `products_total` | `numeric(19,6)` | N |  |
| `vat_value` | `numeric(19,6)` | N |  |
| `final_total` | `numeric(19,6)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |

**C.3.11 `stg_purchases_lines`** (origem: `purchases_lines`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `purchase_line_stamp` | `char(25)` | N |  |
| `purchase_stamp` | `char(25)` | N |  |
| `document_name` | `varchar(20)` | N |  |
| `document_number` | `varchar(20)` | N |  |
| `document_date` | `date` | N |  |
| `product` | `char(18)` | S |  |
| `quantity` | `numeric(14,4)` | N |  |
| `unit_price` | `numeric(19,6)` | N |  |
| `line_total` | `numeric(19,6)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | S |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | S |  |

**C.3.12 `stg_stocks_movements`** (origem: `stocks_movements`)

| Coluna | Tipo | Nulável | Observação |
|---|---|---|---|
| `stock_movement_stamp` | `char(25)` | N |  |
| `document_name` | `varchar(20)` | N |  |
| `document_number` | `varchar(20)` | N |  |
| `movement_date` | `date` | N |  |
| `product` | `char(18)` | N |  |
| `quantity` | `decimal(12,3)` | N |  |
| `unit_price` | `numeric(19,6)` | N |  |
| `total_value` | `numeric(19,6)` | N |  |
| `vat_value` | `numeric(19,6)` | N |  |
| `create_date` | `date` | N |  |
| `create_time` | `time(7)` | N |  |
| `last_update_date` | `date` | N |  |
| `last_update_time` | `time(7)` | N |  |
