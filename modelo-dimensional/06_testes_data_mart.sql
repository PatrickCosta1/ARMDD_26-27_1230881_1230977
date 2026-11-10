/*==============================================================================
  Data Mart de Vendas - More Rhythm, SA
  Testes do esquema fisico: chaves, restricoes, tipos, calendario e SCD2
  Pre-requisitos: 04_ddl_data_mart.sql e 05_carga_dim_data_moeda.sql (2020-2035)
  Parametro (SQLCMD): :setvar DM_DB MoreRhythm_DM
  Os dados de teste sao inseridos numa transacao que e revertida no fim;
  o resultado final lista cada teste (OK / FALHOU) e termina com erro se algum falhar.
==============================================================================*/
SET NOCOUNT ON;
-- indices filtrados exigem QUOTED_IDENTIFIER ON (sqlcmd/SSIS tem-no OFF por omissao)
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

GO
USE $(DM_DB);
GO

-- variavel de tabela: nao e afetada pelo ROLLBACK dos dados de teste
DECLARE @T TABLE (Id int IDENTITY(1,1), Teste varchar(120) NOT NULL, Ok bit NOT NULL, Detalhe varchar(200) NULL);

BEGIN TRANSACTION;

/*----------------------------- 1. Dim_Data ---------------------------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '1.01 Dim_Data tem 5845 linhas (2020-2035 + membro -1)', CASE WHEN COUNT(*) = 5845 THEN 1 ELSE 0 END, CONCAT('linhas=', COUNT(*)) FROM dbo.Dim_Data;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.02 Pascoa 2025 = 2025-04-20; Sexta-feira Santa = 18-04; Corpo de Deus = 19-06',
       CASE WHEN SUM(CASE WHEN (Data = '2025-04-20' AND Nome_Feriado = 'Pascoa')
                            OR (Data = '2025-04-18' AND Nome_Feriado = 'Sexta-feira Santa')
                            OR (Data = '2025-06-19' AND Nome_Feriado = 'Corpo de Deus') THEN 1 ELSE 0 END) = 3 THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Data WHERE Ano = 2025;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.03 Pascoa 2024 = 2024-03-31 e 2026 = 2026-04-05',
       CASE WHEN SUM(CASE WHEN (Data = '2024-03-31' OR Data = '2026-04-05') AND Nome_Feriado = 'Pascoa' THEN 1 ELSE 0 END) = 2 THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Data WHERE Ano IN (2024, 2026);

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.04 13 feriados nacionais em 2025', CASE WHEN COUNT(*) = 13 THEN 1 ELSE 0 END, CONCAT('feriados=', COUNT(*))
FROM dbo.Dim_Data WHERE Ano = 2025 AND Feriado_Nacional = 1;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.05 2025-02-07 e sexta-feira (ISO 5), semana 6, 1.o trimestre, 1.o quadrimestre, 1.o semestre',
       CASE WHEN Dia_Semana = 5 AND Nome_Dia_Semana = 'Sexta-feira' AND Semana_Ano = 6 AND Trimestre = 1
             AND Quadrimestre = 1 AND Semestre = 1 AND Fim_Semana = 0 AND Estacao_Ano = 'Inverno' THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Data WHERE SK_Data = 20250207;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.06 Semana 6 de 2025 vai de 2025-02-03 a 2025-02-09',
       CASE WHEN MIN(Data) = '2025-02-03' AND MAX(Data) = '2025-02-09' AND COUNT(*) = 7 THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Data WHERE Ano_Semana_ISO = 2025 AND Semana_Ano = 6;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.07 Ano ISO: 2024-12-30 pertence a 2025/S1 e 2021-01-01 a 2020/S53',
       CASE WHEN SUM(CASE WHEN (Data = '2024-12-30' AND Ano_Semana_ISO = 2025 AND Semana_Ano = 1)
                            OR (Data = '2021-01-01' AND Ano_Semana_ISO = 2020 AND Semana_Ano = 53) THEN 1 ELSE 0 END) = 2 THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Data WHERE Data IN ('2024-12-30', '2021-01-01');

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.08 Ultimo dia do mes: 12 dias em 2025 (28-02-2025 incluido)',
       CASE WHEN COUNT(*) = 12 AND SUM(CASE WHEN Data = '2025-02-28' THEN 1 ELSE 0 END) = 1 THEN 1 ELSE 0 END, CONCAT('dias=', COUNT(*))
FROM dbo.Dim_Data WHERE Ano = 2025 AND Ultimo_Dia_Mes = 1;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.09 Fins de semana do 2.o trimestre de 2025 = 26 dias',
       CASE WHEN COUNT(*) = 26 THEN 1 ELSE 0 END, CONCAT('dias=', COUNT(*))
FROM dbo.Dim_Data WHERE Ano = 2025 AND Trimestre = 2 AND Fim_Semana = 1;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.10 Estacoes 2025: Primavera 20-03 a 20-06 (93 dias)',
       CASE WHEN COUNT(*) = 93 AND MIN(Data) = '2025-03-20' AND MAX(Data) = '2025-06-20' THEN 1 ELSE 0 END, CONCAT('dias=', COUNT(*))
FROM dbo.Dim_Data WHERE Ano = 2025 AND Estacao_Ano = 'Primavera';

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.11 Sem lacunas: dias consecutivos entre 2020-01-01 e 2035-12-31',
       CASE WHEN COUNT(*) = DATEDIFF(DAY, '2020-01-01', '2035-12-31') + 1 THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Data WHERE SK_Data <> -1;

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.12 Membro -1 existe em Dim_Data e em todas as dimensoes',
       CASE WHEN (SELECT COUNT(*) FROM dbo.Dim_Data WHERE SK_Data = -1)
               + (SELECT COUNT(*) FROM dbo.Dim_Cliente WHERE SK_Cliente = -1)
               + (SELECT COUNT(*) FROM dbo.Dim_Produto WHERE SK_Produto = -1)
               + (SELECT COUNT(*) FROM dbo.Dim_Fornecedor WHERE SK_Fornecedor = -1)
               + (SELECT COUNT(*) FROM dbo.Dim_Funcionario WHERE SK_Funcionario = -1) = 5 THEN 1 ELSE 0 END, NULL;

/*----------------------------- 2. Moeda / taxas ----------------------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '2.01 Dim_Moeda: EUR e GBP', CASE WHEN COUNT(*) = 2 THEN 1 ELSE 0 END, NULL FROM dbo.Dim_Moeda WHERE Codigo_ISO IN ('EUR', 'GBP');

INSERT @T (Teste, Ok, Detalhe)
SELECT '2.02 Taxa EUR = 1 em todos os dias do calendario',
       CASE WHEN COUNT(*) = 5844 AND MIN(t.Taxa_Para_EUR) = 1 AND MAX(t.Taxa_Para_EUR) = 1 THEN 1 ELSE 0 END, CONCAT('taxas=', COUNT(*))
FROM dbo.Dim_Taxa_Cambio t JOIN dbo.Dim_Moeda m ON m.SK_Moeda = t.SK_Moeda WHERE m.Codigo_ISO = 'EUR';

INSERT @T (Teste, Ok, Detalhe)
SELECT '2.03 Nao ha taxas GBP ate o ETL as carregar', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Taxa_Cambio t JOIN dbo.Dim_Moeda m ON m.SK_Moeda = t.SK_Moeda WHERE m.Codigo_ISO = 'GBP';

/*----------------------- 3. Dados de teste (revertidos) --------------------*/
DECLARE @eur smallint = (SELECT SK_Moeda FROM dbo.Dim_Moeda WHERE Codigo_ISO = 'EUR');
DECLARE @gbp smallint = (SELECT SK_Moeda FROM dbo.Dim_Moeda WHERE Codigo_ISO = 'GBP');
DECLARE @h binary(32) = 0x01;

