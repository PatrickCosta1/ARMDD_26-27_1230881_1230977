/*==============================================================================
  Testes do PROTOTIPO da carga: repeticao, SCD1, SCD2 com remapeamento de
  cliente duplicado e alteracao do frete no cabecalho. Altera as copias src_*
  (nunca a MoreRhythm). Executar depois de 01_prototipo_carga.sql (e dos testes 02, que nao alteram dados).
  Parametro SQLCMD: DM_DB
==============================================================================*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE $(DM_DB);
GO
DROP TABLE IF EXISTS dbo.t_res;
CREATE TABLE dbo.t_res (Id int IDENTITY(1,1), Teste varchar(170), Ok bit, Detalhe varchar(250));
GO
CREATE OR ALTER PROCEDURE dbo.usp_cargas @lote bigint AS
BEGIN
    EXEC dbo.usp_load_dim_cliente; EXEC dbo.usp_load_dim_produto; EXEC dbo.usp_load_dim_fornecedor; EXEC dbo.usp_load_dim_funcionario;
    EXEC dbo.usp_load_fact @lote = @lote;
END;
GO

/*---------------- C1. repetir a carga sem alteracoes: nada muda ------------*/
DECLARE @antes TABLE (cli int, pro int, forn int, func int, fact int, hash_soma bigint);
INSERT @antes SELECT (SELECT COUNT(*) FROM dbo.Dim_Cliente), (SELECT COUNT(*) FROM dbo.Dim_Produto), (SELECT COUNT(*) FROM dbo.Dim_Fornecedor),
    (SELECT COUNT(*) FROM dbo.Dim_Funcionario), (SELECT COUNT(*) FROM dbo.Fact_Vendas), (SELECT SUM(CAST(SK_Cliente AS bigint) + SK_Produto) FROM dbo.Fact_Vendas);
DECLARE @r TABLE (ins int, upd int);
INSERT @r EXEC dbo.usp_load_dim_cliente;   -- (sem resultado)
EXEC dbo.usp_load_dim_produto; EXEC dbo.usp_load_dim_fornecedor; EXEC dbo.usp_load_dim_funcionario;
INSERT @r EXEC dbo.usp_load_fact @lote = 2;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C1 2.a carga sem alteracoes: 0 linhas inseridas, 0 atualizadas, dimensoes iguais',
       IIF((SELECT ins FROM @r) = 0 AND (SELECT upd FROM @r) = 0 AND a.cli = (SELECT COUNT(*) FROM dbo.Dim_Cliente) AND a.pro = (SELECT COUNT(*) FROM dbo.Dim_Produto)
           AND a.forn = (SELECT COUNT(*) FROM dbo.Dim_Fornecedor) AND a.func = (SELECT COUNT(*) FROM dbo.Dim_Funcionario) AND a.fact = (SELECT COUNT(*) FROM dbo.Fact_Vendas), 1, 0),
       CONCAT('ins=', (SELECT ins FROM @r), ' upd=', (SELECT upd FROM @r)) FROM @antes a;
GO

/*---------------- C2. SCD1: o nome muda e nao ha nova versao ---------------*/
UPDATE dbo.src_customers SET name = 'Luz e Som, Lda (novo nome)', last_update_date = '2026-01-10' WHERE number = 8;
DECLARE @r TABLE (ins int, upd int);
EXEC dbo.usp_load_dim_cliente; EXEC dbo.usp_load_dim_produto; EXEC dbo.usp_load_dim_fornecedor; EXEC dbo.usp_load_dim_funcionario;
INSERT @r EXEC dbo.usp_load_fact @lote = 3;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C2 SCD1: nome do cliente 8 atualizado na versao existente (sem nova versao); facto intacto',
       IIF(COUNT(*) = 1 AND MAX(Nome) = 'Luz e Som, Lda (novo nome)' AND (SELECT upd FROM @r) = 0 AND (SELECT ins FROM @r) = 0, 1, 0), CONCAT('versoes=', COUNT(*))
FROM dbo.Dim_Cliente WHERE BK_Cliente = 8;
GO

/*------- C3. SCD2 + duplicado: zona do cliente 5 muda; nova fatura do cliente 26 ---*/
DECLARE @fat_antiga char(25) = (SELECT TOP 1 i.invoice_stamp_id FROM dbo.src_invoices i
    WHERE i.customer IN (5, 26) AND EXISTS (SELECT 1 FROM dbo.Fact_Vendas f WHERE f.Numero_Fatura = i.invoice_stamp_id) ORDER BY i.invoice_date);
DECLARE @sk_v1 int = (SELECT SK_Cliente FROM dbo.Dim_Cliente WHERE BK_Cliente = 5 AND Versao_Atual = 1);
DECLARE @n_linhas int = (SELECT COUNT(*) FROM dbo.src_invoices_lines WHERE invoice_stamp_id = @fat_antiga);

