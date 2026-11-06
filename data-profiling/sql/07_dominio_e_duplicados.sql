/*
  07_dominio_e_duplicados.sql

  Data profiling de domínio e deteção de duplicados aproximados de clientes.
  Todas as consultas à base MoreRhythm são de leitura. A única escrita é uma
  função auxiliar (p3_lev, distância de Levenshtein) criada em tempdb e
  removida no fim do script.

  Parte A (7.1 a 7.4): validação de domínio (formato, intervalo, lista de valores).
  Parte B (7.5 a 7.9): duplicados aproximados de clientes e fornecedores.

  Execução (SQL Server 2017 ou superior):
    sqlcmd -S <servidor> -E -i 07_dominio_e_duplicados.sql
*/

USE MoreRhythm;
GO

-- ---------------------------------------------------------------------------
-- 7.1. Número de contribuinte: 9 dígitos e valores não identificativos
-- ---------------------------------------------------------------------------
SELECT 'clientes' AS Tabela, number AS Numero,
       taxpayer_number AS NIF_Original,
       CASE WHEN NULLIF(LTRIM(RTRIM(taxpayer_number)), '') IS NULL THEN 'vazio'
            WHEN taxpayer_number NOT LIKE REPLICATE('[0-9]', 9) THEN 'não tem 9 dígitos'
            WHEN taxpayer_number = '000000000' THEN 'nove zeros'
       END AS Problema
FROM dbo.customers
WHERE NULLIF(LTRIM(RTRIM(taxpayer_number)), '') IS NULL
   OR taxpayer_number NOT LIKE REPLICATE('[0-9]', 9)
   OR taxpayer_number = '000000000'
UNION ALL
SELECT 'fornecedores', number, taxpayer_number,
       CASE WHEN NULLIF(LTRIM(RTRIM(taxpayer_number)), '') IS NULL THEN 'vazio'
            WHEN taxpayer_number NOT LIKE REPLICATE('[0-9]', 9) THEN 'não tem 9 dígitos'
            WHEN taxpayer_number = '111111111' THEN 'valor genérico'
       END
FROM dbo.suplliers
WHERE NULLIF(LTRIM(RTRIM(taxpayer_number)), '') IS NULL
   OR taxpayer_number NOT LIKE REPLICATE('[0-9]', 9)
   OR taxpayer_number = '111111111'
ORDER BY Tabela, Numero;
GO

-- ---------------------------------------------------------------------------
-- 7.2. Email: ausente (vazio ou só espaços) versus preenchido com formato inválido
--      Formato válido: um único '@', texto antes, um '.' depois do '@', sem espaços.
-- ---------------------------------------------------------------------------
WITH e AS (
    SELECT 'clientes' AS Tabela, number AS Numero, email FROM dbo.customers
    UNION ALL SELECT 'fornecedores', number, email FROM dbo.suplliers
    UNION ALL SELECT 'funcionários', number, email FROM dbo.employees
)
SELECT Tabela,
       COUNT(*) AS Registos,
       SUM(CASE WHEN LTRIM(RTRIM(ISNULL(email, ''))) = '' THEN 1 ELSE 0 END) AS Ausente,
       SUM(CASE WHEN LTRIM(RTRIM(ISNULL(email, ''))) <> ''
                 AND (email NOT LIKE '_%@_%._%'
                      OR email LIKE '% %'
                      OR LEN(email) - LEN(REPLACE(email, '@', '')) <> 1)
                THEN 1 ELSE 0 END) AS FormatoInvalido
FROM e
GROUP BY Tabela
ORDER BY Tabela;

SELECT Tabela, Numero, email AS Email_Invalido
FROM (
    SELECT 'clientes' AS Tabela, number AS Numero, email FROM dbo.customers
    UNION ALL SELECT 'fornecedores', number, email FROM dbo.suplliers
    UNION ALL SELECT 'funcionários', number, email FROM dbo.employees
) AS x
WHERE LTRIM(RTRIM(ISNULL(email, ''))) <> ''
  AND (email NOT LIKE '_%@_%._%'
       OR email LIKE '% %'
       OR LEN(email) - LEN(REPLACE(email, '@', '')) <> 1)
ORDER BY Tabela, Numero;
GO

