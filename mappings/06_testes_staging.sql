/*==============================================================================
  Staging Area - More Rhythm
  Testes da estrutura fisica: tabelas, tipos, chaves, restricoes e valores por omissao
  Pre-requisitos: 03_ddl_staging_area.sql e 05_ddl_staging_tabelas_tipadas.sql
  Parametros (SQLCMD):  :setvar STG_DB MoreRhythm_STG     :setvar SRC_DB MoreRhythm
  A base de origem so e lida (INFORMATION_SCHEMA). Os dados de teste sao inseridos numa
  transacao que e revertida no fim. O resultado lista cada teste (OK / FALHOU) e o script
  termina com erro se algum falhar.
  Exemplo:
    sqlcmd -S <servidor> -E -b -v STG_DB=MoreRhythm_STG SRC_DB=MoreRhythm -i 06_testes_staging.sql
==============================================================================*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE $(STG_DB);
GO

-- variavel de tabela: nao e afetada pelo ROLLBACK dos dados de teste
DECLARE @T TABLE (Id int IDENTITY(1,1), Teste varchar(140) NOT NULL, Ok bit NOT NULL, Detalhe varchar(300) NULL);

/*------------------------ 1. Existencia das tabelas -------------------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '1.01 Existem as 12 tabelas stg_<origem>', CASE WHEN COUNT(*) = 12 THEN 1 ELSE 0 END, CONCAT('tabelas=', COUNT(*))
FROM sys.tables
WHERE name IN ('stg_categories', 'stg_customers', 'stg_employees', 'stg_families', 'stg_invoices', 'stg_invoices_lines',
               'stg_products', 'stg_purchases', 'stg_purchases_lines', 'stg_stocks_movements', 'stg_suplliers', 'stg_zones');

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.02 Existem as 4 tabelas de apoio (lotes, raw, rejeicoes, duplicados)', CASE WHEN COUNT(*) = 4 THEN 1 ELSE 0 END, CONCAT('tabelas=', COUNT(*))
FROM sys.tables
WHERE name IN ('stg_load_control', 'stg_raw_rows', 'stg_rejections', 'stg_customer_duplicate_groups');

INSERT @T (Teste, Ok, Detalhe)
SELECT '1.03 A tabela tecnica sysdiagrams nao foi copiada', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, NULL
FROM sys.tables WHERE name LIKE '%sysdiagrams%';

/*------------- 2. Colunas de negocio iguais as da origem (tipo, nulabilidade) -------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '2.01 Todas as colunas de negocio da origem existem na Staging com o mesmo tipo, tamanho e nulabilidade',
       CASE WHEN SUM(CASE WHEN d.COLUMN_NAME IS NULL THEN 1 ELSE 0 END) = 0 THEN 1 ELSE 0 END,
       CONCAT('colunas da origem=', COUNT(*), '; sem correspondencia=', SUM(CASE WHEN d.COLUMN_NAME IS NULL THEN 1 ELSE 0 END))
FROM $(SRC_DB).INFORMATION_SCHEMA.COLUMNS s
LEFT JOIN INFORMATION_SCHEMA.COLUMNS d
       ON d.TABLE_SCHEMA = 'dbo' AND d.TABLE_NAME = 'stg_' + s.TABLE_NAME AND d.COLUMN_NAME = s.COLUMN_NAME
      AND d.DATA_TYPE = s.DATA_TYPE
      AND ISNULL(d.CHARACTER_MAXIMUM_LENGTH, -1) = ISNULL(s.CHARACTER_MAXIMUM_LENGTH, -1)
      AND ISNULL(CAST(d.NUMERIC_PRECISION AS int), -1) = ISNULL(CAST(s.NUMERIC_PRECISION AS int), -1)
      AND ISNULL(CAST(d.NUMERIC_SCALE AS int), -1) = ISNULL(CAST(s.NUMERIC_SCALE AS int), -1)
      AND d.IS_NULLABLE = s.IS_NULLABLE
WHERE s.TABLE_NAME <> 'sysdiagrams';

INSERT @T (Teste, Ok, Detalhe)
SELECT '2.02 Cada tabela stg_ tem todas as colunas tecnicas do contrato',
       CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, CONCAT('tabelas incompletas=', COUNT(*))
FROM sys.tables t
WHERE t.name LIKE 'stg[_]%' AND t.name NOT IN ('stg_load_control', 'stg_raw_rows', 'stg_rejections', 'stg_customer_duplicate_groups')
  AND (SELECT COUNT(*) FROM sys.columns c WHERE c.object_id = t.object_id
       AND c.name IN ('stg_row_id', 'load_id', 'source_table', 'source_pk', 'extraction_timestamp',
                      'validation_status', 'validation_rule', 'validation_message', 'raw_row_hash')) <> 9;

INSERT @T (Teste, Ok, Detalhe)
SELECT '2.03 Tipos das colunas tecnicas (stg_row_id bigint, load_id bigint, timestamp datetime2(3), hash varbinary(32))',
       CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, CONCAT('desvios=', COUNT(*))
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name LIKE 'stg[_]%' AND t.name NOT IN ('stg_load_control', 'stg_raw_rows', 'stg_rejections', 'stg_customer_duplicate_groups')
  AND NOT (   (c.name = 'stg_row_id' AND ty.name = 'bigint')
           OR (c.name = 'load_id' AND ty.name = 'bigint')
           OR (c.name = 'extraction_timestamp' AND ty.name = 'datetime2' AND c.scale = 3)
           OR (c.name = 'raw_row_hash' AND ty.name = 'varbinary' AND c.max_length = 32)
           OR c.name NOT IN ('stg_row_id', 'load_id', 'extraction_timestamp', 'raw_row_hash'));

INSERT @T (Teste, Ok, Detalhe)
SELECT '2.04 A coluna reservada employees.[group] foi preservada',
       CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END, NULL
FROM sys.columns WHERE object_id = OBJECT_ID('dbo.stg_employees') AND name = 'group';

/*--------------------- 3. Colunas auxiliares da Staging -------------------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '3.01 Colunas auxiliares existem (frete, soma das linhas, diferenca, normalizadas, grupo de duplicados, fallback)',
       CASE WHEN COUNT(*) = 9 THEN 1 ELSE 0 END, CONCAT('encontradas=', COUNT(*), ' de 9')
FROM sys.columns c JOIN sys.tables t ON t.object_id = c.object_id
WHERE (t.name = 'stg_invoices_lines' AND c.name = 'frete_alocado')
   OR (t.name = 'stg_invoices' AND c.name IN ('line_sum', 'header_line_difference'))
   OR (t.name = 'stg_customers' AND c.name IN ('normalised_name', 'normalised_taxpayer', 'normalised_email', 'normalised_address', 'duplicate_group_id'))
   OR (t.name = 'stg_products' AND c.name = 'classification_fallback');

INSERT @T (Teste, Ok, Detalhe)
SELECT '3.02 frete_alocado, line_sum e header_line_difference sao numeric(19,6) e aceitam NULL ate serem calculados',
       CASE WHEN COUNT(*) = 3 THEN 1 ELSE 0 END, NULL
FROM sys.columns c JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id IN (OBJECT_ID('dbo.stg_invoices_lines'), OBJECT_ID('dbo.stg_invoices'))
  AND c.name IN ('frete_alocado', 'line_sum', 'header_line_difference')
  AND ty.name = 'numeric' AND c.precision = 19 AND c.scale = 6 AND c.is_nullable = 1;

/*--------------------- 4. Chaves e restricoes (catalogo) ------------------------*/
INSERT @T (Teste, Ok, Detalhe)
SELECT '4.01 As 12 tabelas tem chave primaria em stg_row_id',
       CASE WHEN COUNT(DISTINCT t.name) = 12 THEN 1 ELSE 0 END, CONCAT('tabelas=', COUNT(DISTINCT t.name))