-- Cliente 9001: versao 1 (Centro) ate 2025-03-31, versao 2 (Norte) a partir de 2025-04-01 (SCD2)
INSERT dbo.Dim_Cliente (BK_Cliente, Nome, NIF, Cidade, Zona, Pais, Tipo_Cliente, Segmento, Data_Inicio, Data_Fim, Versao_Atual,
                        Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
VALUES (9001, N'Cliente Teste', '999999990', N'Coimbra', N'Centro', N'Portugal', N'Revendedor', N'Alto',
        '1900-01-01', '2025-03-31', 0, '2025-01-01', '2025-01-01', 0x01, 0x01);
INSERT dbo.Dim_Cliente (BK_Cliente, Nome, NIF, Cidade, Zona, Pais, Tipo_Cliente, Segmento, Data_Inicio, Data_Fim, Versao_Atual,
                        Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
VALUES (9001, N'Cliente Teste', '999999990', N'Porto', N'Norte', N'Portugal', N'Revendedor', N'Alto',
        '2025-04-01', '9999-12-31', 1, '2025-01-01', '2025-04-01', 0x01, 0x02);

INSERT dbo.Dim_Produto (BK_Produto, Designacao, BK_Familia, Familia, BK_Categoria, Categoria, Taxa_IVA, Data_Inicio, Data_Fim, Versao_Atual,
                        Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
VALUES ('PRODTESTE', N'Produto Teste', 'FAMTESTE', N'Teclados', 1, N'Cordas', 23.00, '1900-01-01', '9999-12-31', 1, '2025-01-01', '2025-01-01', 0x01, 0x01);

INSERT dbo.Dim_Fornecedor (BK_Fornecedor, Nome, NIF, Tipo_Fornecedor, Cidade, Zona, Data_Inicio, Data_Fim, Versao_Atual,
                           Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
VALUES (9002, N'Fornecedor Teste', '999999991', N'Material', N'Lisboa', N'Sul', '1900-01-01', '9999-12-31', 1, '2025-01-01', '2025-01-01', 0x01, 0x01);

INSERT dbo.Dim_Funcionario (BK_Funcionario, Codigo, Nome, Email, Grupo, Departamento, Data_Inicio, Data_Fim, Versao_Atual,
                            Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
VALUES (90, 'teste', N'Func Teste', 'teste@teste.pt', N'Vendedor', N'Armazenagem', '1900-01-01', '9999-12-31', 1, '2025-01-01', '2025-01-01', 0x01, 0x01);

DECLARE @sk_prod int = (SELECT SK_Produto FROM dbo.Dim_Produto WHERE BK_Produto = 'PRODTESTE');
DECLARE @sk_forn int = (SELECT SK_Fornecedor FROM dbo.Dim_Fornecedor WHERE BK_Fornecedor = 9002);
DECLARE @sk_func int = (SELECT SK_Funcionario FROM dbo.Dim_Funcionario WHERE BK_Funcionario = 90);

/* SCD2: a pesquisa da SK pela data da fatura devolve a versao vigente nessa data */
INSERT @T (Teste, Ok, Detalhe)
SELECT '3.01 SCD2: fatura de 2025-03-15 resolve a versao 1 (Centro)',
       CASE WHEN COUNT(*) = 1 AND MAX(Zona) = N'Centro' THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Cliente WHERE BK_Cliente = 9001 AND '2025-03-15' BETWEEN Data_Inicio AND Data_Fim;

INSERT @T (Teste, Ok, Detalhe)
SELECT '3.02 SCD2: fatura de 2025-04-01 resolve a versao 2 (Norte), sem sobreposicao',
       CASE WHEN COUNT(*) = 1 AND MAX(Zona) = N'Norte' THEN 1 ELSE 0 END, NULL
FROM dbo.Dim_Cliente WHERE BK_Cliente = 9001 AND '2025-04-01' BETWEEN Data_Inicio AND Data_Fim;

INSERT @T (Teste, Ok, Detalhe)
SELECT '3.03 SCD2: so uma versao corrente por BK',
       CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END, NULL FROM dbo.Dim_Cliente WHERE BK_Cliente = 9001 AND Versao_Atual = 1;

DECLARE @sk_cli1 int = (SELECT SK_Cliente FROM dbo.Dim_Cliente WHERE BK_Cliente = 9001 AND Versao_Atual = 0);
DECLARE @sk_cli2 int = (SELECT SK_Cliente FROM dbo.Dim_Cliente WHERE BK_Cliente = 9001 AND Versao_Atual = 1);

/* Facto: inserir duas linhas (cada uma aponta para a sua versao do cliente) */
INSERT dbo.Fact_Vendas (SK_Data_Fatura, SK_Data_Pagamento, SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda,
                        Numero_Fatura, BK_Linha_Fatura, BK_Cliente_Origem, Quantidade, Preco_Unitario, Valor_Liquido, Valor_IVA, Frete_Alocado,
                        Taxa_Cambio, Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR,
                        Data_Criacao_Origem, Data_Atualizacao_Origem, ID_Lote_ETL, Hash_Linha)
VALUES (20250315, -1, @sk_cli1, @sk_prod, @sk_forn, @sk_func, @eur, 'FATTESTE1', 'LINHATESTE1', 9001, 2, 50, 100, 23, 3, 1, 100, 23, 3,
        '2025-03-15', '2025-03-15', 1, 0x0A),
       (20250415, 20250501, @sk_cli2, @sk_prod, @sk_forn, @sk_func, @eur, 'FATTESTE2', 'LINHATESTE2', 9001, 1, 80, 80, 18.4, 2.5, 1, 80, 18.4, 2.5,
        '2025-04-15', '2025-04-15', 1, 0x0B);

INSERT @T (Teste, Ok, Detalhe)
SELECT '3.04 Facto: 2 linhas inseridas, vendas por zona historica corretas (Centro=100, Norte=80)',
       CASE WHEN SUM(CASE WHEN c.Zona = N'Centro' AND f.Valor_Liquido = 100 THEN 1 ELSE 0 END) = 1
             AND SUM(CASE WHEN c.Zona = N'Norte' AND f.Valor_Liquido = 80 THEN 1 ELSE 0 END) = 1 THEN 1 ELSE 0 END, NULL
FROM dbo.Fact_Vendas f JOIN dbo.Dim_Cliente c ON c.SK_Cliente = f.SK_Cliente WHERE f.BK_Linha_Fatura IN ('LINHATESTE1', 'LINHATESTE2');

INSERT @T (Teste, Ok, Detalhe)
SELECT '3.05 Facto: SK_Data_Pagamento = -1 resolve para "Sem data"',
       CASE WHEN d.Nome_Dia_Semana = 'Sem data' THEN 1 ELSE 0 END, NULL
FROM dbo.Fact_Vendas f JOIN dbo.Dim_Data d ON d.SK_Data = f.SK_Data_Pagamento WHERE f.BK_Linha_Fatura = 'LINHATESTE1';

/*------------------- 4. Violacoes que tem de ser rejeitadas ----------------*/
-- cada bloco deve gerar erro; se nao gerar, o teste falha

BEGIN TRY  -- BK de linha duplicada
    INSERT dbo.Fact_Vendas (SK_Data_Fatura, SK_Data_Pagamento, SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda,
        Numero_Fatura, BK_Linha_Fatura, BK_Cliente_Origem, Quantidade, Preco_Unitario, Valor_Liquido, Valor_IVA, Frete_Alocado, Taxa_Cambio,
        Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR, Data_Criacao_Origem, Data_Atualizacao_Origem, ID_Lote_ETL, Hash_Linha)
    VALUES (20250315, -1, @sk_cli1, @sk_prod, @sk_forn, @sk_func, @eur, 'FATTESTE1', 'LINHATESTE1', 9001, 1, 1, 1, 0, 0, 1, 1, 0, 0, '2025-03-15', '2025-03-15', 1, 0x0C);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.01 UQ: BK_Linha_Fatura duplicada e rejeitada', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.01 UQ: BK_Linha_Fatura duplicada e rejeitada', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- FK: cliente inexistente
    INSERT dbo.Fact_Vendas (SK_Data_Fatura, SK_Data_Pagamento, SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda,
        Numero_Fatura, BK_Linha_Fatura, BK_Cliente_Origem, Quantidade, Preco_Unitario, Valor_Liquido, Valor_IVA, Frete_Alocado, Taxa_Cambio,
        Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR, Data_Criacao_Origem, Data_Atualizacao_Origem, ID_Lote_ETL, Hash_Linha)
    VALUES (20250315, -1, 99999999, @sk_prod, @sk_forn, @sk_func, @eur, 'FATX', 'LINHAX', 9001, 1, 1, 1, 0, 0, 1, 1, 0, 0, '2025-03-15', '2025-03-15', 1, 0x0C);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.02 FK: cliente inexistente e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.02 FK: cliente inexistente e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- sem taxa de cambio no dia (GBP) -> FK composta
    INSERT dbo.Fact_Vendas (SK_Data_Fatura, SK_Data_Pagamento, SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda,
        Numero_Fatura, BK_Linha_Fatura, BK_Cliente_Origem, Quantidade, Preco_Unitario, Valor_Liquido, Valor_IVA, Frete_Alocado, Taxa_Cambio,
        Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR, Data_Criacao_Origem, Data_Atualizacao_Origem, ID_Lote_ETL, Hash_Linha)
    VALUES (20250315, -1, @sk_cli1, @sk_prod, @sk_forn, @sk_func, @gbp, 'FATX', 'LINHAX2', 9001, 1, 1, 1, 0, 0, 1.17, 1.17, 0, 0, '2025-03-15', '2025-03-15', 1, 0x0C);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.03 FK composta: facto GBP sem taxa nesse dia e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.03 FK composta: facto GBP sem taxa nesse dia e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- taxa nao positiva
    INSERT dbo.Dim_Taxa_Cambio (SK_Data, SK_Moeda, Taxa_Para_EUR) VALUES (20250315, @gbp, 0);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.04 CK: taxa de cambio <= 0 e rejeitada', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.04 CK: taxa de cambio <= 0 e rejeitada', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- facto sem data de fatura
    INSERT dbo.Fact_Vendas (SK_Data_Fatura, SK_Data_Pagamento, SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda,
        Numero_Fatura, BK_Linha_Fatura, BK_Cliente_Origem, Quantidade, Preco_Unitario, Valor_Liquido, Valor_IVA, Frete_Alocado, Taxa_Cambio,
        Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR, Data_Criacao_Origem, Data_Atualizacao_Origem, ID_Lote_ETL, Hash_Linha)
    VALUES (-1, -1, @sk_cli1, @sk_prod, @sk_forn, @sk_func, @eur, 'FATX', 'LINHAX3', 9001, 1, 1, 1, 0, 0, 1, 1, 0, 0, '2025-03-15', '2025-03-15', 1, 0x0C);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.05 CK: SK_Data_Fatura = -1 e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.05 CK: SK_Data_Fatura = -1 e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- segunda versao corrente do mesmo cliente
    INSERT dbo.Dim_Cliente (BK_Cliente, Nome, NIF, Cidade, Zona, Pais, Tipo_Cliente, Segmento, Data_Inicio, Data_Fim, Versao_Atual,
                            Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
    VALUES (9001, N'Cliente Teste', '999999990', N'Faro', N'Sul', N'Portugal', N'Revendedor', N'Alto', '2025-06-01', '9999-12-31', 1, '2025-06-01', '2025-06-01', 0x01, 0x03);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.06 Indice unico: duas versoes correntes do mesmo BK e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.06 Indice unico: duas versoes correntes do mesmo BK e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- vigencia incoerente: versao fechada com Data_Fim = 9999
    INSERT dbo.Dim_Cliente (BK_Cliente, Nome, NIF, Cidade, Zona, Pais, Tipo_Cliente, Segmento, Data_Inicio, Data_Fim, Versao_Atual,
                            Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
    VALUES (9003, N'Cliente Teste 3', '999999992', N'Faro', N'Sul', N'Portugal', N'Revendedor', N'Alto', '2025-06-01', '9999-12-31', 0, '2025-06-01', '2025-06-01', 0x01, 0x03);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.07 CK: versao nao corrente com Data_Fim = 9999-12-31 e rejeitada', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.07 CK: versao nao corrente com Data_Fim = 9999-12-31 e rejeitada', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- Data_Fim anterior a Data_Inicio
    INSERT dbo.Dim_Cliente (BK_Cliente, Nome, NIF, Cidade, Zona, Pais, Tipo_Cliente, Segmento, Data_Inicio, Data_Fim, Versao_Atual,
                            Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
    VALUES (9004, N'Cliente Teste 4', '999999993', N'Faro', N'Sul', N'Portugal', N'Revendedor', N'Alto', '2025-06-01', '2025-05-01', 0, '2025-06-01', '2025-06-01', 0x01, 0x03);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.08 CK: Data_Fim < Data_Inicio e rejeitada', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.08 CK: Data_Fim < Data_Inicio e rejeitada', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- mesma versao (BK, Data_Inicio) duas vezes
    INSERT dbo.Dim_Produto (BK_Produto, Designacao, BK_Familia, Familia, BK_Categoria, Categoria, Data_Inicio, Data_Fim, Versao_Atual,
                            Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
    VALUES ('PRODTESTE', N'Outro', 'FAMTESTE', N'Teclados', 1, N'Cordas', '1900-01-01', '2025-01-01', 0, '2025-01-01', '2025-01-01', 0x01, 0x01);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.09 UQ: (BK, Data_Inicio) duplicado e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.09 UQ: (BK, Data_Inicio) duplicado e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- Dim_Data: data duplicada com outra SK
    INSERT dbo.Dim_Data (SK_Data, Data, Dia_Mes, Dia_Ano, Dia_Semana, Nome_Dia_Semana, Fim_Semana, Ultimo_Dia_Mes, Semana_Ano, Ano_Semana_ISO,
                         Mes, Nome_Mes, Ano_Mes, Trimestre, Quadrimestre, Semestre, Estacao_Ano, Ano, Feriado_Nacional)
    VALUES (1, '2025-03-15', 15, 74, 6, 'Sabado', 1, 0, 11, 2025, 3, 'Marco', 202503, 1, 1, 1, 'Primavera', 2025, 0);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('4.10 UQ: Dim_Data com Data repetida e rejeitada', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('4.10 UQ: Dim_Data com Data repetida e rejeitada', 1, ERROR_MESSAGE()); END CATCH;

/*------------------------- 5. Tipos e precisao -----------------------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '5.01 Tipos da Fact_Vendas: Quantidade decimal(14,4), valores decimal(19,6), taxa decimal(18,8), lote bigint',
       CASE WHEN SUM(CASE WHEN (COLUMN_NAME = 'Quantidade' AND DATA_TYPE = 'decimal' AND NUMERIC_PRECISION = 14 AND NUMERIC_SCALE = 4)
                           OR (COLUMN_NAME IN ('Valor_Liquido', 'Valor_IVA', 'Frete_Alocado', 'Valor_Liquido_EUR', 'Valor_IVA_EUR', 'Frete_Alocado_EUR', 'Preco_Unitario')
                               AND DATA_TYPE = 'decimal' AND NUMERIC_PRECISION = 19 AND NUMERIC_SCALE = 6)
                           OR (COLUMN_NAME = 'Taxa_Cambio' AND DATA_TYPE = 'decimal' AND NUMERIC_PRECISION = 18 AND NUMERIC_SCALE = 8)
                           OR (COLUMN_NAME = 'ID_Lote_ETL' AND DATA_TYPE = 'bigint') THEN 1 ELSE 0 END) = 10 THEN 1 ELSE 0 END, NULL
FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Fact_Vendas';

INSERT @T (Teste, Ok, Detalhe)
SELECT '5.02 Todas as FK do facto apontam para dimensoes (8 FK)', CASE WHEN COUNT(*) = 8 THEN 1 ELSE 0 END, CONCAT('fk=', COUNT(*))
FROM sys.foreign_keys WHERE parent_object_id = OBJECT_ID('dbo.Fact_Vendas');

INSERT @T (Teste, Ok, Detalhe)
SELECT '5.03 Nenhuma coluna SK_/BK_ do facto aceita NULL',
       CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, NULL
FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Fact_Vendas' AND IS_NULLABLE = 'YES';

BEGIN TRY  -- email invalido de funcionario (por exemplo dois @) e carregado como NULL (R02)
    INSERT dbo.Dim_Funcionario (BK_Funcionario, Codigo, Nome, Email, Grupo, Departamento, Data_Inicio, Data_Fim, Versao_Atual,
                                Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
    VALUES (91, 'teste2', N'Func Sem Email', NULL, N'Vendedor', N'Armazenagem', '1900-01-01', '9999-12-31', 1, '2025-01-01', '2025-01-01', 0x01, 0x01);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.04 Dim_Funcionario aceita Email NULL (email invalido tratado como ausente)', 1, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.04 Dim_Funcionario aceita Email NULL (email invalido tratado como ausente)', 0, ERROR_MESSAGE()); END CATCH;

ROLLBACK TRANSACTION;

/*------------------------------- Resultado ---------------------------------*/
SELECT Id, CASE Ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS Resultado, Teste, Detalhe FROM @T ORDER BY Id;

DECLARE @falhas int = (SELECT COUNT(*) FROM @T WHERE Ok = 0);
DECLARE @msg nvarchar(200) = CONCAT(@falhas, ' teste(s) falharam');
IF @falhas > 0 THROW 50001, @msg, 1;
GO