-- ---------------------------------------------------------------------------
-- 7.3. Código postal: formato português NNNN-NNN seguido da localidade
--      Os não portugueses correspondem a zonas/nacionalidades estrangeiras.
-- ---------------------------------------------------------------------------
SELECT 'clientes' AS Tabela, c.number AS Numero, c.zip_code AS Codigo_Postal,
       z.zone AS Zona,
       CASE WHEN NULLIF(LTRIM(RTRIM(c.zip_code)), '') IS NULL THEN 'vazio'
            ELSE 'fora do formato português' END AS Problema
FROM dbo.customers AS c
LEFT JOIN dbo.zones AS z ON z.code = c.zone
WHERE c.zip_code IS NULL
   OR c.zip_code NOT LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9] %'
UNION ALL
SELECT 'fornecedores', s.number, s.zip_code, z.zone,
       CASE WHEN NULLIF(LTRIM(RTRIM(s.zip_code)), '') IS NULL THEN 'vazio'
            ELSE 'fora do formato português' END
FROM dbo.suplliers AS s
LEFT JOIN dbo.zones AS z ON z.code = s.zone
WHERE s.zip_code IS NULL
   OR s.zip_code NOT LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9] %'
ORDER BY Tabela, Numero;
GO

-- ---------------------------------------------------------------------------
-- 7.4. Domínios de lista, taxas de IVA e atributos de auditoria
-- ---------------------------------------------------------------------------
-- Valores distintos dos atributos categóricos
SELECT 'clientes.type' AS Atributo, type AS Valor, COUNT(*) AS Registos FROM dbo.customers GROUP BY type
UNION ALL SELECT 'clientes.segment', segment, COUNT(*) FROM dbo.customers GROUP BY segment
UNION ALL SELECT 'clientes.days_pay_invoices', CAST(days_pay_invoices AS varchar(10)), COUNT(*) FROM dbo.customers GROUP BY days_pay_invoices
UNION ALL SELECT 'fornecedores.type', type, COUNT(*) FROM dbo.suplliers GROUP BY type
UNION ALL SELECT 'produtos.classification', classification, COUNT(*) FROM dbo.products GROUP BY classification
UNION ALL SELECT 'produtos.vat_rate', CAST(vat_rate AS varchar(10)), COUNT(*) FROM dbo.products GROUP BY vat_rate
ORDER BY Atributo, Valor;

-- Taxa de IVA implícita nas linhas de fatura (line_vat / line_total)
SELECT CAST(ROUND(100.0 * line_vat / NULLIF(line_total, 0), 2) AS decimal(6, 2)) AS Taxa_Implicita,
       COUNT(*) AS Linhas
FROM dbo.invoices_lines
GROUP BY CAST(ROUND(100.0 * line_vat / NULLIF(line_total, 0), 2) AS decimal(6, 2));

-- Produtos sem taxa de IVA nem classificação
SELECT reference, vat_rate, classification, family, category
FROM dbo.products
WHERE vat_rate IS NULL OR classification IS NULL;

-- Auditoria: última atualização anterior à criação
SELECT 'produtos' AS Tabela, COUNT(*) AS Registos, SUM(CASE WHEN last_update_date < create_date THEN 1 ELSE 0 END) AS UpdateAntesCriacao FROM dbo.products
UNION ALL SELECT 'fornecedores', COUNT(*), SUM(CASE WHEN last_update_date < create_date THEN 1 ELSE 0 END) FROM dbo.suplliers
UNION ALL SELECT 'clientes', COUNT(*), SUM(CASE WHEN last_update_date < create_date THEN 1 ELSE 0 END) FROM dbo.customers
UNION ALL SELECT 'funcionários', COUNT(*), SUM(CASE WHEN last_update_date < create_date THEN 1 ELSE 0 END) FROM dbo.employees
UNION ALL SELECT 'faturas', COUNT(*), SUM(CASE WHEN last_update_date < create_date THEN 1 ELSE 0 END) FROM dbo.invoices;

-- Datas das faturas
SELECT MIN(invoice_date) AS PrimeiraFatura, MAX(invoice_date) AS UltimaFatura,
       MIN(DATEDIFF(day, invoice_date, payment_date)) AS MinDiasAtePagamento,
       MAX(DATEDIFF(day, invoice_date, payment_date)) AS MaxDiasAtePagamento,
       SUM(CASE WHEN payment_date < invoice_date THEN 1 ELSE 0 END) AS PagamentoAntesFatura
FROM dbo.invoices;
GO

