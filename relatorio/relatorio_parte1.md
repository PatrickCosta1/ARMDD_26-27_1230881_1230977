# Introdução

Este relatório documenta a 1.ª parte do trabalho prático de Armazéns de Dados: o desenho de um *data mart* de vendas para a More Rhythm, SA, empresa sediada no Porto que distribui instrumentos musicais em Portugal e, pontualmente, em Espanha. A gestão quer analisar historicamente as vendas (faturação) a clientes, ao nível de detalhe mais elementar.

O relatório apresenta a arquitetura do armazém de dados, o resultado do *Data Profiling* à base de dados operacional, o modelo dimensional (metodologia de Kimball) com os respetivos atributos e tipos de dados, as estruturas da *Staging Area*, os mapeamentos origem → Staging e Staging → Data Mart (com a estratégia de *Slowly Changing Dimension* de cada atributo) e as regras de transformação e limpeza.

Os dados disponibilizados são uma amostra da base `MoreRhythm`: 12 tabelas de negócio e 1 057 registos, dos quais 37 faturas e 93 linhas de fatura, com datas entre 31/01/2025 e 01/05/2025. Algumas análises do enunciado (por exemplo a da primavera e a do 2.º trimestre) devolvem por isso poucos dados; isso não é um erro do modelo.

# Arquitetura do armazém de dados

![Arquitetura do armazém de dados](diagrama_arquitetura.svg)

A arquitetura tem quatro camadas, ligadas por um processo ETL implementado num *Integration Services Project* do Visual Studio.

| Camada | Base de dados | Função |
|---|---|---|
| Sistema operacional | `MoreRhythm` | Origem dos dados. É apenas lida; o processo nunca a altera |
| Staging Area | `MoreRhythm_STG` | Guarda uma cópia fiel e rastreável dos registos extraídos, valida-os, normaliza-os e isola os que têm problemas de qualidade |
| Data Mart | `MoreRhythm_DM` | Esquema em estrela com uma tabela de factos e as dimensões, pronto para consulta |
| Análise | Power BI | As 20 análises multidimensionais pedidas |

**Fluxo.**

1. **Extração:** cada tabela de origem é copiada para a Staging, com o identificador do lote (`load_id`), a data da extração e um *hash* do registo. A extração é incremental sempre que a tabela tem colunas de auditoria (ver secção "Carga incremental").
2. **Validação e limpeza:** aplicam-se as regras R01–R10. Cada registo fica `VALID`, `CORRIGIDO`, `PENDING` ou `REJECTED`. A normalização é feita em cópias de comparação; o valor original nunca se perde.
3. **Rejeição:** os registos que não podem ser corrigidos automaticamente ficam em `stg_rejections`, com a regra violada e o motivo, e **não** são carregados no Data Mart, como o enunciado exige.
4. **Carregamento:** as dimensões carregam antes do facto. Só entram registos `VALID` ou `CORRIGIDO`. O carregamento é incremental e idempotente.
5. **Frete e moeda:** o frete (que na origem está ao nível da fatura) é repartido pelas linhas e os valores são convertidos para euros durante a transformação.

**Parametrização.** O projeto SSIS não tem caminhos absolutos. O nome do servidor e da base de dados do sistema operacional, o servidor do Data Mart e da Staging (o mesmo para ambas) e os nomes das bases de dados do Data Mart e da Staging vêm de um ficheiro de parâmetros.

# Data Profiling

O *profiling* foi feito com seis *scripts* SQL sobre a `MoreRhythm` (inventário, chaves, valores em falta, duplicados de clientes, inconsistências financeiras e integridade referencial). A origem declara 16 chaves estrangeiras e os testes de integridade referencial não encontraram registos órfãos. Os problemas de completude e de consistência estão resumidos abaixo.

