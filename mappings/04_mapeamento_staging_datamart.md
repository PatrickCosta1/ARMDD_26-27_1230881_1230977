# Mapeamento Staging → Data Mart (ao nível do atributo)

> Responsável: Leonor (A), em conjunto com Patrick (B) · Complementa [source-to-staging.md](source-to-staging.md) §9.3 e [transformacoes-limpeza.md](transformacoes-limpeza.md) · Modelo: [02_modelo_dimensional_dicionario_scd.md](../modelo-dimensional/02_modelo_dimensional_dicionario_scd.md) · DDL: [04_ddl_data_mart.sql](../modelo-dimensional/04_ddl_data_mart.sql)

O enunciado exige, para cada atributo, a origem, as operações de transformação e limpeza e a estratégia SCD. Os tipos de origem foram confirmados na `MoreRhythm` (`INFORMATION_SCHEMA.COLUMNS`).

## 1. Convenções

| Convenção | Regra |
|---|---|
| `limpa(x)` | `LTRIM(RTRIM(x))`; se o resultado for vazio → `NULL`. O valor bruto fica sempre em `raw_row_json` |
| Auditoria | `Data_Criacao_Origem = create_date + create_time`; `Data_Atualizacao_Origem = last_update_date + last_update_time` (`datetime2(0)`). Se forem nulos na origem (2 produtos na amostra) usa-se `1900-01-01` |
| `Hash_SCD1` / `Hash_SCD2` | `HASHBYTES('SHA2_256', ...)` dos atributos SCD1 / SCD2 **já transformados**, concatenados por `\|` com `NULL` → texto vazio e com `CONCAT` |
| Só carregam | registos com `validation_status` `VALID` ou `CORRIGIDO` (a Staging usa `PENDING` / `REJECTED`; nos documentos de regras aparecem como "pendente" / "rejeitado") |
| Vigência SCD2 | 1.ª versão: `Data_Inicio = 1900-01-01`. Nova versão: `Data_Inicio = max(CAST(last_update_date AS date), Data_Inicio_anterior + 1)`; a anterior fecha com `Data_Fim = Data_Inicio_nova − 1`, `Versao_Atual = 0` |

## 2. `Dim_Cliente` ← `stg_customers`, `stg_zones`, `stg_employees`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Cliente `numeric(10,0)` | `customers.number` | Cópia | — |
| Nome `nvarchar(55)` | `customers.name` | `limpa`; vazio → rejeitar (identificação) | 1 |
| NIF `varchar(20)` | `customers.taxpayer_number` | Remover espaços e separadores; vazio ou só zeros → `N/D` (R02). Não entra na deteção de duplicados se `N/D` | 1 |
| Contacto `nvarchar(30)` | `customers.contact` | `limpa` | 1 |
| Email `varchar(45)` | `customers.email` | `limpa`; `NULL` se vazio | 1 |
| Telefone `varchar(60)` | `customers.phone` | `limpa` | 1 |
| Telemovel `varchar(45)` | `customers.mobile` | `limpa` | 1 |
| Morada `nvarchar(55)` | `customers.address` | `limpa` | 1 |
| Codigo_Postal `varchar(45)` | `customers.zip_code` | `limpa` | 1 |
| Cidade `nvarchar(43)` | `customers.clity` (grafia da origem) | `limpa`; vazio → `Desconhecida` | **2** |
| Zona `nvarchar(50)` | `zones.zone` via `customers.zone` | `NULL` ou sem correspondência → `Zona desconhecida`; nunca se infere (R03) | **2** |
| Pais `nvarchar(30)` | derivado da zona | `Espanha` → Espanha; `Norte`, `Centro`, `Sul`, `Ilhas` → Portugal; zona desconhecida → `Desconhecido` | **2** (com a zona) |
| Tipo_Cliente `nvarchar(20)` | `customers.type` | `limpa` | **2** |
| Segmento `nvarchar(25)` | `customers.segment` | `limpa` | **2** |
| Vendedor_Atribuido `nvarchar(30)` | `employees.name` via `customers.seller` | `seller = 0` → `NULL` (4 clientes). O hash SCD2 usa o **número** do vendedor, não o nome | **2** |
| Dias_Pagamento `smallint` | `customers.days_pay_invoices` | Cópia | 1 |
| *(excluído)* | `customers.BBAN` | Dado financeiro desnecessário (minimização de dados) | — |

**Duplicados (clientes 10 e 18):** são carregados como dois clientes distintos (`stg_customer_duplicate_groups`, estado `PENDING_REVIEW`). Uma futura consolidação reaponta as faturas ao sobrevivente na carga seguinte.

