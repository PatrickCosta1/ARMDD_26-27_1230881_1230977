
USE MoreRhythm;
GO

-- 2.1. Chaves estrangeiras e respetivas colunas
SELECT
    fk.name AS NomeRelacao,
    OBJECT_SCHEMA_NAME(fk.parent_object_id) AS EsquemaOrigem,
    OBJECT_NAME(fk.parent_object_id) AS TabelaOrigem,
    c1.name AS ColunaOrigem,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS EsquemaDestino,
    OBJECT_NAME(fk.referenced_object_id) AS TabelaDestino,
    c2.name AS ColunaDestino
FROM sys.foreign_keys AS fk
INNER JOIN sys.foreign_key_columns AS fkc
    ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns AS c1
    ON fkc.parent_object_id = c1.object_id
   AND fkc.parent_column_id = c1.column_id
INNER JOIN sys.columns AS c2
    ON fkc.referenced_object_id = c2.object_id
   AND fkc.referenced_column_id = c2.column_id
ORDER BY TabelaOrigem, NomeRelacao;
GO