| Problema | Evidência | Tratamento |
|---|---|---|
| NIF de cliente em falta | 1 cliente (e 1 com `000000000`) | `N/D`; fora da deteção de duplicados |
| Zona de cliente em falta | 2 clientes | Não se infere: "Zona desconhecida" |
| Email e telemóvel em falta | 12 e 21 clientes | Mantêm-se `NULL` |
| Atributos de produto em falta | 2 designações, famílias e categorias; 12 fornecedores | Membro "Desconhecido" (descritivos) |
| Linhas de compra sem produto | 12 linhas, quantidade 319, valor 12 615,30 | Rejeitadas na Staging; fora do âmbito do data mart de vendas |
| Clientes potencialmente duplicados | Clientes 10 e 18 (mesmo NIF e nome normalizados) | Mantidos separados, em revisão |
| Linhas de fatura com `line_total` ≠ quantidade × preço | 4 linhas (2 com quantidade negativa, 2 com preço negativo) | Fatura rejeitada até confirmar a regra de sinal |
| Cabeçalho ≠ soma das linhas | 2 faturas, diferenças de +5,00 e −5,00 | Fatura rejeitada |

**Confirmado e por confirmar.** Os números acima foram confirmados por *queries* sobre a origem. A interpretação dos casos de sinal negativo (devoluções ou erro de dados) e o significado de `invoices.payment_date` (sempre preenchida, entre 03/02 e 31/12/2025 e nunca anterior à data da fatura, pelo que pode ser uma data de vencimento) dependem de confirmação do negócio e estão assinalados como decisões em aberto.

# Modelo dimensional

@@include ../modelo-dimensional/03_relatorio_seccao_modelo_dimensional.md shift=0

![Esquema em estrela do Data Mart](../modelo-dimensional/diagrama_modelo_dimensional.png)

A figura mostra a tabela de factos e as dimensões (atributos marcados com `*` têm SCD tipo 2). O dicionário completo de dados, com tipos, chaves e nulabilidade, está no Anexo B. As restrições físicas adicionais (FK composta do facto para as taxas de câmbio, vigência SCD2 e índices únicos de versão corrente) estão descritas na secção seguinte.

## Implementação física

O esquema foi implementado em SQL Server (`04_ddl_data_mart.sql`) e validado com 33 testes automáticos (chaves, restrições, tipos, calendário e SCD2), todos aprovados numa base de dados descartável. A `Dim_Data` é populada de 2020 a 2035, com feriados nacionais (incluindo os móveis, calculados a partir da Páscoa) e as taxas de câmbio EUR = 1. Os tipos das chaves de negócio coincidem com os da origem (`numeric(10,0)` para clientes e fornecedores, `numeric(6,0)` para funcionários).

# Staging Area

A Staging é a camada onde os dados são preservados, rastreados e validados antes de chegarem ao Data Mart. A estrutura mínima executável (`03_ddl_staging_area.sql`) contém:

| Tabela | Função |
|---|---|
| `stg_load_control` | Um registo por execução: origem, início e fim, contagens (extraídas, validadas, rejeitadas), estado (`RUNNING`, `SUCCEEDED`, `FAILED`) e mensagem de erro |
| `stg_raw_rows` | Cópia fiel de cada registo (`raw_row_json`) com tabela e chave de origem, instante da extração, *hash* e estado de validação |
| `stg_rejections` | Um registo por violação de regra, com os valores originais, a regra (R01–R10), a mensagem e o estado de resolução (`OPEN`, `RESOLVED`, `CANCELLED`) |
| `stg_customer_duplicate_groups` | Potenciais duplicados de clientes, com NIF e nome normalizados e estado de revisão (`PENDING_REVIEW`, `CONFIRMED`, `DISMISSED`) |
| `stg_<origem>` (12 tabelas) | Cópia tipada de cada tabela de origem, com os mesmos nomes e tipos, mais as colunas técnicas abaixo |

@@include ../mappings/source-to-staging.md from="## 9. Contrato físico" to="### 9.2" shift=0

# Mapeamentos

## Origem → Staging

A cópia é 1:1: cada tabela de origem tem a sua `stg_<origem>`, com as mesmas colunas, tipos, precisão e nulabilidade; os `NULL` mantêm-se `NULL` e nenhuma conversão é destrutiva. A tabela técnica `sysdiagrams` não é copiada. As regras de validação aplicadas na passagem para a Staging são as seguintes.

