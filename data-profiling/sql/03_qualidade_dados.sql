
USE MoreRhythm;
GO

-- 3.1. Clientes com campos de identificação ou contacto em falta
SELECT
    COUNT(*) AS TotalClientes,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(name)), '') IS NULL
             THEN 1 ELSE 0 END) AS NomeNulo,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(taxpayer_number)), '') IS NULL
             THEN 1 ELSE 0 END) AS NIFNulo,
    SUM(CASE WHEN zone IS NULL THEN 1 ELSE 0 END) AS ZonaNula,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(email)), '') IS NULL
             THEN 1 ELSE 0 END) AS EmailNulo,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(mobile)), '') IS NULL
             THEN 1 ELSE 0 END) AS TelemovelNulo
FROM dbo.customers;
GO

-- 3.2. Produtos com atributos importantes em falta
SELECT
    COUNT(*) AS TotalProdutos,
    SUM(CASE WHEN designation IS NULL
              OR LTRIM(RTRIM(designation)) = ''
             THEN 1 ELSE 0 END) AS DesignacaoEmFalta,
    SUM(CASE WHEN family IS NULL
              OR LTRIM(RTRIM(family)) = ''
             THEN 1 ELSE 0 END) AS FamiliaEmFalta,
    SUM(CASE WHEN category IS NULL THEN 1 ELSE 0 END) AS CategoriaNula,
    SUM(CASE WHEN supplyer IS NULL THEN 1 ELSE 0 END) AS FornecedorNulo,
    SUM(CASE WHEN stock IS NULL THEN 1 ELSE 0 END) AS StockNulo,
    SUM(CASE WHEN current_sell_price IS NULL
             THEN 1 ELSE 0 END) AS PrecoVendaNulo
FROM dbo.products;
GO

-- 3.3. Linhas de fatura com produto ou campos financeiros em falta
SELECT
    COUNT(*) AS TotalLinhasFatura,
    SUM(CASE WHEN product IS NULL
              OR LTRIM(RTRIM(product)) = ''
             THEN 1 ELSE 0 END) AS ProdutoEmFalta,
    SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END) AS QuantidadeNula,
    SUM(CASE WHEN unit_price IS NULL THEN 1 ELSE 0 END) AS PrecoUnitarioNulo,
    SUM(CASE WHEN line_total IS NULL THEN 1 ELSE 0 END) AS TotalLinhaNulo
FROM dbo.invoices_lines;
GO

-- 3.4. Linhas de compra com produto ou campos financeiros em falta
SELECT
    COUNT(*) AS TotalLinhasCompra,
    SUM(CASE WHEN product IS NULL
              OR LTRIM(RTRIM(product)) = ''
             THEN 1 ELSE 0 END) AS ProdutoEmFalta,
    SUM(CASE WHEN quantity IS NULL THEN 1 ELSE 0 END) AS QuantidadeNula,
    SUM(CASE WHEN unit_price IS NULL THEN 1 ELSE 0 END) AS PrecoUnitarioNulo,
    SUM(CASE WHEN line_total IS NULL THEN 1 ELSE 0 END) AS TotalLinhaNulo
FROM dbo.purchases_lines;
GO

-- 3.5. Linhas de compra sem produto: impacto financeiro
SELECT
    COUNT(*) AS TotalLinhasSemProduto,
    SUM(quantity) AS QuantidadeTotal,
    SUM(line_total) AS ValorTotal
FROM dbo.purchases_lines
WHERE product IS NULL
   OR LTRIM(RTRIM(product)) = '';
GO
