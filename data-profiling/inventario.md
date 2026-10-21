# Inventário da Base de Dados Operacional - MoreRhythm

## 1. Objetivo

Este documento caracteriza a estrutura da base de dados operacional `MoreRhythm`, disponibilizada para o desenvolvimento do Data Mart de vendas da empresa More Rhythm, SA.

O inventário constitui a base para o processo de Data Profiling e para as decisões posteriores relativas à arquitetura, à Staging Area, ao modelo dimensional e aos mapeamentos de dados.

## 2. Ambiente de origem

| Propriedade | Valor |
|---|---|
| Sistema de gestão de bases de dados | Microsoft SQL Server |
| Base de dados | MoreRhythm |
| Tabelas de negócio identificadas | 12 |
| Total de registos nas tabelas de negócio | 1 057 |
| Finalidade | Suporte ao processo de conceção do Data Mart de vendas |

## 3. Inventário de tabelas e volumes

Os volumes seguintes correspondem aos resultados obtidos através das consultas de contagem de registos executadas na base de dados.

| Tabela | Número de registos | Finalidade aparente |
|---|---:|---|
| `categories` | 11 | Categorias de produtos |
| `customers` | 26 | Clientes |
| `employees` | 6 | Funcionários |
| `families` | 17 | Famílias de produtos |
| `invoices` | 37 | Cabeçalhos de faturas |
| `invoices_lines` | 93 | Linhas de faturas |
| `products` | 67 | Produtos |
| `purchases` | 18 | Cabeçalhos de compras |
| `purchases_lines` | 77 | Linhas de compras |
| `stocks_movements` | 686 | Movimentos de stock |
| `suplliers` | 14 | Fornecedores |
| `zones` | 5 | Zonas geográficas |
| **Total** | **1 057** | |

**Nota:** o nome `suplliers` corresponde à designação existente na base de dados. Deve ser preservado nos mapeamentos para evitar confusões com o nome lógico “fornecedores”.

A tabela técnica `sysdiagrams` não foi incluída no total das tabelas de negócio.

## 4. Caracterização funcional das tabelas

### 4.1. Clientes e geografia

- `customers`: contém os dados de identificação e caracterização dos clientes, incluindo nome, número de contribuinte, contactos, endereço, zona, tipo de cliente e vendedor associado.
- `zones`: contém os códigos e designações das zonas geográficas.
- `employees`: contém os dados dos funcionários, incluindo código, nome, grupo, departamento e chefia.

### 4.2. Produtos e classificação

- `products`: contém a referência, designação, família, categoria, fornecedor, preços e informação de stock.
- `families`: contém as referências, designações e classificações das famílias de produtos.
- `categories`: contém os códigos e designações das categorias.

### 4.3. Vendas e faturação

- `invoices`: contém os cabeçalhos das faturas, incluindo data, cliente, funcionário, moeda, totais, IVA e custo de expedição.
- `invoices_lines`: contém as linhas das faturas, incluindo produto, quantidade, preço unitário, total da linha e IVA.

### 4.4. Compras e fornecedores

- `suplliers`: contém os dados de identificação e contacto dos fornecedores, bem como a zona, o tipo e as condições de pagamento.
- `purchases`: contém os cabeçalhos dos documentos de compra, incluindo fornecedor, funcionário, data, zona e valores monetários.
- `purchases_lines`: contém as linhas dos documentos de compra, incluindo produto, quantidade, preço unitário e total da linha.

### 4.5. Movimentos de stock

- `stocks_movements`: regista movimentos de stock, com data, produto, quantidade, preço unitário, valor total e IVA.

## 5. Relações e integridade referencial

As chaves primárias e estrangeiras foram analisadas através das consultas executadas no SQL Server.

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

As relações acima devem ser consideradas em conjunto com as definições das chaves primárias e com os resultados dos testes de integridade referencial.

## 6. Observações sobre os atributos temporais

Várias tabelas incluem atributos de criação e atualização, nomeadamente:

- `create_date`
- `create_time`
- `last_update_date`
- `last_update_time`

Estes atributos são relevantes para o estudo dos carregamentos incrementais e para a definição das estratégias de manutenção do histórico.

A presença destes campos não garante, por si só, que todas as alterações históricas possam ser reconstruídas. Essa capacidade deverá ser avaliada na conceção do processo de carregamento.

## 7. Limitações e próximos passos

O inventário descreve a estrutura e os volumes observados, mas não constitui, isoladamente, uma validação da qualidade dos dados.

As próximas atividades consistem em:

1. Consolidar as consultas SQL utilizadas no inventário.
2. Documentar os resultados do Data Profiling.
3. Identificar registos incompletos, redundantes ou inconsistentes.
4. Avaliar a integridade referencial e a coerência dos valores monetários.
5. Definir regras de tratamento para os problemas confirmados, distinguindo correções automáticas de situações que exigem rejeição ou investigação adicional.