/* ===========================================================================
   PARTE B - Duplicados aproximados
   ===========================================================================
   Função de distância de Levenshtein em tempdb (removida no fim).
   A base MoreRhythm tem nível de compatibilidade 110, pelo que as consultas
   seguintes correm em tempdb e leem a origem com nomes de três partes.
   =========================================================================== */
USE tempdb;
GO

CREATE OR ALTER FUNCTION dbo.p3_lev (@a nvarchar(200), @b nvarchar(200))
RETURNS int
AS
BEGIN
    DECLARE @la int = LEN(@a), @lb int = LEN(@b), @i int, @j int, @cost int;
    IF @a IS NULL OR @b IS NULL RETURN NULL;
    IF @la = 0 RETURN @lb;
    IF @lb = 0 RETURN @la;
    DECLARE @d TABLE (i int, j int, v int, PRIMARY KEY (i, j));
    SET @i = 0; WHILE @i <= @la BEGIN INSERT @d VALUES (@i, 0, @i); SET @i += 1; END
    SET @j = 1; WHILE @j <= @lb BEGIN INSERT @d VALUES (0, @j, @j); SET @j += 1; END
    SET @i = 1;
    WHILE @i <= @la
    BEGIN
        SET @j = 1;
        WHILE @j <= @lb
        BEGIN
            SET @cost = CASE WHEN SUBSTRING(@a, @i, 1) = SUBSTRING(@b, @j, 1) THEN 0 ELSE 1 END;
            INSERT @d
            SELECT @i, @j, MIN(x)
            FROM (VALUES ((SELECT v FROM @d WHERE i = @i - 1 AND j = @j) + 1),
                         ((SELECT v FROM @d WHERE i = @i AND j = @j - 1) + 1),
                         ((SELECT v FROM @d WHERE i = @i - 1 AND j = @j - 1) + @cost)) AS t (x);
            SET @j += 1;
        END
        SET @i += 1;
    END
    RETURN (SELECT v FROM @d WHERE i = @la AND j = @lb);
END;
GO

-- ---------------------------------------------------------------------------
-- 7.5. Atributos normalizados (apenas para comparação; a origem não é alterada)
--   nome:   maiúsculas, sem pontuação, sem as formas jurídicas LDA e SA
--   morada: maiúsculas, sem pontuação, 'R' inicial expandido para 'RUA'
--   NIF:    só conta se tiver 9 dígitos e não for composto só por zeros
--   email:  só conta se tiver o formato válido de 7.2
--   telefone: dígitos de phone e de mobile, sem espaços nem prefixo '+'
-- ---------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#cli') IS NOT NULL DROP TABLE #cli;

SELECT c.number AS n,
       LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(
           ' ' + UPPER(REPLACE(REPLACE(REPLACE(c.name, '.', ' '), ',', ' '), '-', ' ')) + ' ',
           ' LDA ', ' '), ' SA ', ' '), '  ', ' '), '  ', ' '))) AS nome_n,
       LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(
           ' ' + UPPER(REPLACE(REPLACE(REPLACE(c.address, '.', ' '), ',', ' '), '-', ' ')) + ' ',
           ' R ', ' RUA '), '  ', ' '), '  ', ' '))) AS morada_n,
       CASE WHEN c.taxpayer_number LIKE REPLICATE('[0-9]', 9)
             AND c.taxpayer_number <> '000000000' THEN c.taxpayer_number END AS nif_n,
       CASE WHEN c.email LIKE '_%@_%._%' AND c.email NOT LIKE '% %'
             AND LEN(c.email) - LEN(REPLACE(c.email, '@', '')) = 1
            THEN LOWER(c.email) END AS email_n,
       NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(c.phone)), ' ', ''), '+', ''), '') AS tel_n,
       NULLIF(REPLACE(REPLACE(LTRIM(RTRIM(c.mobile)), ' ', ''), '+', ''), '') AS tlm_n,
       CASE WHEN c.zip_code LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9] %' THEN LEFT(c.zip_code, 8) END AS cp_n,
       NULLIF(LTRIM(RTRIM(c.BBAN)), '') AS bban_n,
       c.zone AS zona, c.type AS tipo,
       c.last_update_date AS upd_d, c.last_update_time AS upd_t
INTO #cli
FROM MoreRhythm.dbo.customers AS c;

