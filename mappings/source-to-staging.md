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

## 5. Colunas técnicas propostas

Além das colunas de negócio provenientes da origem, propõe-se incluir os seguintes metadados técnicos:

| Coluna proposta | Finalidade |
|---|---|
| `source_table` | Identificar a tabela operacional de origem |
| `extraction_timestamp` | Registar a data e hora da extração |
| `load_id` | Identificar a execução de carregamento |
| `validation_status` | Registar o resultado da validação do registo |
| `validation_message` | Descrever erros ou problemas detetados |

Estas colunas são uma proposta de desenho e deverão ser confirmadas antes da implementação física.

O estado de validação deverá distinguir, pelo menos, registos válidos, registos com problemas corrigíveis e registos com problemas que impedem o carregamento para o Data Warehouse.

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

### 7.2. Clientes potencialmente duplicados

Foram identificados dois registos de clientes, com os números 10 e 18, que apresentam o mesmo número de contribuinte normalizado e o mesmo nome normalizado.

Ambos deverão ser preservados durante a extração. A decisão de os consolidar deverá ser tomada numa etapa posterior, com base em regras de deduplicação e validação dos dados de negócio.

### 7.3. Inconsistências financeiras

Foram identificadas quatro linhas de faturas em que o valor registado não coincide com o produto da quantidade pelo preço unitário, assim como duas situações de divergência entre os totais dos cabeçalhos das faturas e os valores agregados das respetivas linhas.

Estas situações deverão ser sinalizadas para análise. Não se deverá assumir automaticamente que o valor calculado é o correto, uma vez que a origem poderá incluir notas de crédito, devoluções ou outras convenções de negócio que necessitam de confirmação.

### 7.4. Valores em falta

O profiling identificou valores em falta em atributos de clientes, produtos e linhas de compras. Estes casos deverão ser tratados segundo regras específicas por atributo, distinguindo campos opcionais de campos obrigatórios para o processo analítico.

## 8. Resultado esperado

A implementação deste mapeamento deverá permitir obter uma cópia rastreável dos dados operacionais na Staging Area, preparada para a execução das regras de qualidade e transformação.

O mapeamento constitui uma especificação documental inicial. A definição física das tabelas, os tipos definitivos, os mecanismos de extração e a política de carregamento incremental serão detalhados nas etapas seguintes do trabalho.