-- zona Norte -> Centro e nome muito diferente: se o mapa fosse recalculado, o par 5/26 desfazia-se
UPDATE dbo.src_customers SET zone = 2, name = 'Associacao Cultural Exemplo', last_update_date = '2026-01-15' WHERE number = 5;
INSERT dbo.src_invoices (invoice_stamp_id, invoice_date, customer, employee, payment_date, currency, products_total, shipping_cost,
                         total_for_vat, vat_value, final_total, create_date, create_time, last_update_date, last_update_time)
SELECT 'TESTE-FATURA-0000000001', '2026-01-20', 26, employee, '2026-02-20', currency, products_total, shipping_cost, total_for_vat, vat_value,
       final_total, '2026-01-20', create_time, '2026-01-20', last_update_time FROM dbo.src_invoices WHERE invoice_stamp_id = @fat_antiga;
INSERT dbo.src_invoices_lines (invoice_line_stamp_id, invoice_stamp_id, product, quantity, unit_price, line_total, line_vat,
                               create_date, create_time, last_update_date, last_update_time)
SELECT CONCAT('TESTE-LINHA-', ROW_NUMBER() OVER (ORDER BY invoice_line_stamp_id), '-00000'), 'TESTE-FATURA-0000000001', product, quantity, unit_price,
       line_total, line_vat, '2026-01-20', create_time, '2026-01-20', last_update_time FROM dbo.src_invoices_lines WHERE invoice_stamp_id = @fat_antiga;

DECLARE @r TABLE (ins int, upd int);
EXEC dbo.usp_load_dim_cliente; EXEC dbo.usp_load_dim_produto; EXEC dbo.usp_load_dim_fornecedor; EXEC dbo.usp_load_dim_funcionario;
INSERT @r EXEC dbo.usp_load_fact @lote = 4;

INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C3a SCD2: o cliente 5 tem 2 versoes (Norte ate 14/01, Centro desde 15/01)',
       IIF(COUNT(*) = 2 AND SUM(CASE WHEN Zona = 'Norte' AND Data_Fim = '2026-01-14' AND Versao_Atual = 0 THEN 1 ELSE 0 END) = 1
           AND SUM(CASE WHEN Zona = 'Centro' AND Data_Inicio = '2026-01-15' AND Versao_Atual = 1 THEN 1 ELSE 0 END) = 1, 1, 0),
       (SELECT STRING_AGG(CONCAT(Zona, ' ', Data_Inicio, '..', Data_Fim), '; ') FROM dbo.Dim_Cliente WHERE BK_Cliente = 5)
FROM dbo.Dim_Cliente WHERE BK_Cliente = 5;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C3b as faturas antigas do grupo 5/26 continuam na versao Norte (historico preservado)',
       IIF(COUNT(*) > 0 AND SUM(CASE WHEN c.Zona <> 'Norte' THEN 1 ELSE 0 END) = 0, 1, 0), CONCAT('linhas=', COUNT(*))
FROM dbo.Fact_Vendas f JOIN dbo.Dim_Cliente c ON c.SK_Cliente = f.SK_Cliente WHERE f.BK_Cliente_Origem IN (5, 26) AND f.SK_Data_Fatura < 20260115;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C3c a fatura nova do cliente 26 (duplicado) entra na versao Centro do sobrevivente 5, com origem 26',
       IIF(COUNT(*) = @n_linhas AND SUM(CASE WHEN c.Zona = 'Centro' AND c.BK_Cliente = 5 AND f.BK_Cliente_Origem = 26 THEN 1 ELSE 0 END) = COUNT(*), 1, 0),
       CONCAT('linhas=', COUNT(*), ' esperadas=', @n_linhas)
FROM dbo.Fact_Vendas f JOIN dbo.Dim_Cliente c ON c.SK_Cliente = f.SK_Cliente WHERE f.Numero_Fatura = 'TESTE-FATURA-0000000001';
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C3d so as linhas novas foram inseridas; nenhuma linha antiga foi atualizada',
       IIF((SELECT ins FROM @r) = @n_linhas AND (SELECT upd FROM @r) = 0, 1, 0), CONCAT('ins=', (SELECT ins FROM @r), ' upd=', (SELECT upd FROM @r))
FROM @r;
GO

