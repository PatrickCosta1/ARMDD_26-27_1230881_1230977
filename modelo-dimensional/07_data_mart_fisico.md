# 07 — Data Mart físico: instalação, validação e testes

> Responsável: Leonor (A) · Fase 2 · Esquema dimensional executável

## 1. Scripts e ordem de execução

| Ordem | Ficheiro | Função |
|---|---|---|
| 1 | [04_ddl_data_mart.sql](04_ddl_data_mart.sql) | Cria `MoreRhythm_DM`, dimensões, `Fact_Vendas`, índices, membros "Desconhecido" (SK −1) e as moedas EUR/GBP |
| 2 | [05_carga_dim_data_moeda.sql](05_carga_dim_data_moeda.sql) | Popula `Dim_Data` (2020–2035, feriados nacionais, Páscoa calculada) e `Dim_Taxa_Cambio` (EUR = 1). Idempotente |
| 3 | [06_testes_data_mart.sql](06_testes_data_mart.sql) | 33 testes de chaves, restrições, tipos, calendário e SCD2; os dados de teste são revertidos (`ROLLBACK`) |

Exemplo de execução (SQL Server, autenticação Windows). O nome da base de dados e o intervalo de anos são parâmetros SQLCMD; nada tem caminhos absolutos:

```bash
sqlcmd -S <servidor> -E -b -i 04_ddl_data_mart.sql
sqlcmd -S <servidor> -E -b -v DM_DB=MoreRhythm_DM ANO_INICIO=2020 ANO_FIM=2035 -i 05_carga_dim_data_moeda.sql
sqlcmd -S <servidor> -E -b -v DM_DB=MoreRhythm_DM -i 06_testes_data_mart.sql
```

O `04_ddl_data_mart.sql` cria `MoreRhythm_DM` por omissão; o nome é configurável no projeto SSIS (parâmetros) e, nos scripts, basta substituí-lo.

## 2. Estruturas criadas

- 5 dimensões (`Dim_Data`, `Dim_Cliente`, `Dim_Produto`, `Dim_Fornecedor`, `Dim_Funcionario`), mais `Dim_Moeda` e `Dim_Taxa_Cambio` (moeda e câmbios).
- 1 tabela de factos, `Fact_Vendas`, à granularidade de linha de fatura, com 8 chaves estrangeiras, entre elas a composta `(SK_Data_Fatura, SK_Moeda) → Dim_Taxa_Cambio`.
- Estruturas SCD: colunas de vigência (`Data_Inicio`, `Data_Fim`, `Versao_Atual`), `Hash_SCD1` e `Hash_SCD2`, índice único filtrado de versão corrente e restrição de vigência (ver [02, §5](02_modelo_dimensional_dicionario_scd.md)).
  - **SCD1:** sobrescrita da versão corrente quando muda `Hash_SCD1`.
  - **SCD2:** nova versão quando muda `Hash_SCD2`.

## 3. Alterações ao DDL na Fase 2 (e porquê)

| Alteração | Motivo |
|---|---|
| `SET QUOTED_IDENTIFIER ON` nos três scripts | Os índices filtrados falhavam (erro 1934) quando corridos por `sqlcmd`, que tem a opção desligada. O SSMS esconde o problema |
| `ID_Lote_ETL` de `int` para `bigint` | Tem de coincidir com `stg_load_control.load_id` (`bigint`) da Staging |
| `Hash_Linha` no facto | O contrato da Staging (`source-to-staging.md` §9.3) diz que o mesmo `raw_row_hash` não é reaplicado; sem a coluna não há como detetar linhas já carregadas |
| `Hash_SCD1` / `Hash_SCD2` nas dimensões | Estrutura de deteção de alterações descrita no §5 do dicionário, mas que não existia no DDL |
| Índice único `IX_Dim_*_Atual` (era não único) | Garante uma só versão corrente por chave de negócio |
| `CK_Dim_*_Vigencia` | Impede versões incoerentes (`Data_Fim < Data_Inicio`; versão fechada com `9999-12-31`; versão corrente com data de fim) |
| FK composta facto → `Dim_Taxa_Cambio` | Aplica a regra "sem taxa de câmbio, o registo é rejeitado" na própria base de dados |
| `CK_Fact_Taxa_Positiva`, `CK_Fact_Fatura_Dia` | Taxa positiva; a data da fatura é sempre uma data real |

## 4. Resultados dos testes

Executados em SQL Server local, numa base de dados descartável (criada, testada e removida). Resultado: **33 de 33 testes OK**, e a segunda execução do script 05 não duplicou linhas (5 845 datas e 5 844 taxas EUR).

| Grupo | O que valida |
|---|---|
| 1. `Dim_Data` | 5 845 linhas (2020–2035 + SK −1), sem lacunas; Páscoa de 2024, 2025 e 2026, Sexta-feira Santa e Corpo de Deus de 2025; 13 feriados nacionais em 2025; semana ISO (2025-02-03 a 02-09 é a semana 6 de 2025); ano ISO nas viragens de ano; 12 últimos dias de mês; 26 dias de fim de semana no 2.º trimestre; Primavera de 2025 com 93 dias; semestre, trimestre e quadrimestre |
| 2. Moeda | EUR e GBP existem; EUR = 1 em todos os dias; sem taxas GBP até o ETL as carregar |
| 3. SCD2 e facto | A pesquisa por data da fatura devolve a versão certa (Centro em 15/03, Norte em 01/04); uma só versão corrente; vendas por zona histórica corretas; `SK_Data_Pagamento = −1` resolve para "Sem data" |
| 4. Violações | São rejeitados: linha de fatura duplicada, FK inexistente, falta de taxa de câmbio no dia, taxa ≤ 0, data de fatura −1, duas versões correntes, vigência incoerente, `Data_Fim < Data_Inicio`, versão (BK, `Data_Inicio`) repetida, data repetida |
| 5. Tipos | Precisões e escalas da `Fact_Vendas` (iguais às da origem, `inventario.md` §7.2); 8 FK; nenhuma coluna nulável no facto |

## 5. Limitações e pontos em aberto

- As **estações do ano** usam datas fixas (20/03, 21/06, 23/09, 21/12), como no dicionário. Os equinócios e solstícios reais variam um dia entre anos; para as análises (Primavera de 2025) a diferença é nula.
- Os **feriados municipais e a Terça-feira de Carnaval** não estão em `Feriado_Nacional` (não são feriados nacionais obrigatórios).
- `Dim_Taxa_Cambio` só tem EUR. A carga de cotações GBP fica para o ETL (Fase 3), quando existir sucursal no Reino Unido.
- Os testes foram escritos contra o DDL, não contra dados reais da `MoreRhythm`. A validação com dados reais (contagens, reconciliação financeira) é da Fase 3.
- **Critério de conclusão da Fase 2 (campos da Staging ↔ requisitos do Data Mart):** `ID_Lote_ETL` e `Hash_Linha` já coincidem com `stg_load_control.load_id` e `raw_row_hash`. As tabelas tipadas `stg_<origem>` ainda não existem em [03_ddl_staging_area.sql](../mappings/03_ddl_staging_area.sql) (são do Patrick), por isso o cruzamento coluna a coluna fica pendente dessa entrega.
