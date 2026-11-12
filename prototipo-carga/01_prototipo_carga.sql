/*==============================================================================
  PROTOTIPO da carga Staging -> Data Mart. Valida a logica da carga em T-SQL com dados reais; NAO e o ETL em SSIS
  e so deve correr numa base descartavel.
  Objetivo: validar o desenho da carga com dados reais antes de o especificar.
  Em vez das tabelas stg_<origem> (ainda sem dados) le copias src_<origem> da
  MoreRhythm; as regras e as consultas sao as que o ETL aplicaria sobre a Staging.
  Pre-requisitos na base $(DM_DB): 04_ddl_data_mart.sql e 05_carga_dim_data_moeda.sql.
  Parametros SQLCMD: DM_DB (data mart de teste) e SRC_DB (MoreRhythm).
==============================================================================*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE $(DM_DB);
GO

-- Extensao proposta ao DDL: cliente de origem no facto (rastreabilidade e remapeamento)
IF COL_LENGTH('dbo.Fact_Vendas', 'BK_Cliente_Origem') IS NULL
    ALTER TABLE dbo.Fact_Vendas ADD BK_Cliente_Origem numeric(10,0) NULL;
GO

/*------------------------ copias da origem (= Staging) ---------------------*/
DROP TABLE IF EXISTS dbo.src_customers, dbo.src_products, dbo.src_families, dbo.src_categories, dbo.src_suplliers,
                     dbo.src_employees, dbo.src_zones, dbo.src_invoices, dbo.src_invoices_lines, dbo.map_cliente;
SELECT * INTO dbo.src_customers FROM $(SRC_DB).dbo.customers;
SELECT * INTO dbo.src_products FROM $(SRC_DB).dbo.products;
SELECT * INTO dbo.src_families FROM $(SRC_DB).dbo.families;
SELECT * INTO dbo.src_categories FROM $(SRC_DB).dbo.categories;
SELECT * INTO dbo.src_suplliers FROM $(SRC_DB).dbo.suplliers;
SELECT * INTO dbo.src_employees FROM $(SRC_DB).dbo.employees;
SELECT * INTO dbo.src_zones FROM $(SRC_DB).dbo.zones;
SELECT * INTO dbo.src_invoices FROM $(SRC_DB).dbo.invoices;
SELECT * INTO dbo.src_invoices_lines FROM $(SRC_DB).dbo.invoices_lines;
CREATE TABLE dbo.map_cliente (origem numeric(10,0) NOT NULL PRIMARY KEY, sobrevivente numeric(10,0) NOT NULL, regra varchar(40) NOT NULL);
GO

/*------------------------------ funcoes auxiliares -------------------------*/
CREATE OR ALTER FUNCTION dbo.fn_nif(@x varchar(20)) RETURNS varchar(20) AS
BEGIN   -- NIF normalizado; 'N/D' se vazio ou so zeros
    DECLARE @n varchar(20) = REPLACE(REPLACE(LTRIM(RTRIM(@x)), ' ', ''), '.', '');
    RETURN CASE WHEN @n = '' OR REPLACE(@n, '0', '') = '' THEN 'N/D' ELSE @n END;
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_upd(@d date, @t time) RETURNS datetime2(0) AS
BEGIN
    RETURN DATEADD(SECOND, DATEDIFF(SECOND, CAST('00:00' AS time), @t), CAST(@d AS datetime2(0)));
END;
GO

/*------------------- 1. mapa de clientes duplicados (persistente) -----------
  Criterio do Patrick (transformacoes-limpeza.md, 4.2): semelhanca do nome (1 - Levenshtein / maior
  comprimento) >= 0,80 e >= 2 atributos corroborantes de 6: mesmo codigo postal; semelhanca da
  morada >= 0,80; mesmo telefone ou telemovel; mesmo email valido; mesmo BBAN; NIF validos com
  distancia de Levenshtein <= 2. Sobrevivente: atualizacao mais recente (empate: menor numero).
  O mapa e persistente: so se avaliam pares em que ambos os clientes ainda nao tem decisao.
  Prototipo: usa um bloqueio por SOUNDEX para limitar os pares comparados; no SSIS e o Fuzzy Grouping. */