## 3. `Dim_Produto` ← `stg_products`, `stg_families`, `stg_categories`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Produto `char(18)` | `products.reference` | Cópia (sem `RTRIM`, para coincidir com `invoices_lines.product`) | — |
| Designacao `nvarchar(60)` | `products.designation` | `limpa`; `NULL` → `Desconhecida` (2 produtos, sem vendas) | 1 |
| BK_Familia `varchar(18)` | `products.family` | `NULL` → `N/D` | — |
| Familia `nvarchar(60)` | `families.name` | Sem família → `Desconhecida` | **2** |
| Classificacao_Familia `nvarchar(20)` | `families.classification` | `limpa`; vazio → `NULL` (8 famílias) | **2** |
| BK_Categoria `int` | `products.category` | `NULL` → `−1` | — |
| Categoria `nvarchar(35)` | `categories.Category` | Sem categoria → `Desconhecida` | **2** |
| Classificacao_Produto `nvarchar(20)` | `products.classification` | `limpa`; se vazia usa `families.classification` (*fallback* da decisão 6) | **2** |
| Taxa_IVA `decimal(5,2)` | `products.vat_rate` (`numeric(2,0)`) | Cópia; `NULL` mantém-se (2 produtos) | **2** |
| *(excluídos)* | `stock`, `minimum_stock`, `current_sell_price`, `last_cost_price` | Semi-aditivos ou variáveis; o preço real está no facto | — |

## 4. `Dim_Fornecedor` ← `stg_suplliers`, `stg_zones`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Fornecedor `numeric(10,0)` | `suplliers.number` | Cópia | — |
| Nome `nvarchar(55)` | `suplliers.name` | `limpa` | 1 |
| NIF `varchar(20)` | `suplliers.taxpayer_number` | Como no cliente (`N/D` se vazio ou zeros) | 1 |
| Tipo_Fornecedor `nvarchar(20)` | `suplliers.type` | `limpa` | **2** |
| Nacionalidade `nvarchar(20)` | `suplliers.nationality` | `limpa`; vazio → `NULL` | 1 |
| Cidade `nvarchar(43)` | `suplliers.city` | `limpa`; vazio → `Desconhecida` | **2** |
| Zona `nvarchar(50)` | `zones.zone` via `suplliers.zone` | `NULL` → `Zona desconhecida` | **2** |
| Morada, Codigo_Postal, Contacto, Cargo_Contacto, Email, Telefone, Telemovel | `address`, `zip_code`, `contact`, `contact_position`, `email`, `phone`, `mobile` | `limpa`; vazio → `NULL` | 1 |
| Dias_Pagamento `smallint` | `suplliers.days_pay_invoices` | Cópia | 1 |

Membro técnico **SK −1 "Sem fornecedor"** para os 12 produtos com `products.supplyer` nulo.

## 5. `Dim_Funcionario` ← `stg_employees`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Funcionario `numeric(6,0)` | `employees.number` | Cópia | — |
| Codigo `varchar(20)` | `employees.code` | `limpa` | 1 |
| Nome `nvarchar(30)` | `employees.name` | `limpa` | 1 |
| Email `varchar(100)` | `employees.email` | `limpa` | 1 |
| Grupo `nvarchar(20)` | `employees.[group]` | `limpa` (nome reservado: escrever entre parênteses retos) | **2** |
| Departamento `nvarchar(20)` | `employees.departament` (grafia da origem) | `limpa` | **2** |
| BK_Chefe `numeric(6,0)` | `employees.chief` | `NULL` para a direção (2 funcionários) | **2** |
| Nome_Chefe `nvarchar(30)` | `employees.name` via `chief` | `NULL` se não há chefe. O hash SCD2 usa o **número** do chefe; se o chefe mudar de nome, o nome é atualizado em todas as versões dos subordinados | **2** (por `BK_Chefe`) |

## 6. `Dim_Data`, `Dim_Moeda`, `Dim_Taxa_Cambio`

Não vêm da Staging. `Dim_Data` e `Dim_Taxa_Cambio` (EUR = 1) são populadas por [05_carga_dim_data_moeda.sql](../modelo-dimensional/05_carga_dim_data_moeda.sql). `Dim_Moeda`: `invoices.currency = 'EURO'` → `EUR`; qualquer outro valor sem correspondência é rejeitado. Cotações GBP: carga futura.

## 7. `Fact_Vendas` ← `stg_invoices` + `stg_invoices_lines`

