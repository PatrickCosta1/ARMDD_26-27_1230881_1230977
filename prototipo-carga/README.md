# Protótipo da carga do Data Mart (T-SQL)

Esta pasta contém a lógica da carga Staging → Data Mart escrita em T-SQL e testada com os dados reais da amostra. Serve de **evidência**
das regras descritas na secção "Processo ETL: carga do Data Mart" do relatório.

**O que é:** procedimentos que carregam as quatro dimensões (SCD1 e SCD2 por *hash*, com o cliente consolidado pelo mapa de duplicados) e
`Fact_Vendas` (chaves pela data da fatura, frete, euros e *upsert*), mais testes de reconciliação, de repetição da carga, de SCD e de duplicados.

**O que não é:** o processo em SSIS, que será construído na 2.ª parte. Em vez das tabelas `stg_<origem>` (ainda sem dados), o protótipo copia as
tabelas da `MoreRhythm` para tabelas `src_<origem>` dentro da própria base de teste e aplica as regras sobre elas. Corre **só numa base de dados
descartável**; nunca altera a `MoreRhythm` (só a lê).

## Como correr

Requisitos: SQL Server com a base `MoreRhythm` anexada e o cliente `sqlcmd`. A partir da raiz do repositório (autenticação Windows):

1. Criar o esquema do Data Mart e carregar o calendário (cria a base `MoreRhythm_DM`; use-a só para este teste):

   ```bash
   sqlcmd -S . -E -C -b -i modelo-dimensional\04_ddl_data_mart.sql
   ```

   ```bash
   sqlcmd -S . -E -C -b -v DM_DB=MoreRhythm_DM ANO_INICIO=2020 ANO_FIM=2035 -i modelo-dimensional\05_carga_dim_data_moeda.sql
   ```

2. Carregar (1.ª carga):

   ```bash
   sqlcmd -S . -E -C -b -W -v DM_DB=MoreRhythm_DM SRC_DB=MoreRhythm -i prototipo-carga\01_prototipo_carga.sql
   ```

3. Testes de reconciliação (não alteram dados):

   ```bash
   sqlcmd -S . -E -C -b -y 0 -v DM_DB=MoreRhythm_DM -i prototipo-carga\02_testes_reconciliacao.sql
   ```

4. Testes de repetição, SCD e duplicados (alteram as cópias `src_*` e voltam a carregar; correm **uma vez** por base de teste):

   ```bash
   sqlcmd -S . -E -C -b -y 0 -v DM_DB=MoreRhythm_DM -i prototipo-carga\03_testes_scd_e_duplicados.sql
   ```

5. Apagar a base de teste quando terminar:

   ```bash
   sqlcmd -S . -E -C -Q "ALTER DATABASE MoreRhythm_DM SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE MoreRhythm_DM"
   ```

## Resultado esperado

- 1.ª carga: **82 linhas inseridas** (30 das 37 faturas; ficam de fora as 7 rejeitadas por R06, R07 e R11).
- Testes `02`: **16 de 16 OK** (contagens, frete, totais, clientes consolidados, funcionários com email nulo).
- Testes `03`: **9 de 9 OK** (repetir a carga não altera nada, SCD1, SCD2 com fatura de um cliente duplicado, alteração do frete no cabeçalho).

## Ficheiros

| Ficheiro | Conteúdo |
|---|---|
| `01_prototipo_carga.sql` | Procedimentos de carga das dimensões e do facto, mapa persistente de duplicados e a 1.ª carga |
| `02_testes_reconciliacao.sql` | Reconciliação da 1.ª carga e verificação do cliente consolidado |
| `03_testes_scd_e_duplicados.sql` | Repetição, SCD1, SCD2 com duplicado, alteração do frete e integridade das versões |

## Limitações

- A deteção de duplicados usa um bloqueio por `SOUNDEX` e funções escalares só adequadas à amostra; no SSIS usa-se o *Fuzzy Grouping*.
- O reapontamento de um duplicado detetado depois da carga está especificado no relatório e **não** está implementado aqui.