CREATE OR ALTER FUNCTION dbo.fn_lev(@s nvarchar(200), @t nvarchar(200)) RETURNS int AS
BEGIN
    DECLARE @sl int = LEN(@s), @tl int = LEN(@t), @i int, @j int, @c int, @a int, @b int, @d int;
    IF @sl = 0 RETURN @tl;
    IF @tl = 0 RETURN @sl;
    DECLARE @m TABLE (i int, j int, v int, PRIMARY KEY (i, j));
    SET @i = 0; WHILE @i <= @sl BEGIN INSERT @m VALUES (@i, 0, @i); SET @i += 1; END;
    SET @j = 1; WHILE @j <= @tl BEGIN INSERT @m VALUES (0, @j, @j); SET @j += 1; END;
    SET @i = 1;
    WHILE @i <= @sl BEGIN
        SET @j = 1;
        WHILE @j <= @tl BEGIN
            SET @c = CASE WHEN SUBSTRING(@s, @i, 1) = SUBSTRING(@t, @j, 1) THEN 0 ELSE 1 END;
            SELECT @a = v FROM @m WHERE i = @i - 1 AND j = @j;
            SELECT @b = v FROM @m WHERE i = @i AND j = @j - 1;
            SELECT @d = v FROM @m WHERE i = @i - 1 AND j = @j - 1;
            INSERT @m VALUES (@i, @j, (SELECT MIN(x) FROM (VALUES (@a + 1), (@b + 1), (@d + @c)) q(x)));
            SET @j += 1;
        END;
        SET @i += 1;
    END;
    RETURN (SELECT v FROM @m WHERE i = @sl AND j = @tl);
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_sim(@a nvarchar(200), @b nvarchar(200)) RETURNS decimal(4,3) AS
BEGIN
    DECLARE @mx int = IIF(LEN(@a) > LEN(@b), LEN(@a), LEN(@b));
    RETURN IIF(@mx = 0, 1, 1.0 - CAST(dbo.fn_lev(@a, @b) AS decimal(9,4)) / @mx);
END;
GO
CREATE OR ALTER FUNCTION dbo.fn_norm(@x varchar(100)) RETURNS varchar(100) AS
BEGIN   -- maiusculas, sem acentos nem pontuacao, sem LDA/SA; "R " inicial -> "RUA "
    DECLARE @n varchar(100) = UPPER(LTRIM(RTRIM(@x))) COLLATE SQL_Latin1_General_Cp1251_CS_AS;
    SET @n = REPLACE(REPLACE(REPLACE(REPLACE(@n, '.', ''), ',', ''), '-', ''), '  ', ' ');
    IF @n LIKE 'R %' SET @n = 'RUA ' + SUBSTRING(@n, 3, 100);
    IF @n LIKE '% LDA' SET @n = LEFT(@n, LEN(@n) - 4);
    IF @n LIKE '% SA' SET @n = LEFT(@n, LEN(@n) - 3);
    RETURN LTRIM(RTRIM(@n));