FROM sys.key_constraints k
JOIN sys.tables t ON t.object_id = k.parent_object_id
JOIN sys.index_columns ic ON ic.object_id = k.parent_object_id AND ic.index_id = k.unique_index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE k.type = 'PK' AND c.name = 'stg_row_id' AND t.name LIKE 'stg[_]%'
  AND t.name NOT IN ('stg_load_control', 'stg_raw_rows', 'stg_rejections', 'stg_customer_duplicate_groups');

INSERT @T (Teste, Ok, Detalhe)
SELECT '4.02 As 12 tabelas tem FK de load_id para stg_load_control',
       CASE WHEN COUNT(*) = 12 THEN 1 ELSE 0 END, CONCAT('FK=', COUNT(*))
FROM sys.foreign_keys
WHERE referenced_object_id = OBJECT_ID('dbo.stg_load_control')
  AND OBJECT_NAME(parent_object_id) NOT IN ('stg_raw_rows', 'stg_rejections');

INSERT @T (Teste, Ok, Detalhe)
SELECT '4.03 As 12 tabelas tem UNIQUE (load_id, source_pk)',
       CASE WHEN COUNT(*) = 12 THEN 1 ELSE 0 END, CONCAT('UQ=', COUNT(*))
FROM sys.key_constraints WHERE type = 'UQ' AND name LIKE 'UQ[_]stg[_]%[_]load' AND name <> 'UQ_stg_raw_row_load';

