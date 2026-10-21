# Inventário da Base de Dados Operacional - MoreRhythm

## 1. Objetivo

Este documento apresenta a estrutura da base de dados operacional MoreRhythm, utilizada como fonte de dados para o desenvolvimento do Data Mart de vendas.

O inventário identifica as tabelas de negócio, o respetivo volume de registos, as colunas, os tipos de dados, as chaves primárias e as relações entre tabelas. Esta informação serve de base ao Data Profiling e à definição posterior da arquitetura, da Staging Area e do modelo dimensional.

## 2. Caracterização da origem

| Propriedade | Descrição |
|---|---|
| Sistema de gestão de bases de dados | Microsoft SQL Server |
| Base de dados | `MoreRhythm` |
| Esquema principal | `dbo` |
| Tabelas de negócio | 12 |
| Total de registos nas tabelas de negócio | 1 057 |
| Tabela técnica excluída do inventário de negócio | `sysdiagrams` |

O total de 1 057 registos resulta da soma dos registos das 12 tabelas de negócio. A tabela `sysdiagrams`, utilizada para armazenar diagramas da base de dados, foi excluída desta contagem.

## 3. Inventário de tabelas

A contagem foi obtida através de uma consulta aos metadados do SQL Server.

| Tabela | Registos | Descrição funcional |
|---|---:|---|
| `categories` | 11 | Categorias de produtos |
| `customers` | 26 | Clientes |
| `employees` | 6 | Funcionários |
| `families` | 17 | Famílias de produtos |
| `invoices` | 37 | Cabeçalhos das faturas |
| `invoices_lines` | 93 | Linhas das faturas |
| `products` | 67 | Produtos e respetivos atributos |
| `purchases` | 18 | Cabeçalhos dos documentos de compra |
| `purchases_lines` | 77 | Linhas dos documentos de compra |
| `stocks_movements` | 686 | Movimentos de stock |
| `suplliers` | 14 | Fornecedores |
| `zones` | 5 | Zonas geográficas |
| **Total** | **1 057** | |

A tabela `stocks_movements` representa a maior parte dos registos da origem, com 686 movimentos. As tabelas `invoices` e `invoices_lines` contêm, respetivamente, 37 cabeçalhos de fatura e 93 linhas, enquanto as tabelas `purchases` e `purchases_lines` contêm 18 cabeçalhos de compra e 77 linhas.

O nome `suplliers` é mantido tal como existe na base de dados de origem.

## 4. Organização funcional dos dados

### 4.1. Clientes, funcionários e geografia

- **`customers`** — identifica os clientes através do número interno e contém informação fiscal, contactos, morada, zona, tipo, vendedor, condições de pagamento e segmento.
- **`employees`** — contém os dados dos funcionários, incluindo código, nome, grupo, departamento e referência à chefia.
- **`zones`** — associa códigos a designações de zonas geográficas.

### 4.2. Produtos e classificação

- **`products`** — contém a referência e designação do produto, família, categoria, fornecedor, stock, stock mínimo, preços, classificação e taxa de IVA.
- **`families`** — contém a referência, o nome e a classificação das famílias de produtos.
- **`categories`** — contém o código e a designação de cada categoria.

### 4.3. Vendas e faturação

- **`invoices`** — contém os cabeçalhos das faturas, com data, cliente, funcionário, data de pagamento, moeda, total dos produtos, custo de expedição, valores de IVA e total final.
- **`invoices_lines`** — contém as linhas das faturas, incluindo o identificador da fatura, produto, quantidade, preço unitário, total da linha e IVA.

### 4.4. Compras e fornecedores

- **`suplliers`** — contém a identificação dos fornecedores, contactos, morada, zona, tipo, condições de pagamento e nacionalidade.
- **`purchases`** — contém os cabeçalhos dos documentos de compra, com fornecedor, funcionário, zona, datas e valores monetários.
- **`purchases_lines`** — contém as linhas dos documentos de compra, incluindo produto, quantidade, preço unitário e total da linha.

### 4.5. Movimentos de stock

- **`stocks_movements`** — regista os movimentos de stock por produto, com data, documento associado, quantidade, preço unitário, valor total e IVA.

## 5. Chaves primárias

As chaves primárias foram obtidas através dos metadados do SQL Server.

| Tabela | Coluna da chave primária |
|---|---|
| `categories` | `Code` |
| `customers` | `number` |
| `employees` | `number` |
| `families` | `reference` |
| `invoices` | `invoice_stamp_id` |
| `invoices_lines` | `invoice_line_stamp_id` |
| `products` | `reference` |
| `purchases` | `purchase_stamp` |
| `purchases_lines` | `purchase_line_stamp` |
| `stocks_movements` | `stock_movement_stamp` |
| `suplliers` | `number` |
| `zones` | `code` |

A tabela técnica `sysdiagrams` possui também uma chave primária, `diagram_id`, mas não faz parte do modelo de negócio considerado neste inventário.

