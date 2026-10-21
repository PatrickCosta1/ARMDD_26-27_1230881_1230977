
USE MoreRhythm;
GO

-- 5.1. Linhas de fatura cujo total difere de quantidade x preço
SELECT
    invoice_line_stamp_id,
    quantity,
    unit_price,
    line_total,
    quantity * unit_price AS TotalCalculado,
    line_total - (quantity * unit_price) AS Diferenca
FROM dbo.invoices_lines
WHERE ABS(line_total - (quantity * unit_price)) > 0.01
ORDER BY ABS(line_total - (quantity * unit_price)) DESC;
GO

-- 5.2. Comparar totais do cabeçalho com as linhas da fatura
SELECT
    i.invoice_stamp_id,
    i.invoice_date,
    i.products_total AS TotalProdutosCabecalho,
    COUNT(il.invoice_line_stamp_id) AS NumeroLinhas,
    SUM(il.line_total) AS SomaTotaisLinhas,
    SUM(ABS(il.line_total)) AS SomaValoresAbsolutos,
    i.products_total - SUM(il.line_total) AS DiferencaCabecalho
FROM dbo.invoices AS i
INNER JOIN dbo.invoices_lines AS il
    ON il.invoice_stamp_id = i.invoice_stamp_id
GROUP BY
    i.invoice_stamp_id,
    i.invoice_date,
    i.products_total
HAVING ABS(i.products_total - SUM(il.line_total)) > 0.01
ORDER BY i.invoice_date, i.invoice_stamp_id;
GO

-- 5.3. Consultar os valores do cabeçalho de uma fatura
-- Substituir o identificador pelo valor que se pretende investigar.
SELECT
    invoice_stamp_id,
    invoice_date,
    currency,
    products_total,
    shipping_cost,
    total_for_vat,
    vat_value,
    final_total
FROM dbo.invoices
ORDER BY invoice_date, invoice_stamp_id;
GO

-- 5.4. Linhas de fatura com quantidades ou preços negativos
SELECT
    invoice_line_stamp_id,
    invoice_stamp_id,
    product,
    quantity,
    unit_price,
    line_total,
    line_vat
FROM dbo.invoices_lines
WHERE quantity < 0
   OR unit_price < 0
   OR line_total < 0
ORDER BY invoice_stamp_id, invoice_line_stamp_id;
GO