-- ---------------------------------------------------------------------------
-- 7.6. Indicadores para os 325 pares de clientes (26 x 25 / 2)
--   sim_nome / sim_morada = 1 - Levenshtein / comprimento máximo (0 a 1)
--   d_nif = Levenshtein entre NIF válidos (NULL se algum não for identificativo)
--   n_corrob = número de atributos corroborantes verificados
-- ---------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#pares') IS NOT NULL DROP TABLE #pares;

SELECT a.n AS na, b.n AS nb,
       CAST(1.0 - dbo.p3_lev(a.nome_n, b.nome_n) * 1.0
            / NULLIF(CASE WHEN LEN(a.nome_n) > LEN(b.nome_n) THEN LEN(a.nome_n) ELSE LEN(b.nome_n) END, 0)
            AS decimal(4, 2)) AS sim_nome,
       CAST(1.0 - dbo.p3_lev(a.morada_n, b.morada_n) * 1.0
            / NULLIF(CASE WHEN LEN(a.morada_n) > LEN(b.morada_n) THEN LEN(a.morada_n) ELSE LEN(b.morada_n) END, 0)
            AS decimal(4, 2)) AS sim_morada,
       dbo.p3_lev(a.nif_n, b.nif_n) AS d_nif,
       CASE WHEN a.cp_n = b.cp_n THEN 1 ELSE 0 END AS mesmo_cp,
       CASE WHEN a.email_n = b.email_n THEN 1 ELSE 0 END AS mesmo_email,
       CASE WHEN a.tel_n IN (b.tel_n, b.tlm_n) OR a.tlm_n IN (b.tel_n, b.tlm_n) THEN 1 ELSE 0 END AS mesmo_tel,
       CASE WHEN a.bban_n = b.bban_n THEN 1 ELSE 0 END AS mesmo_bban
INTO #pares
FROM #cli AS a
JOIN #cli AS b ON a.n < b.n;

ALTER TABLE #pares ADD n_corrob int, decisao varchar(20);
GO

-- Critério R01 (ver mappings/transformacoes-limpeza.md):
--   DUPLICADO se sim_nome >= 0,80 e houver pelo menos 2 atributos corroborantes
--   entre: mesmo código postal; sim_morada >= 0,80; mesmo telefone/telemóvel;
--   mesmo email válido; mesmo BBAN; NIF válido com distância <= 2.
UPDATE #pares
SET n_corrob = mesmo_cp
             + CASE WHEN sim_morada >= 0.80 THEN 1 ELSE 0 END
             + mesmo_tel + mesmo_email + mesmo_bban
             + CASE WHEN d_nif <= 2 THEN 1 ELSE 0 END;

UPDATE #pares
SET decisao = CASE WHEN sim_nome >= 0.80 AND n_corrob >= 2 THEN 'DUPLICADO' ELSE 'DISTINTO' END;
GO

-- 7.6.a. Pares com maior semelhança de nome, com os indicadores
SELECT TOP (12) p.na, p.nb, ca.name AS Nome_A, cb.name AS Nome_B,
       p.sim_nome, p.sim_morada, p.d_nif, p.mesmo_cp, p.mesmo_tel,
       p.mesmo_email, p.mesmo_bban, p.n_corrob, p.decisao
FROM #pares AS p
JOIN MoreRhythm.dbo.customers AS ca ON ca.number = p.na
JOIN MoreRhythm.dbo.customers AS cb ON cb.number = p.nb
ORDER BY p.sim_nome DESC, p.n_corrob DESC, p.na, p.nb;

-- 7.6.b. Sensibilidade ao limiar de nome: quantos pares passam em cada limiar
SELECT t.Limiar,
       SUM(CASE WHEN p.sim_nome >= t.Limiar THEN 1 ELSE 0 END) AS ParesComNomeSemelhante,
       SUM(CASE WHEN p.sim_nome >= t.Limiar AND p.n_corrob >= 2 THEN 1 ELSE 0 END) AS ParesDuplicados
FROM #pares AS p
CROSS JOIN (VALUES (0.50), (0.60), (0.70), (0.80), (0.90), (1.00)) AS t (Limiar)
GROUP BY t.Limiar
ORDER BY t.Limiar;

-- 7.6.c. Maior semelhança de nome entre pares classificados como distintos
SELECT MAX(sim_nome) AS MaxSimNome_Distintos FROM #pares WHERE decisao = 'DISTINTO';
GO