| Atributo destino (tipo) | Origem | Transformação / limpeza |
|---|---|---|
| SK_Data_Fatura `int` | `invoices.invoice_date` | `yyyymmdd`; data fora de `Dim_Data` → rejeitar |
| SK_Data_Pagamento `int` | `invoices.payment_date` | `yyyymmdd`; `NULL` → `−1`. Na amostra a data está sempre preenchida e pode ser de vencimento (a confirmar) |
| SK_Cliente `int` | `invoices.customer` | Pesquisa em `Dim_Cliente` por `BK_Cliente` e `invoice_date BETWEEN Data_Inicio AND Data_Fim` |
| SK_Produto `int` | `invoices_lines.product` | Idem, em `Dim_Produto` |
| SK_Fornecedor `int` | `products.supplyer` do produto da linha | Idem, em `Dim_Fornecedor`; `NULL` → `−1` |
| SK_Funcionario `int` | `invoices.employee` | Idem, em `Dim_Funcionario` |
| SK_Moeda `smallint` | `invoices.currency` | `EURO` → `EUR` → `Dim_Moeda` |
| Numero_Fatura `char(25)` | `invoices.invoice_stamp_id` | Cópia |
| BK_Linha_Fatura `char(25)` | `invoices_lines.invoice_line_stamp_id` | Cópia; chave do *upsert* |
| Quantidade `decimal(14,4)` | `invoices_lines.quantity` | Cópia, sem alterar o sinal |
| Preco_Unitario `decimal(19,6)` | `invoices_lines.unit_price` | Cópia |
| Valor_Liquido `decimal(19,6)` | `invoices_lines.line_total` | Cópia; R06 (`≠ quantidade × preço`) rejeita a fatura |
| Valor_IVA `decimal(19,6)` | `invoices_lines.line_vat` | Cópia; `NULL` (permitido na origem, 0 casos) → rejeitar, por ser medida |
| Frete_Alocado `decimal(19,6)` | `invoices.shipping_cost` | `ROUND(shipping_cost × line_total / Σ line_total, 6)`; resíduo na última linha por `invoice_line_stamp_id`; se `Σ line_total = 0`, divisão igual pelas linhas. Controlo: `Σ = shipping_cost` por fatura |
| Taxa_Cambio `decimal(18,8)` | `Dim_Taxa_Cambio` | Taxa da moeda no dia da fatura; sem taxa → rejeitar (a FK composta também o impede) |
| Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR | cálculo | `ROUND(valor × Taxa_Cambio, 6)` |
| Data_Criacao_Origem | `invoices_lines.create_*` | `datetime2(0)` |
| Data_Atualizacao_Origem | `invoices_lines.last_update_*` e `invoices.last_update_*` | **O máximo dos dois**: uma alteração ao frete no cabeçalho muda a alocação de todas as linhas sem tocar nas linhas |
| ID_Lote_ETL `bigint` | `stg_load_control.load_id` | Lote que inseriu ou atualizou |
| Hash_Linha `varbinary(32)` | `raw_row_hash` da linha e da fatura | `SHA2_256` da concatenação dos dois hashes: a linha só é reaplicada se mudar a linha **ou** o cabeçalho |

**Limitação conhecida:** `Dim_Fornecedor` não faz parte da hierarquia SCD de `Dim_Produto`. O fornecedor da linha é o que `products.supplyer` tem na altura da carga e não se historiciza se o produto mudar de fornecedor.

## 8. Algoritmo de carga das dimensões (por lote)

1. Ler da Staging os registos `VALID`/`CORRIGIDO` do lote com `last_update` posterior à última carga bem-sucedida (ou todos, se for a 1.ª carga).
2. Calcular `Hash_SCD1` e `Hash_SCD2` sobre os valores transformados.
3. Procurar a versão corrente por BK (`Versao_Atual = 1`):
   - **não existe** → inserir versão com `Data_Inicio = 1900-01-01`;
   - **`Hash_SCD2` igual e `Hash_SCD1` diferente** → atualizar (tipo 1) **todas** as versões desse BK;
   - **`Hash_SCD2` diferente** → fechar a versão corrente e inserir nova versão (tipo 2) com os atributos SCD1 atuais;
   - **hashes iguais** → nada a fazer (repetir o lote não altera nada).
4. As dimensões carregam **antes** dos factos.

## 9. Colunas que a Staging tem de fornecer (verificação cruzada com o Patrick)

As tabelas tipadas `stg_<origem>` ainda não existem em [03_ddl_staging_area.sql](03_ddl_staging_area.sql). Para este mapeamento funcionar, têm de existir:

| Necessidade do Data Mart | Onde |
|---|---|
| Todas as colunas de negócio das 9 tabelas acima, com o tipo da origem (incluindo `BBAN`, que **não** sobe para o Data Mart) | `stg_customers`, `stg_products`, `stg_families`, `stg_categories`, `stg_suplliers`, `stg_zones`, `stg_employees`, `stg_invoices`, `stg_invoices_lines` |
| Colunas técnicas `load_id`, `validation_status`, `validation_rule`, `raw_row_hash` | todas |
| `frete_alocado`, `line_sum` (Σ das linhas) e `header_line_difference` | `stg_invoices_lines` / `stg_invoices` |
| Marca de que a classificação do produto veio do *fallback* da família | `stg_products` (decisão 6 pede para registar a origem do valor; o Data Mart não tem coluna para isso) |
| Estado `PENDING_REVIEW` do grupo de duplicados por cliente | `stg_customer_duplicate_groups` (já existe) |
