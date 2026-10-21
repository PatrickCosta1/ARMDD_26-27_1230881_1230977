
USE MoreRhythm;
GO

-- 6.1. Linhas de fatura sem cabeçalho
SELECT COUNT(*) AS LinhasFaturaSemCabecalho
FROM dbo.invoices_lines AS il
LEFT JOIN dbo.invoices AS i
    ON i.invoice_stamp_id = il.invoice_stamp_id
WHERE i.invoice_stamp_id IS NULL;
GO

-- 6.2. Linhas de compra sem cabeçalho
SELECT COUNT(*) AS LinhasCompraSemCabecalho
FROM dbo.purchases_lines AS pl
LEFT JOIN dbo.purchases AS p
    ON p.purchase_stamp = pl.purchase_stamp
WHERE p.purchase_stamp IS NULL;
GO

-- 6.3. Movimentos de stock sem produto correspondente
SELECT COUNT(*) AS MovimentosSemProduto
FROM dbo.stocks_movements AS sm
LEFT JOIN dbo.products AS p
    ON p.reference = sm.product
WHERE p.reference IS NULL;
GO

-- 6.4. Linhas de fatura com produto não identificado
SELECT COUNT(*) AS LinhasFaturaSemProdutoCorrespondente
FROM dbo.invoices_lines AS il
LEFT JOIN dbo.products AS p
    ON p.reference = il.product
WHERE il.product IS NOT NULL
  AND p.reference IS NULL;
GO

-- 6.5. Linhas de compra com produto não identificado
SELECT COUNT(*) AS LinhasCompraComProdutoInexistente
FROM dbo.purchases_lines AS pl
LEFT JOIN dbo.products AS p
    ON p.reference = pl.product
WHERE pl.product IS NOT NULL
  AND LTRIM(RTRIM(pl.product)) <> ''
  AND p.reference IS NULL;
GO

-- 6.6. Faturas com clientes inexistentes
SELECT COUNT(*) AS FaturasComClienteInexistente
FROM dbo.invoices AS i
LEFT JOIN dbo.customers AS c
    ON c.number = i.customer
WHERE c.number IS NULL;
GO

-- 6.7. Faturas com funcionários inexistentes
SELECT COUNT(*) AS FaturasComFuncionarioInexistente
FROM dbo.invoices AS i
LEFT JOIN dbo.employees AS e
    ON e.number = i.employee
WHERE e.number IS NULL;
GO