END;
GO
CREATE OR ALTER PROCEDURE dbo.usp_map_clientes AS
BEGIN
    INSERT dbo.map_cliente (origem, sobrevivente, regra)
    SELECT c.number, c.number, 'SOBREVIVENTE' FROM dbo.src_customers c
    WHERE NOT EXISTS (SELECT 1 FROM dbo.map_cliente m WHERE m.origem = c.number);

    DROP TABLE IF EXISTS #c, #par;
    SELECT c.number n, dbo.fn_norm(c.name) nome, dbo.fn_norm(c.address) morada, dbo.fn_nif(c.taxpayer_number) nif,
           LTRIM(RTRIM(c.zip_code)) cp, NULLIF(LTRIM(RTRIM(c.phone)), '') tel, NULLIF(LTRIM(RTRIM(c.mobile)), '') mob,
           CASE WHEN c.email LIKE '%_@_%._%' AND c.email NOT LIKE '% %' THEN LOWER(LTRIM(RTRIM(c.email))) END email,
           NULLIF(LTRIM(RTRIM(c.BBAN)), '') bban, dbo.fn_upd(c.last_update_date, c.last_update_time) upd
    INTO #c FROM dbo.src_customers c JOIN dbo.map_cliente m ON m.origem = c.number AND m.sobrevivente = c.number;  -- so clientes sem decisao

    SELECT a.n n1, b.n n2, dbo.fn_sim(a.nome, b.nome) sim_nome, a.upd u1, b.upd u2,
           (CASE WHEN a.cp <> '' AND a.cp = b.cp THEN 1 ELSE 0 END)
         + (CASE WHEN a.tel = b.tel OR a.mob = b.mob THEN 1 ELSE 0 END)
         + (CASE WHEN a.email IS NOT NULL AND a.email = b.email THEN 1 ELSE 0 END)
         + (CASE WHEN a.bban IS NOT NULL AND a.bban = b.bban THEN 1 ELSE 0 END)
         + (CASE WHEN dbo.fn_sim(a.morada, b.morada) >= 0.80 THEN 1 ELSE 0 END)
         + (CASE WHEN a.nif <> 'N/D' AND b.nif <> 'N/D' AND LEN(a.nif) = 9 AND LEN(b.nif) = 9 AND dbo.fn_lev(a.nif, b.nif) <= 2 THEN 1 ELSE 0 END) AS corrob
    INTO #par FROM #c a JOIN #c b ON a.n < b.n
    WHERE DIFFERENCE(a.nome, b.nome) >= 3;                      -- bloqueio (so no prototipo)

    UPDATE m SET sobrevivente = x.novo, regra = 'NOME>=0.80+2CORROB'
    FROM dbo.map_cliente m
    JOIN (SELECT CASE WHEN u1 > u2 OR (u1 = u2 AND n1 < n2) THEN n2 ELSE n1 END AS velho,
                 CASE WHEN u1 > u2 OR (u1 = u2 AND n1 < n2) THEN n1 ELSE n2 END AS novo
          FROM #par WHERE sim_nome >= 0.80 AND corrob >= 2) x ON x.velho = m.origem;
END;
GO

/*--------------------- 2. SCD generico (tipo 1 + tipo 2) --------------------
  Espera #n com: BK, <colunas>, Hash_SCD1, Hash_SCD2, Data_Criacao_Origem, Data_Atualizacao_Origem. */
CREATE OR ALTER PROCEDURE dbo.usp_scd
    @dim sysname, @bk sysname, @sk sysname, @colunas nvarchar(max), @colunas_scd1 nvarchar(max)
AS
BEGIN
    DECLARE @sql nvarchar(max), @set1 nvarchar(max), @lista nvarchar(max), @sel nvarchar(max);
    SELECT @set1 = STRING_AGG('d.' + QUOTENAME(LTRIM(value)) + ' = n.' + QUOTENAME(LTRIM(value)), ', ')
      FROM STRING_SPLIT(@colunas_scd1, ',');
    SELECT @lista = STRING_AGG(QUOTENAME(LTRIM(value)), ', '), @sel = STRING_AGG('n.' + QUOTENAME(LTRIM(value)), ', ')
      FROM STRING_SPLIT(@colunas, ',');

    -- (a) alteracao SCD1: atualiza todas as versoes do BK
    SET @sql = N'UPDATE d SET ' + @set1 + N', d.Hash_SCD1 = n.Hash_SCD1, d.Data_Atualizacao_Origem = n.Data_Atualizacao_Origem
        FROM dbo.' + QUOTENAME(@dim) + N' d JOIN #n n ON n.BK = d.' + QUOTENAME(@bk) + N' WHERE d.' + QUOTENAME(@sk) + N' > 0 AND d.Hash_SCD1 <> n.Hash_SCD1;';
    EXEC (@sql);

    -- (b) alteracao SCD2: calcula inicio da nova versao e fecha a corrente
    DROP TABLE IF EXISTS #chg;
    CREATE TABLE #chg (BK sql_variant NOT NULL, novo_inicio date NOT NULL);
    SET @sql = N'INSERT #chg (BK, novo_inicio)
        SELECT n.BK, CASE WHEN CAST(n.Data_Atualizacao_Origem AS date) > d.Data_Inicio
                          THEN CAST(n.Data_Atualizacao_Origem AS date) ELSE DATEADD(DAY, 1, d.Data_Inicio) END
        FROM #n n JOIN dbo.' + QUOTENAME(@dim) + N' d ON d.' + QUOTENAME(@bk) + N' = n.BK AND d.Versao_Atual = 1
        WHERE d.Hash_SCD2 <> n.Hash_SCD2;
        UPDATE d SET d.Data_Fim = DATEADD(DAY, -1, c.novo_inicio), d.Versao_Atual = 0
        FROM dbo.' + QUOTENAME(@dim) + N' d JOIN #chg c ON c.BK = d.' + QUOTENAME(@bk) + N' WHERE d.Versao_Atual = 1;';
    EXEC (@sql);

    -- (c) insere BK novos (inicio 1900-01-01) e novas versoes
    SET @sql = N'INSERT dbo.' + QUOTENAME(@dim) + N' (' + QUOTENAME(@bk) + N', ' + @lista + N', Data_Inicio, Data_Fim, Versao_Atual,
            Data_Criacao_Origem, Data_Atualizacao_Origem, Hash_SCD1, Hash_SCD2)
        SELECT n.BK, ' + @sel + N', ISNULL(c.novo_inicio, ''1900-01-01''), ''9999-12-31'', 1,
               n.Data_Criacao_Origem, n.Data_Atualizacao_Origem, n.Hash_SCD1, n.Hash_SCD2
        FROM #n n LEFT JOIN #chg c ON c.BK = n.BK
        WHERE c.BK IS NOT NULL OR NOT EXISTS (SELECT 1 FROM dbo.' + QUOTENAME(@dim) + N' d WHERE d.' + QUOTENAME(@bk) + N' = n.BK);';
    EXEC (@sql);
