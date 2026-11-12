# Mapeamento Staging → Data Mart (ao nível do atributo)

> Responsáveis: Leonor (A) e Patrick (B) · Complementa [source-to-staging.md](source-to-staging.md) §9.3 e [transformacoes-limpeza.md](transformacoes-limpeza.md) · Modelo: [02_modelo_dimensional_dicionario_scd.md](../modelo-dimensional/02_modelo_dimensional_dicionario_scd.md) · DDL: [04_ddl_data_mart.sql](../modelo-dimensional/04_ddl_data_mart.sql)

O enunciado exige, para cada atributo, a origem, as operações de transformação e limpeza e a estratégia SCD. Os tipos de origem foram confirmados na `MoreRhythm` (`INFORMATION_SCHEMA.COLUMNS`).

## 1. Convenções

| Convenção | Regra |
|---|---|
| `limpa(x)` | `LTRIM(RTRIM(x))`; se o resultado for vazio → `NULL`. O valor bruto fica na própria coluna de `stg_<origem>` (cópia 1:1); os registos rejeitados ficam também nas tabelas `dqp_<origem>` |
| Auditoria | `Data_Criacao_Origem = create_date + create_time`; `Data_Atualizacao_Origem = last_update_date + last_update_time` (`datetime2(0)`). Se forem nulos na origem (2 produtos na amostra) usa-se `1900-01-01` |
| `Hash_SCD1` / `Hash_SCD2` | `HASHBYTES('SHA2_256', ...)` dos atributos SCD1 / SCD2 **já transformados**, concatenados por `\|` com `NULL` → texto vazio e com `CONCAT` |
| Só carregam | registos com `validation_status` `VALID` ou `CORRIGIDO` (`PENDING` e `REJECTED` não carregam) |
| Vigência SCD2 | 1.ª versão: `Data_Inicio = 1900-01-01`. Nova versão: `Data_Inicio = max(CAST(last_update_date AS date), Data_Inicio_anterior + 1)`; a anterior fecha com `Data_Fim = Data_Inicio_nova − 1`, `Versao_Atual = 0` |

## 2. `Dim_Cliente` ← `stg_customers`, `stg_customer_duplicate_groups`, `stg_zones`, `stg_employees`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Cliente `numeric(10,0)` | `customers.number` | `COALESCE(survivor_customer_number, number)`, juntando `stg_customers` a `stg_customer_duplicate_groups` por `source_customer_number` com `review_status = 'ACTIVE'`. Só os sobreviventes originam linhas da dimensão | — |
| Nome `nvarchar(55)` | `customers.name` | `limpa`; vazio → rejeitar (identificação) | 1 |
| NIF `varchar(20)` | `customers.taxpayer_number` | Remover espaços e separadores; vazio ou só zeros → `N/D` (R02). Não entra na deteção de duplicados se `N/D` | 1 |
| Contacto `nvarchar(30)` | `customers.contact` | `limpa` | 1 |
| Email `varchar(45)` | `customers.email` | `limpa`; `NULL` se vazio ou com formato inválido (R02) | 1 |
| Telefone `varchar(60)` | `customers.phone` | `limpa` | 1 |
| Telemovel `varchar(45)` | `customers.mobile` | `limpa` | 1 |
| Morada `nvarchar(55)` | `customers.address` | `limpa` | 1 |
| Codigo_Postal `varchar(45)` | `customers.zip_code` | `limpa` | 1 |
| Cidade `nvarchar(43)` | `customers.clity` (grafia da origem) | `limpa`; vazio → `Desconhecida` (cliente 21, em Espanha, com 2 faturas). A zona do cliente define a hierarquia geográfica e o país e é critério de várias análises, por isso a sua falta rejeita o cliente; a cidade só rotula, e a falta fica visível como «Desconhecida». Rejeitar o cliente 21 por causa da cidade perderia 2 faturas (3 821,48, 7,7 % do valor) | **2** |
| Zona `nvarchar(50)` | `zones.zone` via `customers.zone` | `NULL` ou sem correspondência → **cliente rejeitado** (R03); a zona nunca se infere | **2** |
| Pais `nvarchar(30)` | derivado da zona | `Espanha` → Espanha; `Norte`, `Centro`, `Sul`, `Ilhas` → Portugal (todo o cliente carregado tem zona) | **2** (com a zona) |
| Tipo_Cliente `nvarchar(20)` | `customers.type` | `limpa` | **2** |
| Segmento `nvarchar(25)` | `customers.segment` | `limpa` | **2** |
| Vendedor_Atribuido `nvarchar(30)` | `employees.name` via `customers.seller` | `seller = 0` → `NULL` (4 clientes). O hash SCD2 usa o **número** do vendedor, não o nome | **2** |
| Dias_Pagamento `smallint` | `customers.days_pay_invoices` | Cópia | 1 |
| *(excluído)* | `customers.BBAN` | Dado financeiro desnecessário (minimização de dados) | — |

