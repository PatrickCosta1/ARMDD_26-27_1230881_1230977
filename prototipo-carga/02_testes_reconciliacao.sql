/*==============================================================================
  Testes de reconciliacao do PROTOTIPO da carga. Executar depois de 01_prototipo_carga.sql.
  Parametro SQLCMD: DM_DB
==============================================================================*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE $(DM_DB);
GO
DECLARE @T TABLE (Id int IDENTITY(1,1), Teste varchar(160), Ok bit, Detalhe varchar(200));

/*------------------------- A. reconciliacao da 1.a carga -------------------*/
DECLARE @fat_ok TABLE (id char(25) PRIMARY KEY);
INSERT @fat_ok   -- expectativa independente: faturas sem linha incoerente (R06), com cabecalho = linhas (R07) e total coerente (R11)
SELECT i.invoice_stamp_id FROM dbo.src_invoices i
WHERE NOT EXISTS (SELECT 1 FROM dbo.src_invoices_lines l WHERE l.invoice_stamp_id = i.invoice_stamp_id AND l.line_total <> l.quantity * l.unit_price)
  AND ABS(i.products_total - (SELECT SUM(line_total) FROM dbo.src_invoices_lines l WHERE l.invoice_stamp_id = i.invoice_stamp_id)) <= 0.01
  AND ABS(i.final_total - (i.products_total + i.shipping_cost + i.vat_value)) <= 0.01;
INSERT @T SELECT 'A1 faturas carregadas = faturas validas da origem (R06, R07, R11)', IIF(COUNT(DISTINCT Numero_Fatura) = (SELECT COUNT(*) FROM @fat_ok), 1, 0),
       CONCAT('facto=', COUNT(DISTINCT Numero_Fatura), ' esperado=', (SELECT COUNT(*) FROM @fat_ok), ' de ', (SELECT COUNT(*) FROM dbo.src_invoices)) FROM dbo.Fact_Vendas;
INSERT @T SELECT 'A2 linhas carregadas = linhas das faturas validas', IIF(COUNT(*) = (SELECT COUNT(*) FROM dbo.src_invoices_lines l JOIN @fat_ok f ON f.id = l.invoice_stamp_id), 1, 0),
       CONCAT('facto=', COUNT(*), ' esperado=', (SELECT COUNT(*) FROM dbo.src_invoices_lines l JOIN @fat_ok f ON f.id = l.invoice_stamp_id), ' de ', (SELECT COUNT(*) FROM dbo.src_invoices_lines)) FROM dbo.Fact_Vendas;
INSERT @T
SELECT 'A3 soma do frete alocado = shipping_cost em todas as faturas carregadas',
       IIF(MAX(ABS(f.fr - i.shipping_cost)) = 0, 1, 0), CONCAT('maior diferenca=', MAX(ABS(f.fr - i.shipping_cost)))
FROM (SELECT Numero_Fatura, SUM(Frete_Alocado) fr FROM dbo.Fact_Vendas GROUP BY Numero_Fatura) f
JOIN dbo.src_invoices i ON i.invoice_stamp_id = f.Numero_Fatura;
INSERT @T
SELECT 'A4 liquido + IVA + frete = final_total em todas as faturas carregadas (tolerancia 0,01)',
       IIF(MAX(ABS(f.tot - i.final_total)) <= 0.01, 1, 0), CONCAT('maior diferenca=', MAX(ABS(f.tot - i.final_total)))
FROM (SELECT Numero_Fatura, SUM(Valor_Liquido + Valor_IVA + Frete_Alocado) tot FROM dbo.Fact_Vendas GROUP BY Numero_Fatura) f
JOIN dbo.src_invoices i ON i.invoice_stamp_id = f.Numero_Fatura;
INSERT @T
SELECT 'A5 soma do liquido = soma de products_total das faturas carregadas',
       IIF(ABS(SUM(f.liq) - SUM(i.products_total)) <= 0.01, 1, 0), CONCAT('facto=', SUM(f.liq), ' origem=', SUM(i.products_total))
FROM (SELECT Numero_Fatura, SUM(Valor_Liquido) liq FROM dbo.Fact_Vendas GROUP BY Numero_Fatura) f
JOIN dbo.src_invoices i ON i.invoice_stamp_id = f.Numero_Fatura;
INSERT @T SELECT 'A6 valores em EUR = valores originais (moeda EURO, taxa 1)',
       IIF(SUM(CASE WHEN Valor_Liquido_EUR <> Valor_Liquido OR Valor_IVA_EUR <> Valor_IVA OR Frete_Alocado_EUR <> Frete_Alocado THEN 1 ELSE 0 END) = 0, 1, 0), NULL FROM dbo.Fact_Vendas;
INSERT @T SELECT 'A7 faturas rejeitadas por R07 nao entram no facto',
       IIF(COUNT(*) = 0, 1, 0), NULL
FROM dbo.Fact_Vendas f WHERE f.Numero_Fatura IN ('ADM06013159092,572514309', 'ADM06022859337,463265852');

/*------------------------ B. cliente consolidado ---------------------------*/
INSERT @T SELECT 'B1 Dim_Cliente: 21 clientes reais + membro -1 (26 menos 2 sem zona menos 3 duplicados)',
       IIF(COUNT(*) = 22, 1, 0), CONCAT('linhas=', COUNT(*)) FROM dbo.Dim_Cliente;