## 6. Relações entre tabelas

A consulta às chaves estrangeiras identificou 16 relações declaradas na base de dados.

| Tabela de origem | Coluna de origem | Tabela de destino | Coluna de destino |
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

Estas relações permitem identificar os principais percursos de ligação entre documentos, clientes, funcionários, produtos, fornecedores e zonas. Serão relevantes para definir os mapeamentos para a Staging Area e as relações do futuro modelo dimensional.

## 7. Tipos de dados e características relevantes

A estrutura foi obtida através da vista `INFORMATION_SCHEMA.COLUMNS`, complementada pela consulta das chaves primárias.

Os tipos de dados observados incluem `varchar`, `char`, `numeric`, `decimal`, `int`, `date` e `time`.

### 7.1. Identificadores

Os identificadores dos clientes, funcionários, fornecedores e zonas utilizam tipos numéricos. As referências dos produtos e famílias são textuais, assim como os identificadores dos documentos e das respetivas linhas.

Os identificadores dos documentos devem ser preservados durante os processos de extração e transformação, uma vez que permitem relacionar os cabeçalhos com as linhas correspondentes.

### 7.2. Valores monetários e quantidades

Os campos monetários utilizam maioritariamente `numeric(19,6)`. As quantidades das linhas de fatura e de compra utilizam `numeric(14,4)`, enquanto a quantidade dos movimentos de stock utiliza `decimal(12,3)`.

Estas diferenças de precisão devem ser consideradas na definição dos tipos de dados da Staging Area e do Data Mart, evitando arredondamentos ou perdas de precisão durante as transformações.

### 7.3. Datas e horas

As tabelas operacionais incluem datas de negócio, como `invoice_date`, `document_date` e `movement_date`, e atributos de auditoria, como `create_date`, `create_time`, `last_update_date` e `last_update_time`.

Estes atributos poderão apoiar a identificação de alterações e o planeamento dos carregamentos incrementais. A sua utilização dependerá da análise da fiabilidade e da cobertura dos valores existentes.

### 7.4. Campos anuláveis

A nulabilidade declarada na estrutura não corresponde necessariamente à presença efetiva de valores nulos. Por esse motivo, foi realizada uma análise adicional dos dados, cujos resultados são documentados no ficheiro `resultados.md`.

## 8. Observações iniciais sobre a qualidade dos dados

A análise preliminar identificou situações que devem ser consideradas na preparação dos dados:

- Existem dois registos de cliente com o mesmo número de contribuinte e o mesmo nome normalizado: clientes 10 e 18.
- Existem clientes sem determinados dados de contacto e sem zona geográfica associada.
- Existem produtos com atributos em falta, incluindo designação, família, categoria e fornecedor.
- Existem 12 linhas de compra sem produto identificado.
- Foram observadas diferenças entre o total de produtos de algumas faturas e a soma dos totais das respetivas linhas.
- Foram identificadas linhas de fatura com quantidades ou preços negativos, cuja interpretação exige análise adicional.

Estas observações são desenvolvidas no relatório de Data Profiling. Não se deve assumir que todas as situações correspondem a erros: algumas podem resultar de regras de negócio, devoluções ou particularidades dos documentos.

## 9. Validação inicial da integridade referencial

Foram executados testes para verificar a existência de registos sem correspondência nas principais relações entre documentos e entidades.

| Teste | Registos sem correspondência |
|---|---:|
| Linhas de fatura sem cabeçalho | 0 |
| Linhas de compra sem cabeçalho | 0 |
| Movimentos de stock sem produto correspondente | 0 |
| Linhas de fatura com produto inexistente | 0 |
| Linhas de compra com produto inexistente, excluindo valores nulos | 0 |
| Faturas com cliente inexistente | 0 |
| Faturas com funcionário inexistente | 0 |

Os resultados indicam que não foram encontrados registos órfãos nos testes realizados. No entanto, este resultado não significa que todos os campos estejam preenchidos ou que todos os valores sejam consistentes do ponto de vista do negócio. Por exemplo, as linhas de compra sem produto identificado não são necessariamente registos órfãos: o campo do produto pode estar nulo, embora o cabeçalho da compra exista.

## 10. Conclusão

A base de dados MoreRhythm contém 12 tabelas de negócio e 1 057 registos, abrangendo clientes, funcionários, produtos, fornecedores, faturação, compras, movimentos de stock e zonas geográficas.

A estrutura relacional e as chaves estrangeiras identificadas permitem compreender as principais dependências entre entidades e documentos. Contudo, a análise dos dados revelou situações que exigem tratamento antes da construção do Data Mart, sobretudo duplicados de clientes, campos incompletos e inconsistências nos valores das faturas.

O inventário constitui, assim, a referência estrutural para as próximas atividades: consolidação do Data Profiling, definição das regras de limpeza, preparação da Staging Area e mapeamento dos dados para o modelo dimensional.