**Clientes e fornecedores sem zona (R03):** não carregam na dimensão e ficam em `dqp_customers` e `dqp_suplliers`. Como uma fatura que aponta para um cliente rejeitado também é rejeitada (R08), isto não perde vendas na amostra: os clientes 2 e 20 não têm faturas. O mesmo vale para os produtos sem designação, família ou categoria (R04: `Z001` e `CORSR`, sem linhas de fatura).

**Clientes duplicados (R01):** os pares 10/18, 8/22 e 5/26 são consolidados num único cliente (sobreviventes 18, 8 e 5). `Dim_Cliente` tem uma linha por cliente real, com a chave de negócio do sobrevivente, e os clientes absorvidos não geram linhas próprias. Cada atributo usa o valor do sobrevivente se for válido; se for ausente ou inválido usa o valor válido do membro absorvido (por exemplo o email `coro@sapo.pt` do cliente 26 no grupo 5/26). Quando os dois valores são válidos e diferentes (NIF, nome e morada nos grupos 5/26 e 8/22), prevalece o do sobrevivente e a divergência fica em `review_note`. O mapa é persistente: uma decisão `ACTIVE` não é recalculada quando os atributos mudam e só se desfaz por revisão (`DISMISSED`).

## 3. `Dim_Produto` ← `stg_products`, `stg_families`, `stg_categories`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Produto `char(18)` | `products.reference` | Cópia (sem `RTRIM`, para coincidir com `invoices_lines.product`) | — |
| Designacao `nvarchar(60)` | `products.designation` | `limpa`; `NULL` → **produto rejeitado** (R04; 2 produtos, sem vendas) | 1 |
| BK_Familia `varchar(18)` | `products.family` | Cópia; `NULL` → produto rejeitado (R04) | — |
| Familia `nvarchar(60)` | `families.name` | Sem família → **produto rejeitado** (R04) | **2** |
| Classificacao_Familia `nvarchar(20)` | `families.classification` | `limpa`; vazio → `NULL` (8 famílias) | **2** |
| BK_Categoria `int` | `products.category` | Cópia; `NULL` → produto rejeitado (R04) | — |
| Categoria `nvarchar(35)` | `categories.Category` | Sem categoria → **produto rejeitado** (R04) | **2** |
| Classificacao_Produto `nvarchar(20)` | `products.classification` | `limpa`; se vazia usa `families.classification` (*fallback* da decisão 6) | **2** |
| Taxa_IVA `decimal(5,2)` | `products.vat_rate` (`numeric(2,0)`) | Cópia; `NULL` permitido (na amostra, os 2 produtos sem taxa são os rejeitados por R04) | **2** |
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
| Zona `nvarchar(50)` | `zones.zone` via `suplliers.zone` | `NULL` → **fornecedor rejeitado** (R03; fornecedores 3 e 13, sem produtos nem vendas) | **2** |
| Morada, Codigo_Postal, Contacto, Cargo_Contacto, Email, Telefone, Telemovel | `address`, `zip_code`, `contact`, `contact_position`, `email`, `phone`, `mobile` | `limpa`; vazio → `NULL` (também o email com formato inválido) | 1 |
| Dias_Pagamento `smallint` | `suplliers.days_pay_invoices` | Cópia | 1 |

Membro técnico **SK −1 "Sem fornecedor"** para os 12 produtos com `products.supplyer` nulo.

## 5. `Dim_Funcionario` ← `stg_employees`

| Atributo destino (tipo) | Origem | Transformação / limpeza | SCD |
|---|---|---|---|
| BK_Funcionario `numeric(6,0)` | `employees.number` | Cópia | — |
| Codigo `varchar(20)` | `employees.code` | `limpa` | 1 |
| Nome `nvarchar(30)` | `employees.name` | `limpa` | 1 |
| Email `varchar(100)` | `employees.email` | `limpa`; vazio ou com formato inválido → `NULL` (R02: dois `@` nos funcionários 2 e 5); o original fica na Staging | 1 |
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
| SK_Cliente `int` | `invoices.customer` | Cliente → sobrevivente (`COALESCE(survivor_customer_number, customer)` em `stg_customer_duplicate_groups`, estado `ACTIVE`) e *Lookup* da versão corrente (`Versao_Atual = 1`) em `Dim_Cliente` por `BK_Cliente` |
| SK_Produto `int` | `invoices_lines.product` | Idem, em `Dim_Produto` |
| SK_Fornecedor `int` | `products.supplyer` do produto da linha | Idem, em `Dim_Fornecedor`; `NULL` → `−1` |
| SK_Funcionario `int` | `invoices.employee` | Idem, em `Dim_Funcionario` |
| SK_Moeda `smallint` | `invoices.currency` | `EURO` → `EUR` → `Dim_Moeda` |
| Numero_Fatura `char(25)` | `invoices.invoice_stamp_id` | Cópia |
| BK_Linha_Fatura `char(25)` | `invoices_lines.invoice_line_stamp_id` | Cópia; chave do *upsert* |
| BK_Cliente_Origem `numeric(10,0)` | `invoices.customer` | Cópia, **antes** de consolidar duplicados. Guarda de que cliente de origem veio a fatura e permite reapontar as faturas já carregadas se um duplicado for detetado numa carga posterior |
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