/*----- C4. o frete do cabecalho muda: todas as linhas da fatura sao realocadas ----*/
DECLARE @fat char(25) = (SELECT TOP 1 Numero_Fatura FROM dbo.Fact_Vendas WHERE Numero_Fatura NOT LIKE 'TESTE%' GROUP BY Numero_Fatura HAVING COUNT(*) >= 2 ORDER BY Numero_Fatura);
DECLARE @n int = (SELECT COUNT(*) FROM dbo.src_invoices_lines WHERE invoice_stamp_id = @fat);
UPDATE dbo.src_invoices SET shipping_cost += 10, total_for_vat += 10, final_total += 10, last_update_date = '2026-02-01' WHERE invoice_stamp_id = @fat;
DECLARE @r TABLE (ins int, upd int);
EXEC dbo.usp_load_dim_cliente; EXEC dbo.usp_load_dim_produto; EXEC dbo.usp_load_dim_fornecedor; EXEC dbo.usp_load_dim_funcionario;
INSERT @r EXEC dbo.usp_load_fact @lote = 5;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C4 frete do cabecalho +10: as n linhas da fatura sao atualizadas e a soma do frete = novo shipping_cost',
       IIF((SELECT upd FROM @r) = @n AND (SELECT ins FROM @r) = 0 AND ABS(SUM(f.Frete_Alocado) - i.shipping_cost) = 0, 1, 0),
       CONCAT('upd=', (SELECT upd FROM @r), ' esperadas=', @n, ' soma=', SUM(f.Frete_Alocado), ' frete=', i.shipping_cost)
FROM dbo.Fact_Vendas f JOIN dbo.src_invoices i ON i.invoice_stamp_id = f.Numero_Fatura WHERE f.Numero_Fatura = @fat GROUP BY i.shipping_cost;
GO

/*------------------ C5. integridade das versoes SCD2 em todas as dimensoes ------*/
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C5 Dim_Cliente: uma versao corrente por BK e versoes sem sobreposicao',
       IIF((SELECT COUNT(*) FROM (SELECT BK_Cliente FROM dbo.Dim_Cliente WHERE SK_Cliente > 0 GROUP BY BK_Cliente HAVING SUM(CAST(Versao_Atual AS int)) <> 1) x) = 0
       AND (SELECT COUNT(*) FROM dbo.Dim_Cliente a JOIN dbo.Dim_Cliente b ON a.BK_Cliente = b.BK_Cliente AND a.SK_Cliente < b.SK_Cliente
            WHERE a.SK_Cliente > 0 AND a.Data_Inicio <= b.Data_Fim AND b.Data_Inicio <= a.Data_Fim) = 0, 1, 0), NULL;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C6 nenhuma linha do facto aponta para o membro -1 de cliente, produto ou funcionario',
       IIF(COUNT(*) = 0, 1, 0), NULL FROM dbo.Fact_Vendas WHERE SK_Cliente = -1 OR SK_Produto = -1 OR SK_Funcionario = -1;

/*------ C7. o hash distingue a posicao de um NULL (CONCAT com separadores explicitos) ------*/
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C7 hash: (a, NULL, b) e (a, b, NULL) dao valores diferentes',
       IIF(HASHBYTES('SHA2_256', CONCAT('a', '|', NULL, '|', 'b')) <> HASHBYTES('SHA2_256', CONCAT('a', '|', 'b', '|', NULL)), 1, 0), NULL;
GO

/*------ C8. R08: uma fatura com uma linha por resolver nao carrega nenhuma linha ------*/
DECLARE @fat8 char(25) = (SELECT TOP 1 invoice_stamp_id FROM dbo.src_invoices_lines WHERE invoice_stamp_id IN (SELECT Numero_Fatura FROM dbo.Fact_Vendas)
                          GROUP BY invoice_stamp_id HAVING COUNT(*) >= 2 ORDER BY invoice_stamp_id);
SELECT * INTO #i8 FROM dbo.src_invoices WHERE invoice_stamp_id = @fat8;
SELECT * INTO #l8 FROM dbo.src_invoices_lines WHERE invoice_stamp_id = @fat8;
UPDATE #i8 SET invoice_stamp_id = 'TESTE-FATURA-0000000008', invoice_date = '2026-03-02', last_update_date = '2026-03-02';
UPDATE #l8 SET invoice_stamp_id = 'TESTE-FATURA-0000000008', invoice_line_stamp_id = CONCAT('TESTE8-', RIGHT(invoice_line_stamp_id, 15)),
               last_update_date = '2026-03-02';
UPDATE TOP (1) #l8 SET product = 'Z001';     -- produto rejeitado (R04): sem versao na dimensao
INSERT dbo.src_invoices SELECT * FROM #i8;
INSERT dbo.src_invoices_lines SELECT * FROM #l8;
DECLARE @r8 TABLE (ins int, upd int);
INSERT @r8 EXEC dbo.usp_load_fact @lote = 6;
INSERT dbo.t_res (Teste, Ok, Detalhe)
SELECT 'C8 R08: fatura com uma linha por resolver nao carrega nenhuma das suas linhas',
       IIF(COUNT(*) = 0, 1, 0), CONCAT('linhas carregadas=', COUNT(*), ' (esperado 0)')
FROM dbo.Fact_Vendas WHERE Numero_Fatura = 'TESTE-FATURA-0000000008';
GO

SELECT Id, IIF(Ok = 1, 'OK', 'FALHOU') AS Resultado, Teste, Detalhe FROM dbo.t_res ORDER BY Id;
GO
