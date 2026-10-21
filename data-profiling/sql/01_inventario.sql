
USE MoreRhythm;
GO

-- 1.1. Tabelas de negócio e número de registos
SELECT
    s.name AS Esquema,
    t.name AS Tabela,
    SUM(p.rows) AS TotalRegistos
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON t.schema_id = s.schema_id
LEFT JOIN sys.partitions AS p
    ON t.object_id = p.object_id
   AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
  AND t.name <> 'sysdiagrams'
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
GO

-- 1.2. Colunas, tipos de dados e nulabilidade
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    ORDINAL_POSITION,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
GO

-- 1.3. Chaves primárias
SELECT
    t.name AS Tabela,
    c.name AS Coluna,
    kc.name AS NomeChave
FROM sys.key_constraints AS kc
INNER JOIN sys.tables AS t
    ON kc.parent_object_id = t.object_id
INNER JOIN sys.index_columns AS ic
    ON kc.parent_object_id = ic.object_id
   AND kc.unique_index_id = ic.index_id
INNER JOIN sys.columns AS c
    ON ic.object_id = c.object_id
   AND ic.column_id = c.column_id
WHERE kc.type = 'PK'
ORDER BY t.name, ic.key_ordinal;
GO