-- ---------------------------------------------------------------------------
-- 7.7. Grupos, sobrevivente e mapeamento origem -> sobrevivente
--   Verificação prévia: nenhum cliente aparece em mais de um par duplicado.
--   Sobrevivente: registo com a atualização mais recente (data e hora);
--   em empate, o menor número de cliente.
-- ---------------------------------------------------------------------------
SELECT CASE WHEN COUNT(*) = 0 THEN 'OK: nenhum cliente em mais de um par' ELSE 'ATENÇÃO: cadeia de duplicados' END AS Verificacao
FROM (SELECT n FROM (SELECT na AS n FROM #pares WHERE decisao = 'DUPLICADO'
                     UNION ALL SELECT nb FROM #pares WHERE decisao = 'DUPLICADO') AS m
      GROUP BY n HAVING COUNT(*) > 1) AS x;

IF OBJECT_ID('tempdb..#mapa') IS NOT NULL DROP TABLE #mapa;

WITH m AS (
    SELECT p.na AS grupo, p.na AS n FROM #pares AS p WHERE p.decisao = 'DUPLICADO'
    UNION ALL SELECT p.na, p.nb FROM #pares AS p WHERE p.decisao = 'DUPLICADO'
), r AS (
    SELECT m.grupo, m.n,
           ROW_NUMBER() OVER (PARTITION BY m.grupo
                              ORDER BY c.upd_d DESC, c.upd_t DESC, m.n ASC) AS ordem
    FROM m JOIN #cli AS c ON c.n = m.n
)
SELECT grupo AS duplicate_group_id, n AS cliente_origem,
       FIRST_VALUE(n) OVER (PARTITION BY grupo ORDER BY ordem) AS cliente_sobrevivente,
       CASE WHEN ordem = 1 THEN 'sobrevivente' ELSE 'absorvido' END AS papel
INTO #mapa
FROM r;

SELECT * FROM #mapa ORDER BY duplicate_group_id, papel DESC;
GO

-- Registo consolidado: por atributo, o valor do sobrevivente se for válido;
-- caso contrário, o valor válido do absorvido (um valor vazio nunca prevalece).
SELECT s.duplicate_group_id,
       s.cliente_origem AS BK_Sobrevivente,
       COALESCE(NULLIF(LTRIM(RTRIM(cs.name)), ''), NULLIF(LTRIM(RTRIM(ca.name)), '')) AS Nome,
       COALESCE(s_c.nif_n, a_c.nif_n) AS NIF,
       COALESCE(s_c.email_n, a_c.email_n) AS Email,
       COALESCE(NULLIF(LTRIM(RTRIM(cs.phone)), ''), NULLIF(LTRIM(RTRIM(ca.phone)), '')) AS Telefone,
       COALESCE(NULLIF(LTRIM(RTRIM(cs.address)), ''), NULLIF(LTRIM(RTRIM(ca.address)), '')) AS Morada,
       COALESCE(NULLIF(LTRIM(RTRIM(cs.zip_code)), ''), NULLIF(LTRIM(RTRIM(ca.zip_code)), '')) AS Codigo_Postal
FROM #mapa AS s
JOIN #mapa AS a ON a.duplicate_group_id = s.duplicate_group_id AND a.papel = 'absorvido'
JOIN MoreRhythm.dbo.customers AS cs ON cs.number = s.cliente_origem
JOIN MoreRhythm.dbo.customers AS ca ON ca.number = a.cliente_origem
JOIN #cli AS s_c ON s_c.n = s.cliente_origem
JOIN #cli AS a_c ON a_c.n = a.cliente_origem
WHERE s.papel = 'sobrevivente'
ORDER BY s.duplicate_group_id;

-- Atributos de identificação com valores válidos e diferentes entre membros
-- (o sobrevivente prevalece; a divergência fica registada para revisão)
SELECT s.duplicate_group_id, v.Atributo, v.Sobrevivente, v.Absorvido
FROM #mapa AS s
JOIN #mapa AS a ON a.duplicate_group_id = s.duplicate_group_id AND a.papel = 'absorvido'
JOIN MoreRhythm.dbo.customers AS cs ON cs.number = s.cliente_origem
JOIN MoreRhythm.dbo.customers AS ca ON ca.number = a.cliente_origem
JOIN #cli AS s_c ON s_c.n = s.cliente_origem
JOIN #cli AS a_c ON a_c.n = a.cliente_origem
CROSS APPLY (VALUES
    ('name',            NULLIF(LTRIM(RTRIM(cs.name)), ''),    NULLIF(LTRIM(RTRIM(ca.name)), '')),
    ('taxpayer_number', s_c.nif_n,                            a_c.nif_n),
    ('email',           s_c.email_n,                          a_c.email_n),
    ('address',         NULLIF(LTRIM(RTRIM(cs.address)), ''), NULLIF(LTRIM(RTRIM(ca.address)), '')),
    ('clity',           NULLIF(LTRIM(RTRIM(cs.clity)), ''),   NULLIF(LTRIM(RTRIM(ca.clity)), '')),
    ('BBAN',            s_c.bban_n,                           a_c.bban_n)
) AS v (Atributo, Sobrevivente, Absorvido)
WHERE s.papel = 'sobrevivente'
  AND v.Sobrevivente IS NOT NULL AND v.Absorvido IS NOT NULL
  AND v.Sobrevivente COLLATE Latin1_General_CI_AI <> v.Absorvido COLLATE Latin1_General_CI_AI
ORDER BY s.duplicate_group_id, v.Atributo;
GO

-- ---------------------------------------------------------------------------
-- 7.8. Impacto da consolidação
-- ---------------------------------------------------------------------------
-- Faturação por cliente de origem nos grupos de duplicados
SELECT m.duplicate_group_id, m.cliente_origem, m.papel,
       COUNT(i.invoice_stamp_id) AS Faturas,
       ISNULL(SUM(i.final_total), 0) AS TotalFaturado
FROM #mapa AS m
LEFT JOIN MoreRhythm.dbo.invoices AS i ON i.customer = m.cliente_origem
GROUP BY m.duplicate_group_id, m.cliente_origem, m.papel
ORDER BY m.duplicate_group_id, m.papel DESC;

-- Antes e depois da consolidação
SELECT (SELECT COUNT(*) FROM #cli) AS Clientes_Antes,
       (SELECT COUNT(*) FROM #cli) - (SELECT COUNT(*) FROM #mapa WHERE papel = 'absorvido') AS Clientes_Depois,
       (SELECT COUNT(DISTINCT customer) FROM MoreRhythm.dbo.invoices) AS ClientesComFaturas_Antes,
       (SELECT COUNT(DISTINCT ISNULL(m.cliente_sobrevivente, i.customer))
        FROM MoreRhythm.dbo.invoices AS i
        LEFT JOIN #mapa AS m ON m.cliente_origem = i.customer) AS ClientesComFaturas_Depois,
       (SELECT COUNT(*) FROM MoreRhythm.dbo.invoices AS i
        JOIN #mapa AS m ON m.cliente_origem = i.customer) AS Faturas_Afetadas,
       (SELECT SUM(i.final_total) FROM MoreRhythm.dbo.invoices AS i
        JOIN #mapa AS m ON m.cliente_origem = i.customer) AS Total_Afetado,
       (SELECT SUM(final_total) FROM MoreRhythm.dbo.invoices) AS Total_Global;
GO

-- ---------------------------------------------------------------------------
-- 7.9. Fornecedores: o mesmo método aplicado ao nome, NIF e morada
-- ---------------------------------------------------------------------------
SELECT a.number AS na, b.number AS nb, a.name AS Nome_A, b.name AS Nome_B,
       a.taxpayer_number AS NIF_A, b.taxpayer_number AS NIF_B,
       a.city AS Cidade_A, b.city AS Cidade_B,
       a.zone AS Zona_A, b.zone AS Zona_B,
       a.email AS Email_A, b.email AS Email_B,
       (SELECT COUNT(*) FROM MoreRhythm.dbo.products WHERE supplyer = a.number) AS Produtos_A,
       (SELECT COUNT(*) FROM MoreRhythm.dbo.products WHERE supplyer = b.number) AS Produtos_B
FROM MoreRhythm.dbo.suplliers AS a
JOIN MoreRhythm.dbo.suplliers AS b ON a.number < b.number
WHERE a.taxpayer_number = b.taxpayer_number
  AND a.taxpayer_number LIKE REPLICATE('[0-9]', 9)
  AND a.taxpayer_number NOT IN ('000000000', '111111111');
GO

DROP FUNCTION dbo.p3_lev;
GO