INSERT @T (Teste, Ok, Detalhe)
SELECT '4.04 As 12 tabelas tem CHECK de estado, de source_table e do formato de source_pk (36 restricoes)',
       CASE WHEN COUNT(*) = 36 THEN 1 ELSE 0 END, CONCAT('CK=', COUNT(*))
FROM sys.check_constraints
WHERE (name LIKE 'CK[_]stg[_]%[_]status' OR name LIKE 'CK[_]stg[_]%[_]src' OR name LIKE 'CK[_]stg[_]%[_]pk')
  AND OBJECT_NAME(parent_object_id) NOT IN ('stg_load_control', 'stg_raw_rows', 'stg_rejections', 'stg_customer_duplicate_groups');

INSERT @T (Teste, Ok, Detalhe)
SELECT '4.05 stg_customers tem FK para stg_customer_duplicate_groups',
       CASE WHEN COUNT(*) = 1 THEN 1 ELSE 0 END, NULL
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID('dbo.stg_customers') AND referenced_object_id = OBJECT_ID('dbo.stg_customer_duplicate_groups');

/*------------------------ 5. Comportamento com dados ----------------------------*/
BEGIN TRANSACTION;

DECLARE @l1 bigint, @l2 bigint;
INSERT dbo.stg_load_control (source_system, extraction_started_at, status) VALUES (N'teste', SYSUTCDATETIME(), 'RUNNING');
SET @l1 = SCOPE_IDENTITY();
INSERT dbo.stg_load_control (source_system, extraction_started_at, status) VALUES (N'teste', SYSUTCDATETIME(), 'RUNNING');
SET @l2 = SCOPE_IDENTITY();

-- registo valido, so com o essencial: os valores por omissao devem preencher o resto
INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
VALUES (@l1, N'code=1', SYSUTCDATETIME(), 0x01, 1, 'Norte');

INSERT @T (Teste, Ok, Detalhe)
SELECT '5.01 Valores por omissao: validation_status = PENDING e source_table = zones',
       CASE WHEN validation_status = 'PENDING' AND source_table = N'zones' THEN 1 ELSE 0 END, NULL
FROM dbo.stg_zones WHERE load_id = @l1;