END;
GO

/*------------------------------ 3. Dim_Cliente -----------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_load_dim_cliente AS
BEGIN
    EXEC dbo.usp_map_clientes;
    DROP TABLE IF EXISTS #n;
    ;WITH base AS (
        SELECT c.number BK, c.*, dbo.fn_upd(c.last_update_date, c.last_update_time) upd
        FROM dbo.src_customers c JOIN dbo.map_cliente m ON m.origem = c.number AND m.sobrevivente = c.number
        WHERE c.zone IS NOT NULL)                       -- sem zona: rejeitado (nao se infere)
    SELECT b.BK,
        CAST(LTRIM(RTRIM(b.name)) AS nvarchar(55)) AS Nome,
        dbo.fn_nif(b.taxpayer_number) AS NIF,
        CAST(NULLIF(LTRIM(RTRIM(b.contact)), '') AS nvarchar(30)) AS Contacto,
        em.v AS Email, ph.v AS Telefone, mo.v AS Telemovel,
        CAST(NULLIF(LTRIM(RTRIM(b.address)), '') AS nvarchar(55)) AS Morada,
        NULLIF(LTRIM(RTRIM(b.zip_code)), '') AS Codigo_Postal,
        CAST(ISNULL(NULLIF(LTRIM(RTRIM(b.clity)), ''), 'Desconhecida') AS nvarchar(43)) AS Cidade,
        CAST(z.zone AS nvarchar(50)) AS Zona,
        CAST(CASE WHEN z.zone = 'Espanha' THEN 'Espanha' ELSE 'Portugal' END AS nvarchar(30)) AS Pais,
        CAST(LTRIM(RTRIM(b.type)) AS nvarchar(20)) AS Tipo_Cliente,
        CAST(LTRIM(RTRIM(b.segment)) AS nvarchar(25)) AS Segmento,
        CAST(e.name AS nvarchar(30)) AS Vendedor_Atribuido,
        CAST(b.days_pay_invoices AS smallint) AS Dias_Pagamento,
        b.seller AS seller_no,
        CAST(b.create_date AS datetime2(0)) AS Data_Criacao_Origem,
        (SELECT MAX(dbo.fn_upd(g.last_update_date, g.last_update_time)) FROM dbo.map_cliente mg JOIN dbo.src_customers g ON g.number = mg.origem
          WHERE mg.sobrevivente = b.BK) AS Data_Atualizacao_Origem
    INTO #n0
    FROM base b
    JOIN dbo.src_zones z ON z.code = b.zone
    LEFT JOIN dbo.src_employees e ON e.number = b.seller AND b.seller <> 0
    -- atributos de contacto: o valor valido mais recente do grupo de duplicados
    OUTER APPLY (SELECT TOP 1 CAST(NULLIF(LTRIM(RTRIM(g.email)), '') AS varchar(45)) v FROM dbo.map_cliente mg JOIN dbo.src_customers g ON g.number = mg.origem
                 WHERE mg.sobrevivente = b.BK AND g.email LIKE '%_@_%._%' AND g.email NOT LIKE '% %' AND LEN(g.email) - LEN(REPLACE(g.email, '@', '')) = 1
                 ORDER BY dbo.fn_upd(g.last_update_date, g.last_update_time) DESC) em
    OUTER APPLY (SELECT TOP 1 CAST(NULLIF(LTRIM(RTRIM(g.phone)), '') AS varchar(60)) v FROM dbo.map_cliente mg JOIN dbo.src_customers g ON g.number = mg.origem
                 WHERE mg.sobrevivente = b.BK AND LTRIM(RTRIM(g.phone)) <> ''
                 ORDER BY dbo.fn_upd(g.last_update_date, g.last_update_time) DESC) ph
    OUTER APPLY (SELECT TOP 1 CAST(NULLIF(LTRIM(RTRIM(g.mobile)), '') AS varchar(45)) v FROM dbo.map_cliente mg JOIN dbo.src_customers g ON g.number = mg.origem
                 WHERE mg.sobrevivente = b.BK AND LTRIM(RTRIM(g.mobile)) <> ''
                 ORDER BY dbo.fn_upd(g.last_update_date, g.last_update_time) DESC) mo;

    SELECT *, HASHBYTES('SHA2_256', CONCAT_WS('|', Nome, NIF, Contacto, Email, Telefone, Telemovel, Morada, Codigo_Postal, Dias_Pagamento)) AS Hash_SCD1,
              HASHBYTES('SHA2_256', CONCAT_WS('|', Cidade, Zona, Pais, Tipo_Cliente, Segmento, seller_no)) AS Hash_SCD2
    INTO #n FROM #n0;
    EXEC dbo.usp_scd 'Dim_Cliente', 'BK_Cliente', 'SK_Cliente',
        'Nome,NIF,Contacto,Email,Telefone,Telemovel,Morada,Codigo_Postal,Cidade,Zona,Pais,Tipo_Cliente,Segmento,Vendedor_Atribuido,Dias_Pagamento',
        'Nome,NIF,Contacto,Email,Telefone,Telemovel,Morada,Codigo_Postal,Dias_Pagamento';
END;
GO

/*------------------------------ 4. Dim_Produto -----------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_load_dim_produto AS
BEGIN
    DROP TABLE IF EXISTS #n;
    SELECT p.reference AS BK,
        CAST(RTRIM(p.designation) AS nvarchar(60)) AS Designacao,
        CAST(p.family AS varchar(18)) AS BK_Familia, CAST(f.name AS nvarchar(60)) AS Familia,
        CAST(NULLIF(RTRIM(f.classification), '') AS nvarchar(20)) AS Classificacao_Familia,
        p.category AS BK_Categoria, CAST(c.Category AS nvarchar(35)) AS Categoria,
        CAST(COALESCE(NULLIF(RTRIM(p.classification), ''), NULLIF(RTRIM(f.classification), '')) AS nvarchar(20)) AS Classificacao_Produto,
        CAST(p.vat_rate AS decimal(5,2)) AS Taxa_IVA,
        CAST(ISNULL(p.create_date, '1900-01-01') AS datetime2(0)) AS Data_Criacao_Origem,
        dbo.fn_upd(ISNULL(p.last_update_date, '1900-01-01'), ISNULL(p.last_update_time, '00:00')) AS Data_Atualizacao_Origem
    INTO #n0
    FROM dbo.src_products p
    JOIN dbo.src_families f ON f.reference = p.family
    JOIN dbo.src_categories c ON c.Code = p.category
    WHERE p.designation IS NOT NULL;                    -- sem designacao, familia ou categoria: rejeitado

    SELECT *, HASHBYTES('SHA2_256', CONCAT_WS('|', Designacao, '')) AS Hash_SCD1,
              HASHBYTES('SHA2_256', CONCAT_WS('|', BK_Familia, Familia, Classificacao_Familia, BK_Categoria, Categoria, Classificacao_Produto, Taxa_IVA)) AS Hash_SCD2
    INTO #n FROM #n0;
    EXEC dbo.usp_scd 'Dim_Produto', 'BK_Produto', 'SK_Produto',
        'Designacao,BK_Familia,Familia,Classificacao_Familia,BK_Categoria,Categoria,Classificacao_Produto,Taxa_IVA', 'Designacao';
END;
GO

/*---------------------------- 5. Dim_Fornecedor ----------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_load_dim_fornecedor AS
BEGIN
    DROP TABLE IF EXISTS #n;
    SELECT s.number AS BK, CAST(LTRIM(RTRIM(s.name)) AS nvarchar(55)) AS Nome, dbo.fn_nif(s.taxpayer_number) AS NIF,
        CAST(LTRIM(RTRIM(s.type)) AS nvarchar(20)) AS Tipo_Fornecedor,
        CAST(NULLIF(LTRIM(RTRIM(s.nationality)), '') AS nvarchar(20)) AS Nacionalidade,
        CAST(ISNULL(NULLIF(LTRIM(RTRIM(s.city)), ''), 'Desconhecida') AS nvarchar(43)) AS Cidade,
        CAST(ISNULL(z.zone, 'Zona desconhecida') AS nvarchar(50)) AS Zona,
        CAST(NULLIF(LTRIM(RTRIM(s.address)), '') AS nvarchar(55)) AS Morada,
        NULLIF(LTRIM(RTRIM(s.zip_code)), '') AS Codigo_Postal,
        CAST(NULLIF(LTRIM(RTRIM(s.contact)), '') AS nvarchar(30)) AS Contacto,
        CAST(NULLIF(LTRIM(RTRIM(s.contact_position)), '') AS nvarchar(15)) AS Cargo_Contacto,
        NULLIF(LTRIM(RTRIM(s.email)), '') AS Email, NULLIF(LTRIM(RTRIM(s.phone)), '') AS Telefone,
        NULLIF(LTRIM(RTRIM(s.mobile)), '') AS Telemovel, CAST(s.days_pay_invoices AS smallint) AS Dias_Pagamento,
        CAST(s.create_date AS datetime2(0)) AS Data_Criacao_Origem, dbo.fn_upd(s.last_update_date, s.last_update_time) AS Data_Atualizacao_Origem
    INTO #n0
    FROM dbo.src_suplliers s LEFT JOIN dbo.src_zones z ON z.code = s.zone;

    SELECT *, HASHBYTES('SHA2_256', CONCAT_WS('|', Nome, NIF, Nacionalidade, Morada, Codigo_Postal, Contacto, Cargo_Contacto, Email, Telefone, Telemovel, Dias_Pagamento)) AS Hash_SCD1,
              HASHBYTES('SHA2_256', CONCAT_WS('|', Tipo_Fornecedor, Cidade, Zona)) AS Hash_SCD2
    INTO #n FROM #n0;
    EXEC dbo.usp_scd 'Dim_Fornecedor', 'BK_Fornecedor', 'SK_Fornecedor',
        'Nome,NIF,Tipo_Fornecedor,Nacionalidade,Cidade,Zona,Morada,Codigo_Postal,Contacto,Cargo_Contacto,Email,Telefone,Telemovel,Dias_Pagamento',
        'Nome,NIF,Nacionalidade,Morada,Codigo_Postal,Contacto,Cargo_Contacto,Email,Telefone,Telemovel,Dias_Pagamento';
END;
GO

/*---------------------------- 6. Dim_Funcionario ---------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_load_dim_funcionario AS
BEGIN
    DROP TABLE IF EXISTS #n;
    SELECT e.number AS BK, CAST(LTRIM(RTRIM(e.code)) AS varchar(20)) AS Codigo, CAST(LTRIM(RTRIM(e.name)) AS nvarchar(30)) AS Nome,
        CAST(CASE WHEN e.email LIKE '%_@_%._%' AND e.email NOT LIKE '% %' AND LEN(e.email) - LEN(REPLACE(e.email, '@', '')) = 1 THEN LTRIM(RTRIM(e.email)) END AS varchar(100)) AS Email, CAST(LTRIM(RTRIM(e.[group])) AS nvarchar(20)) AS Grupo,
        CAST(LTRIM(RTRIM(e.departament)) AS nvarchar(20)) AS Departamento,
        e.chief AS BK_Chefe, CAST(ch.name AS nvarchar(30)) AS Nome_Chefe,
        CAST(e.create_date AS datetime2(0)) AS Data_Criacao_Origem, dbo.fn_upd(e.last_update_date, e.last_update_time) AS Data_Atualizacao_Origem
    INTO #n0
    FROM dbo.src_employees e LEFT JOIN dbo.src_employees ch ON ch.number = e.chief;

    -- o nome do chefe e SCD1 (atualiza todas as versoes); o SCD2 usa so o numero do chefe
    SELECT *, HASHBYTES('SHA2_256', CONCAT_WS('|', Codigo, Nome, Email, Nome_Chefe)) AS Hash_SCD1,
              HASHBYTES('SHA2_256', CONCAT_WS('|', Grupo, Departamento, BK_Chefe)) AS Hash_SCD2
    INTO #n FROM #n0;
    EXEC dbo.usp_scd 'Dim_Funcionario', 'BK_Funcionario', 'SK_Funcionario',
        'Codigo,Nome,Email,Grupo,Departamento,BK_Chefe,Nome_Chefe', 'Codigo,Nome,Email,Nome_Chefe';
END;
GO

/*------------------------------- 7. Fact_Vendas ----------------------------*/
CREATE OR ALTER PROCEDURE dbo.usp_load_fact @lote bigint AS
BEGIN
    DROP TABLE IF EXISTS #linhas;
    ;WITH soma AS (
        SELECT invoice_stamp_id, SUM(line_total) s, COUNT(*) n,
               SUM(CASE WHEN line_total <> quantity * unit_price THEN 1 ELSE 0 END) r06
        FROM dbo.src_invoices_lines GROUP BY invoice_stamp_id),
    fat AS (   -- so faturas validas: sem R06 (linha incoerente), R07 (cabecalho <> linhas) e R11 (total <> produtos + frete + IVA)
        SELECT i.*, so.s, so.n FROM dbo.src_invoices i JOIN soma so ON so.invoice_stamp_id = i.invoice_stamp_id
        WHERE so.r06 = 0 AND ABS(i.products_total - so.s) <= 0.01
          AND ABS(i.final_total - (i.products_total + i.shipping_cost + i.vat_value)) <= 0.01),   -- R11 (proposta)
    lin AS (
        SELECT l.*, f.invoice_date, f.customer, f.employee, f.payment_date, f.currency, f.shipping_cost, f.s, f.n,
               f.last_update_date AS f_upd_d, f.last_update_time AS f_upd_t, f.create_date AS f_cd, f.create_time AS f_ct,
               ROW_NUMBER() OVER (PARTITION BY l.invoice_stamp_id ORDER BY l.invoice_line_stamp_id DESC) AS rn_desc,
               ROUND(f.shipping_cost * CASE WHEN f.s = 0 THEN 1.0 / f.n ELSE l.line_total / f.s END, 6) AS frete_parcial
        FROM dbo.src_invoices_lines l JOIN fat f ON f.invoice_stamp_id = l.invoice_stamp_id)
    SELECT lin.*,
        -- resto do arredondamento na ultima linha, para a soma bater com o frete da fatura
        CASE WHEN rn_desc = 1 THEN shipping_cost - (SUM(frete_parcial) OVER (PARTITION BY invoice_stamp_id) - frete_parcial)
             ELSE frete_parcial END AS frete_alocado
    INTO #linhas FROM lin;

    -- linhas validas: com todas as dimensoes resolvidas pela data da fatura
    DROP TABLE IF EXISTS #res;
    SELECT l.*, YEAR(l.invoice_date) * 10000 + MONTH(l.invoice_date) * 100 + DAY(l.invoice_date) AS sk_data,
        ISNULL(YEAR(l.payment_date) * 10000 + MONTH(l.payment_date) * 100 + DAY(l.payment_date), -1) AS sk_pag,
        dc.SK_Cliente, dp.SK_Produto, ISNULL(df.SK_Fornecedor, -1) AS SK_Fornecedor, dfu.SK_Funcionario, dm.SK_Moeda, tc.Taxa_Para_EUR,
        dc.BK_Cliente AS bk_sobrevivente
    INTO #res
    FROM #linhas l
    JOIN dbo.map_cliente mc ON mc.origem = l.customer
    JOIN dbo.Dim_Cliente dc ON dc.BK_Cliente = mc.sobrevivente AND l.invoice_date BETWEEN dc.Data_Inicio AND dc.Data_Fim
    JOIN dbo.Dim_Produto dp ON dp.BK_Produto = l.product AND l.invoice_date BETWEEN dp.Data_Inicio AND dp.Data_Fim
    JOIN dbo.src_products pr ON pr.reference = l.product
    LEFT JOIN dbo.Dim_Fornecedor df ON df.BK_Fornecedor = pr.supplyer AND l.invoice_date BETWEEN df.Data_Inicio AND df.Data_Fim
    JOIN dbo.Dim_Funcionario dfu ON dfu.BK_Funcionario = l.employee AND l.invoice_date BETWEEN dfu.Data_Inicio AND dfu.Data_Fim
    JOIN dbo.Dim_Moeda dm ON dm.Codigo_ISO = CASE WHEN l.currency = 'EURO' THEN 'EUR' ELSE l.currency END
    JOIN dbo.Dim_Taxa_Cambio tc ON tc.SK_Data = YEAR(l.invoice_date) * 10000 + MONTH(l.invoice_date) * 100 + DAY(l.invoice_date) AND tc.SK_Moeda = dm.SK_Moeda
    WHERE pr.supplyer IS NULL OR df.SK_Fornecedor IS NOT NULL;

    -- hash da linha: linha + cabecalho (o frete do cabecalho altera a alocacao de todas as linhas)
    DROP TABLE IF EXISTS #f;
    SELECT SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda, sk_data, sk_pag, customer,
        invoice_stamp_id, invoice_line_stamp_id, quantity, unit_price, line_total, line_vat, frete_alocado, Taxa_Para_EUR,
        dbo.fn_upd(create_date, create_time) AS cd,
        CASE WHEN dbo.fn_upd(last_update_date, last_update_time) > dbo.fn_upd(f_upd_d, f_upd_t)
             THEN dbo.fn_upd(last_update_date, last_update_time) ELSE dbo.fn_upd(f_upd_d, f_upd_t) END AS ud,
        HASHBYTES('SHA2_256', CONCAT_WS('|', invoice_line_stamp_id, product, quantity, unit_price, line_total, line_vat,
                                         invoice_date, customer, employee, payment_date, currency, shipping_cost, last_update_date, last_update_time,
                                         f_upd_d, f_upd_t)) AS hl
    INTO #f FROM #res;

    -- upsert por BK_Linha_Fatura: so insere novas linhas ou as que mudaram (hash)
    UPDATE x SET SK_Data_Fatura = f.sk_data, SK_Data_Pagamento = f.sk_pag, SK_Cliente = f.SK_Cliente, SK_Produto = f.SK_Produto,
        SK_Fornecedor = f.SK_Fornecedor, SK_Funcionario = f.SK_Funcionario, SK_Moeda = f.SK_Moeda, Quantidade = f.quantity,
        Preco_Unitario = f.unit_price, Valor_Liquido = f.line_total, Valor_IVA = f.line_vat, Frete_Alocado = f.frete_alocado,
        Taxa_Cambio = f.Taxa_Para_EUR, Valor_Liquido_EUR = ROUND(f.line_total * f.Taxa_Para_EUR, 6),
        Valor_IVA_EUR = ROUND(f.line_vat * f.Taxa_Para_EUR, 6), Frete_Alocado_EUR = ROUND(f.frete_alocado * f.Taxa_Para_EUR, 6),
        Data_Atualizacao_Origem = f.ud, ID_Lote_ETL = @lote, Hash_Linha = f.hl, BK_Cliente_Origem = f.customer
    FROM dbo.Fact_Vendas x JOIN #f f ON f.invoice_line_stamp_id = x.BK_Linha_Fatura WHERE x.Hash_Linha <> f.hl;
    DECLARE @upd int = @@ROWCOUNT;

    INSERT dbo.Fact_Vendas (SK_Data_Fatura, SK_Data_Pagamento, SK_Cliente, SK_Produto, SK_Fornecedor, SK_Funcionario, SK_Moeda,
        Numero_Fatura, BK_Linha_Fatura, Quantidade, Preco_Unitario, Valor_Liquido, Valor_IVA, Frete_Alocado, Taxa_Cambio,
        Valor_Liquido_EUR, Valor_IVA_EUR, Frete_Alocado_EUR, Data_Criacao_Origem, Data_Atualizacao_Origem, ID_Lote_ETL, Hash_Linha, BK_Cliente_Origem)
    SELECT f.sk_data, f.sk_pag, f.SK_Cliente, f.SK_Produto, f.SK_Fornecedor, f.SK_Funcionario, f.SK_Moeda,
        f.invoice_stamp_id, f.invoice_line_stamp_id, f.quantity, f.unit_price, f.line_total, f.line_vat, f.frete_alocado, f.Taxa_Para_EUR,
        ROUND(f.line_total * f.Taxa_Para_EUR, 6), ROUND(f.line_vat * f.Taxa_Para_EUR, 6), ROUND(f.frete_alocado * f.Taxa_Para_EUR, 6),
        f.cd, f.ud, @lote, f.hl, f.customer
    FROM #f f WHERE NOT EXISTS (SELECT 1 FROM dbo.Fact_Vendas x WHERE x.BK_Linha_Fatura = f.invoice_line_stamp_id);
    DECLARE @ins int = @@ROWCOUNT;
    SELECT @ins AS linhas_inseridas, @upd AS linhas_atualizadas;
END;
GO

/*--------------------------------- execucao --------------------------------*/
PRINT '== Carga 1';
EXEC dbo.usp_load_dim_cliente;
EXEC dbo.usp_load_dim_produto;
EXEC dbo.usp_load_dim_fornecedor;
EXEC dbo.usp_load_dim_funcionario;
EXEC dbo.usp_load_fact @lote = 1;
GO
