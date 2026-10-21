
USE MoreRhythm;
GO

-- 4.1. Possíveis duplicados pelo número de contribuinte
SELECT
    REPLACE(
        REPLACE(
            REPLACE(
                UPPER(LTRIM(RTRIM(taxpayer_number))),
                ' ', ''
            ),
            '.', ''
        ),
        '-', ''
    ) AS NIF_Normalizado,
    COUNT(*) AS Ocorrencias,
    STRING_AGG(CONVERT(varchar(30), number), ', ') AS NumerosCliente
FROM dbo.customers
WHERE NULLIF(LTRIM(RTRIM(taxpayer_number)), '') IS NOT NULL
GROUP BY
    REPLACE(
        REPLACE(
            REPLACE(
                UPPER(LTRIM(RTRIM(taxpayer_number))),
                ' ', ''
            ),
            '.', ''
        ),
        '-', ''
    )
HAVING COUNT(*) > 1
ORDER BY Ocorrencias DESC;
GO

-- 4.2. Possíveis duplicados pelo nome normalizado
SELECT
    UPPER(LTRIM(RTRIM(name))) AS Nome_Normalizado,
    COUNT(*) AS Ocorrencias,
    STRING_AGG(CONVERT(varchar(30), number), ', ') AS NumerosCliente
FROM dbo.customers
WHERE NULLIF(LTRIM(RTRIM(name)), '') IS NOT NULL
GROUP BY UPPER(LTRIM(RTRIM(name)))
HAVING COUNT(*) > 1
ORDER BY Ocorrencias DESC;
GO

-- 4.3. Inspecionar os dois clientes já identificados
SELECT *
FROM dbo.customers
WHERE number IN (10, 18)
ORDER BY number;
GO

-- 4.4. Comparar a atividade de faturação dos dois clientes
SELECT
    customer AS NumeroCliente,
    COUNT(*) AS NumeroFaturas,
    SUM(final_total) AS TotalFaturado,
    MIN(invoice_date) AS PrimeiraFatura,
    MAX(invoice_date) AS UltimaFatura
FROM dbo.invoices
WHERE customer IN (10, 18)
GROUP BY customer
ORDER BY customer;
GO