-- a mesma chave pode repetir-se noutro lote (historico das cargas)
BEGIN TRY
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (@l2, N'code=1', SYSUTCDATETIME(), 0x02, 1, 'Norte');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.02 A mesma chave de origem pode existir em lotes diferentes', 1, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.02 A mesma chave de origem pode existir em lotes diferentes', 0, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- mesma chave no mesmo lote
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (@l1, N'code=1', SYSUTCDATETIME(), 0x03, 1, 'Norte');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.03 UQ: a mesma chave duas vezes no mesmo lote e rejeitada', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.03 UQ: a mesma chave duas vezes no mesmo lote e rejeitada', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- estado invalido
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone, validation_status)
    VALUES (@l1, N'code=2', SYSUTCDATETIME(), 0x04, 2, 'Sul', 'PENDENTE');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.04 CK: estado de validacao fora de VALID/CORRIGIDO/PENDING/REJECTED e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.04 CK: estado de validacao fora de VALID/CORRIGIDO/PENDING/REJECTED e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- source_table errado
    INSERT dbo.stg_zones (load_id, source_table, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (@l1, N'customers', N'code=3', SYSUTCDATETIME(), 0x05, 3, 'Centro');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.05 CK: source_table diferente da tabela de origem e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.05 CK: source_table diferente da tabela de origem e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- formato da chave serializada
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (@l1, N'3', SYSUTCDATETIME(), 0x06, 3, 'Centro');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.06 CK: source_pk sem o formato coluna=valor e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.06 CK: source_pk sem o formato coluna=valor e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- lote inexistente
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (-1, N'code=4', SYSUTCDATETIME(), 0x07, 4, 'Sul');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.07 FK: registo com load_id inexistente e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.07 FK: registo com load_id inexistente e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- hash obrigatorio
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (@l1, N'code=5', SYSUTCDATETIME(), NULL, 5, 'Sul');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.08 NOT NULL: raw_row_hash e obrigatorio', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.08 NOT NULL: raw_row_hash e obrigatorio', 1, ERROR_MESSAGE()); END CATCH;

BEGIN TRY  -- chave de negocio obrigatoria
    INSERT dbo.stg_zones (load_id, source_pk, extraction_timestamp, raw_row_hash, code, zone)
    VALUES (@l1, N'code=6', SYSUTCDATETIME(), 0x08, NULL, 'Sul');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.09 NOT NULL: a chave de negocio da origem e obrigatoria', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.09 NOT NULL: a chave de negocio da origem e obrigatoria', 1, ERROR_MESSAGE()); END CATCH;

-- R05: linha de compra sem produto tem de poder ser guardada para ser rejeitada com motivo
BEGIN TRY
    INSERT dbo.stg_purchases_lines (load_id, source_pk, extraction_timestamp, raw_row_hash,
        purchase_line_stamp, purchase_stamp, document_name, document_number, document_date, product,
        quantity, unit_price, line_total, create_date, last_update_date)
    VALUES (@l1, N'purchase_line_stamp=PLTESTE1', SYSUTCDATETIME(), 0x09,
        'PLTESTE1', 'PTESTE1', 'Fatura', '1', '2025-02-01', NULL, 10, 5, 50, '2025-02-01', '2025-02-01');
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.10 R05: linha de compra com product NULL pode ser guardada na Staging', 1, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.10 R05: linha de compra com product NULL pode ser guardada na Staging', 0, ERROR_MESSAGE()); END CATCH;

-- linha de fatura: line_vat opcional na origem; frete_alocado fica NULL ate ser calculado
BEGIN TRY
    INSERT dbo.stg_invoices_lines (load_id, source_pk, extraction_timestamp, raw_row_hash,
        invoice_line_stamp_id, invoice_stamp_id, product, quantity, unit_price, line_total, line_vat,
        create_date, create_time, last_update_date, last_update_time)
    VALUES (@l1, N'invoice_line_stamp_id=LTESTE1', SYSUTCDATETIME(), 0x0A,
        'LTESTE1', 'FTESTE1', 'PRODTESTE', 2, 50, 100, NULL, '2025-03-15', '00:00', '2025-03-15', '00:00');
    INSERT @T (Teste, Ok, Detalhe)
    SELECT '5.11 Linha de fatura aceita line_vat NULL e frete_alocado fica NULL ate ao calculo', CASE WHEN frete_alocado IS NULL THEN 1 ELSE 0 END, NULL
    FROM dbo.stg_invoices_lines WHERE invoice_line_stamp_id = 'LTESTE1';
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.11 Linha de fatura aceita line_vat NULL e frete_alocado fica NULL ate ao calculo', 0, ERROR_MESSAGE()); END CATCH;