@@include ../mappings/source-to-staging.md from="### 9.2" to="### 9.3" shift=0 drop_heading=1

## Staging → Data Mart

O mapeamento seguinte indica, para cada atributo do Data Mart, a origem, as transformações e a estratégia SCD.

@@include ../mappings/04_mapeamento_staging_datamart.md shift=1

# Regras de transformação, limpeza e rejeição

@@include ../mappings/transformacoes-limpeza.md from="## 2. Regras de tratamento" to="## 3. Classificação" shift=0 drop_heading=1

Os registos são classificados como correção automática segura, atributo opcional em falta, problema por investigar ou registo rejeitado. Um atributo opcional em falta não rejeita a venda; uma chave, medida ou relação inválida rejeita-a.

@@include ../mappings/transformacoes-limpeza.md from="## 8. Contrato" shift=0

# Carga incremental

O enunciado exige que cada execução carregue só os dados novos e atualize os que mudaram.

- **Deteção de registos novos ou alterados:** as tabelas de negócio (exceto `zones` e `categories`, que não têm colunas de auditoria e são minúsculas) têm `create_*` e `last_update_*`. Cada extração lê os registos com `last_update` posterior à última carga bem-sucedida registada em `stg_load_control`. `zones` e `categories` são lidas por inteiro e comparadas por *hash*.
- **Idempotência:** `source_table + source_pk` identifica o registo lógico e `raw_row_hash` o seu conteúdo. Repetir um lote não cria nem altera nada.
- **Dimensões:** a comparação do `Hash_SCD1` e do `Hash_SCD2` com a versão corrente decide entre ignorar, atualizar (tipo 1) ou abrir uma nova versão (tipo 2).
- **Facto:** *upsert* por `BK_Linha_Fatura`. O `Hash_Linha` combina os *hashes* da linha e do cabeçalho da fatura, porque uma alteração ao custo de expedição no cabeçalho muda a alocação de todas as linhas sem alterar as linhas.
- **Limitação:** a origem não marca eliminações, pelo que os registos apagados na origem não são detetados.

# Uniformização monetária em euros

Para suportar a futura expansão para o Reino Unido, os valores monetários do facto são guardados na moeda original e em euros, juntamente com a taxa de câmbio aplicada. A taxa é a da moeda no dia da fatura (`Dim_Taxa_Cambio`, uma linha por moeda e dia); para euros é 1. Na amostra só existe a moeda `EURO` (mapeada para `EUR`); a estrutura e a moeda `GBP` já estão previstas. Sem taxa aplicável, o registo é rejeitado em vez de se usar a taxa do dia anterior. O facto tem uma chave estrangeira composta para as taxas, pelo que a base de dados impede essa situação.

# Decisões em aberto e limitações

| Ponto | Situação |
|---|---|
| Sinal das 4 linhas de fatura com quantidade ou preço negativo | Rejeitadas até o negócio confirmar se são devoluções |
| Significado de `payment_date` | Sempre preenchida; pode ser data de vencimento |
| Tabelas tipadas `stg_<origem>` | Contrato definido; a criação física é feita na 2.ª parte |
| Marca de classificação de produto vinda do *fallback* da família | A Staging deve registar a origem; o Data Mart não tem coluna para isso |
| Fornecedor da linha | Reflete `products.supplyer` à data da carga; não é historiado |
| Estações do ano | Usam datas fixas (20/03, 21/06, 23/09, 21/12) |
| Eliminações na origem | Não são detetadas |

# Anexo A — Matriz de requisitos analíticos

@@include ../modelo-dimensional/01_matriz_requisitos_analiticos.md shift=0

# Anexo B — Dicionário de dados e estratégias SCD

@@include ../modelo-dimensional/02_modelo_dimensional_dicionario_scd.md from="## 3. Dicionário" to="## 6. Clientes" shift=0