INSERT @T SELECT 'B2 mapa: 10->18, 5->26 ou 26->5 e 8/22 convergem num so sobrevivente',
       IIF((SELECT COUNT(DISTINCT sobrevivente) FROM dbo.map_cliente WHERE origem IN (10, 18)) = 1
        AND (SELECT COUNT(DISTINCT sobrevivente) FROM dbo.map_cliente WHERE origem IN (5, 26)) = 1
        AND (SELECT COUNT(DISTINCT sobrevivente) FROM dbo.map_cliente WHERE origem IN (8, 22)) = 1
        AND (SELECT COUNT(*) FROM dbo.map_cliente WHERE regra <> 'SOBREVIVENTE') = 3, 1, 0),
       (SELECT STRING_AGG(CONCAT(origem, '->', sobrevivente), ' ') FROM dbo.map_cliente WHERE regra <> 'SOBREVIVENTE');
INSERT @T SELECT 'B3 as faturas dos dois clientes de cada par apontam para o mesmo SK_Cliente',
       IIF(SUM(CASE WHEN n_sk > 1 THEN 1 ELSE 0 END) = 0, 1, 0), NULL
FROM (SELECT g, COUNT(DISTINCT SK_Cliente) n_sk FROM (SELECT SK_Cliente, CASE WHEN BK_Cliente_Origem IN (10, 18) THEN 1 WHEN BK_Cliente_Origem IN (5, 26) THEN 2 WHEN BK_Cliente_Origem IN (8, 22) THEN 3 END g FROM dbo.Fact_Vendas) x WHERE g IS NOT NULL GROUP BY g) y;
INSERT @T SELECT 'B4 BK_Cliente_Origem preserva os dois clientes de origem em cada par',
       IIF((SELECT COUNT(DISTINCT BK_Cliente_Origem) FROM dbo.Fact_Vendas WHERE BK_Cliente_Origem IN (10, 18)) = 2
        AND (SELECT COUNT(DISTINCT BK_Cliente_Origem) FROM dbo.Fact_Vendas WHERE BK_Cliente_Origem IN (5, 26)) = 2, 1, 0), NULL;
INSERT @T SELECT 'B5 cliente consolidado 5/26: email valido (o do 26) e telemovel preenchido',
       IIF(Email = 'coro@sapo.pt' AND Telemovel IS NOT NULL, 1, 0), CONCAT(Email, ' / ', Telemovel) FROM dbo.Dim_Cliente WHERE BK_Cliente IN (5, 26) AND Versao_Atual = 1;
INSERT @T SELECT 'B6 clientes sem zona (2 e 20) nao entram na dimensao',
       IIF(COUNT(*) = 0, 1, 0), NULL FROM dbo.Dim_Cliente WHERE BK_Cliente IN (2, 20);
INSERT @T SELECT 'B7 dimensoes: 65 produtos validos (67 menos 2), 14 fornecedores, 6 funcionarios (sem contar o membro -1)',
       IIF((SELECT COUNT(*) FROM dbo.Dim_Produto WHERE SK_Produto > 0) = 65 AND (SELECT COUNT(*) FROM dbo.Dim_Fornecedor WHERE SK_Fornecedor > 0) = 14
        AND (SELECT COUNT(*) FROM dbo.Dim_Funcionario WHERE SK_Funcionario > 0) = 6, 1, 0),
       CONCAT((SELECT COUNT(*) FROM dbo.Dim_Produto WHERE SK_Produto > 0), '/', (SELECT COUNT(*) FROM dbo.Dim_Fornecedor WHERE SK_Fornecedor > 0), '/', (SELECT COUNT(*) FROM dbo.Dim_Funcionario WHERE SK_Funcionario > 0));
INSERT @T SELECT 'B8 vendedor atribuido: seller=0 fica NULL (clientes 24 e 25; 2 e 20 nao entram)', IIF(SUM(CASE WHEN Vendedor_Atribuido IS NULL THEN 1 ELSE 0 END) = 2, 1, 0), CONCAT('sem vendedor=', SUM(CASE WHEN Vendedor_Atribuido IS NULL THEN 1 ELSE 0 END))
FROM dbo.Dim_Cliente WHERE SK_Cliente > 0;

INSERT @T SELECT 'B9 funcionarios 2 e 5 (email com dois @) carregam com Email NULL; os restantes mantem o email',
       IIF(SUM(CASE WHEN BK_Funcionario IN (2, 5) AND Email IS NULL THEN 1 ELSE 0 END) = 2
       AND SUM(CASE WHEN BK_Funcionario NOT IN (2, 5) AND Email IS NOT NULL THEN 1 ELSE 0 END) = 4, 1, 0),
       CONCAT('sem email=', SUM(CASE WHEN Email IS NULL THEN 1 ELSE 0 END))
FROM dbo.Dim_Funcionario WHERE SK_Funcionario > 0;

SELECT Id, IIF(Ok = 1, 'OK', 'FALHOU') AS Resultado, Teste, Detalhe FROM @T ORDER BY Id;
GO