-- produto com todos os atributos opcionais em falta (como 2 produtos da amostra)
BEGIN TRY
    INSERT dbo.stg_products (load_id, source_pk, extraction_timestamp, raw_row_hash, reference)
    VALUES (@l1, N'reference=PRODTESTE', SYSUTCDATETIME(), 0x0B, 'PRODTESTE');
    INSERT @T (Teste, Ok, Detalhe)
    SELECT '5.12 Produto so com a referencia e aceite; classification_fallback = 0 por omissao', CASE WHEN classification_fallback = 0 THEN 1 ELSE 0 END, NULL
    FROM dbo.stg_products WHERE reference = 'PRODTESTE';
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.12 Produto so com a referencia e aceite; classification_fallback = 0 por omissao', 0, ERROR_MESSAGE()); END CATCH;

-- clientes: grupo de duplicados inexistente
BEGIN TRY
    INSERT dbo.stg_customers (load_id, source_pk, extraction_timestamp, raw_row_hash,
        number, name, taxpayer_number, phone, mobile, contact, email, address, clity, zip_code, zone, type,
        seller, days_pay_invoices, BBAN, segment, create_date, create_time, last_update_date, last_update_time,
        duplicate_group_id)
    VALUES (@l1, N'number=9001', SYSUTCDATETIME(), 0x0C,
        9001, 'Cliente Teste', '123456789', '', '', '', '', '', '', '', NULL, 'Empresa',
        0, 30, '', 'Retalho', '2025-01-01', '00:00', '2025-01-01', '00:00', 999999);
    INSERT @T (Teste, Ok, Detalhe) VALUES ('5.13 FK: duplicate_group_id inexistente e rejeitado', 0, NULL);
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.13 FK: duplicate_group_id inexistente e rejeitado', 1, ERROR_MESSAGE()); END CATCH;

-- clientes: zona e vazios preservados (zone NULL, texto vazio sem conversao)
BEGIN TRY
    INSERT dbo.stg_customers (load_id, source_pk, extraction_timestamp, raw_row_hash,
        number, name, taxpayer_number, phone, mobile, contact, email, address, clity, zip_code, zone, type,
        seller, days_pay_invoices, BBAN, segment, create_date, create_time, last_update_date, last_update_time)
    VALUES (@l1, N'number=9002', SYSUTCDATETIME(), 0x0D,
        9002, 'Cliente Teste 2', '000000000', '', '', '', '', '', '', '', NULL, 'Empresa',
        0, 30, '', 'Retalho', '2025-01-01', '00:00', '2025-01-01', '00:00');
    INSERT @T (Teste, Ok, Detalhe)
    SELECT '5.14 Cliente sem zona e com campos vazios e guardado sem conversao (zone NULL, email vazio)',
           CASE WHEN zone IS NULL AND email = '' THEN 1 ELSE 0 END, NULL
    FROM dbo.stg_customers WHERE number = 9002;
END TRY BEGIN CATCH INSERT @T (Teste, Ok, Detalhe) VALUES ('5.14 Cliente sem zona e com campos vazios e guardado sem conversao (zone NULL, email vazio)', 0, ERROR_MESSAGE()); END CATCH;

ROLLBACK TRANSACTION;

/*------------------------------- Resultado ---------------------------------*/
-- se um teste rebentar com erro nao regista resultado; por isso o total tambem e verificado
DECLARE @esperados int = 28;
IF (SELECT COUNT(*) FROM @T) <> @esperados
    INSERT @T (Teste, Ok, Detalhe)
    VALUES ('9.99 Numero de testes executados = esperado', 0, CONCAT('executados=', (SELECT COUNT(*) FROM @T), '; esperados=', @esperados));

SELECT Id, CASE Ok WHEN 1 THEN 'OK' ELSE 'FALHOU' END AS Resultado, Teste, Detalhe FROM @T ORDER BY Id;

DECLARE @falhas int = (SELECT COUNT(*) FROM @T WHERE Ok = 0);
DECLARE @msg nvarchar(200) = CONCAT(@falhas, ' teste(s) falharam');
IF @falhas > 0 THROW 50001, @msg, 1;
GO