A tabela de factos não tem estratégia SCD: as suas linhas apontam para a versão corrente de cada dimensão e só se atualizam quando a linha de origem muda. `Dim_Data`, `Dim_Taxa_Cambio` e os membros `−1` são imutáveis (sem SCD) e `Dim_Moeda` só tem correções (tipo 1).

## 8. Algoritmo de carga das dimensões (por lote)

1. Ler da Staging os registos `VALID`/`CORRIGIDO` do lote. Nas tabelas com auditoria fiável (clientes, funcionários, famílias, faturas e linhas) só os que têm `last_update` posterior à última carga bem-sucedida; em zonas, categorias, produtos e fornecedores lê-se tudo e a alteração deteta-se por *hash* (ver o quadro «Colunas que a Staging fornece», abaixo). Na 1.ª carga leem-se todos.
2. Calcular `Hash_SCD1` e `Hash_SCD2` sobre os valores transformados.
3. Em `Dim_Cliente`, partir só dos sobreviventes do mapa `stg_customer_duplicate_groups` e consolidar os atributos do grupo. Procurar a versão corrente por BK (`Versao_Atual = 1`):
   - **não existe** → inserir versão com `Data_Inicio = 1900-01-01`;
   - **`Hash_SCD2` igual e `Hash_SCD1` diferente** → atualizar (tipo 1) **todas** as versões desse BK;
   - **`Hash_SCD2` diferente** → fechar a versão corrente e inserir nova versão (tipo 2) com os atributos SCD1 atuais;
   - **hashes iguais** → nada a fazer (repetir o lote não altera nada).
4. As dimensões carregam **antes** dos factos.

## 9. Colunas que a Staging fornece (verificação cruzada)

A Staging tem 20 tabelas: 12 `stg_<origem>`, 6 tabelas de rejeição `dqp_<origem>` e 2 de apoio (`stg_load_control` e `stg_customer_duplicate_groups`). O quadro mostra onde está cada necessidade deste mapeamento.

| Necessidade do Data Mart | Onde |
|---|---|
| Todas as colunas de negócio das 9 tabelas acima, com o tipo da origem (incluindo `BBAN`, que **não** sobe para o Data Mart) | `stg_customers`, `stg_products`, `stg_families`, `stg_categories`, `stg_suplliers`, `stg_zones`, `stg_employees`, `stg_invoices`, `stg_invoices_lines` |
| Colunas técnicas `load_id`, `validation_status`, `validation_rule`, `raw_row_hash` | todas as `stg_<origem>` |
| `frete_alocado` (linhas), `line_sum` e `header_line_difference` (fatura) | `stg_invoices_lines` / `stg_invoices` |
| Marca de que a classificação do produto veio do *fallback* da família | `stg_products.classification_fallback`; o Data Mart não tem coluna para isso |
| Mapa origem → sobrevivente dos clientes duplicados | `stg_customer_duplicate_groups` (`source_customer_number`, `survivor_customer_number`, `review_status`) |
| Registos rejeitados, com a regra e a descrição do problema | tabelas `dqp_<origem>` (padrão DQP das aulas). R06, R07 e R11 rejeitam a fatura inteira |
| Marca para a carga incremental | `MAX(last_update)` de cada tabela `stg_` (não o relógio da extração), só nas tabelas com auditoria fiável (clientes, funcionários, famílias, faturas e linhas). Produtos e fornecedores têm `last_update` anterior à criação em 8 de 67 e 8 de 14 registos, e zonas e categorias não têm auditoria: nestas lê-se tudo e compara-se o `raw_row_hash`. `stg_load_control` não tem `source_table` |

Só entram em `Fact_Vendas` faturas sem R06, R07 e R11 (7 das 37 faturas ficam de fora: 4 989,88 de 49 341,33, ou 10,1 % do valor).
