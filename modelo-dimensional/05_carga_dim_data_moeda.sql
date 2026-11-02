/*==============================================================================
  Data Mart de Vendas - More Rhythm, SA
  Carga inicial de Dim_Data (2020-2035) e Dim_Taxa_Cambio (EUR = 1)
  Pre-requisito: 04_ddl_data_mart.sql
  Idempotente: so insere datas / taxas que ainda nao existem.
  Parametros (SQLCMD):  :setvar DM_DB MoreRhythm_DM
                        :setvar ANO_INICIO 2020   :setvar ANO_FIM 2035
  Nao depende da LANGUAGE/DATEFIRST da sessao (nomes e dia da semana explicitos).
==============================================================================*/
SET NOCOUNT ON;
-- indices filtrados exigem QUOTED_IDENTIFIER ON (sqlcmd/SSIS tem-no OFF por omissao)
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

SET DATEFIRST 1;
GO
USE $(DM_DB);
GO

DECLARE @Inicio date = DATEFROMPARTS($(ANO_INICIO), 1, 1);
DECLARE @Fim    date = DATEFROMPARTS($(ANO_FIM), 12, 31);

/* Calendario: uma linha por dia */
;WITH Dias AS (
    SELECT @Inicio AS D
    UNION ALL
    SELECT DATEADD(DAY, 1, D) FROM Dias WHERE D < @Fim
)
SELECT D INTO #Dias FROM Dias OPTION (MAXRECURSION 0);

/* Pascoa (algoritmo gregoriano de Meeus/Jones/Butcher) para cada ano */
DROP TABLE IF EXISTS #Pascoa;
CREATE TABLE #Pascoa (A smallint PRIMARY KEY, P date NOT NULL);
INSERT INTO #Pascoa (A, P)
SELECT A,
       DATEADD(DAY, (hh + ll - 7 * mm + 114) % 31,
               DATEFROMPARTS(A, (hh + ll - 7 * mm + 114) / 31, 1))
FROM (
    SELECT A, hh, ll, (a1 + 11 * hh + 22 * ll) / 451 AS mm
    FROM (
        SELECT A, a1, hh,
               (32 + 2 * (A / 100 % 4) + 2 * ((A % 100) / 4) - hh - ((A % 100) % 4)) % 7 AS ll
        FROM (
            SELECT A, A % 19 AS a1,
                   (19 * (A % 19) + (A / 100) - (A / 100 / 4)
                    - ((A / 100 - (A / 100 + 8) / 25 + 1) / 3) + 15) % 30 AS hh
            FROM (SELECT DISTINCT CAST(YEAR(D) AS smallint) AS A FROM #Dias) y
        ) q1
    ) q2
) q3;

/* Feriados nacionais de Portugal (fixos e moveis) */
DROP TABLE IF EXISTS #Feriados;
CREATE TABLE #Feriados (D date PRIMARY KEY, Nome varchar(60) NOT NULL);
INSERT INTO #Feriados (D, Nome)
SELECT DATEFROMPARTS(A, f.M, f.Dd), f.Nome
FROM #Pascoa
CROSS APPLY (VALUES
    (1, 1,  'Ano Novo'),
    (4, 25, 'Dia da Liberdade'),
    (5, 1,  'Dia do Trabalhador'),
    (6, 10, 'Dia de Portugal'),
    (8, 15, 'Assuncao de Nossa Senhora'),
    (10, 5, 'Implantacao da Republica'),
    (11, 1, 'Todos os Santos'),
    (12, 1, 'Restauracao da Independencia'),
    (12, 8, 'Imaculada Conceicao'),
    (12, 25,'Natal')) f (M, Dd, Nome)
UNION ALL SELECT DATEADD(DAY, -2, P), 'Sexta-feira Santa' FROM #Pascoa
UNION ALL SELECT P,                   'Pascoa'            FROM #Pascoa
UNION ALL SELECT DATEADD(DAY, 60, P), 'Corpo de Deus'     FROM #Pascoa;

INSERT INTO dbo.Dim_Data (SK_Data, Data, Dia_Mes, Dia_Ano, Dia_Semana, Nome_Dia_Semana, Fim_Semana, Ultimo_Dia_Mes,
                          Semana_Ano, Ano_Semana_ISO, Mes, Nome_Mes, Ano_Mes, Trimestre, Quadrimestre, Semestre,
                          Estacao_Ano, Ano, Feriado_Nacional, Nome_Feriado)
SELECT
    YEAR(d.D) * 10000 + MONTH(d.D) * 100 + DAY(d.D),
    d.D,
    DAY(d.D),
    DATEPART(DAYOFYEAR, d.D),
    w.DS,
    CHOOSE(w.DS, 'Segunda-feira', 'Terca-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sabado', 'Domingo'),
    CASE WHEN w.DS IN (6, 7) THEN 1 ELSE 0 END,
    CASE WHEN d.D = EOMONTH(d.D) THEN 1 ELSE 0 END,
    DATEPART(ISO_WEEK, d.D),
    YEAR(DATEADD(DAY, 26 - DATEPART(ISO_WEEK, d.D), d.D)),   -- ano ISO da semana
    MONTH(d.D),
    CHOOSE(MONTH(d.D), 'Janeiro', 'Fevereiro', 'Marco', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto',
                       'Setembro', 'Outubro', 'Novembro', 'Dezembro'),
    YEAR(d.D) * 100 + MONTH(d.D),
    (MONTH(d.D) - 1) / 3 + 1,
    (MONTH(d.D) - 1) / 4 + 1,
    (MONTH(d.D) - 1) / 6 + 1,
    CASE                                                     -- datas fixas (ver 02_modelo_dimensional_dicionario_scd.md)
        WHEN MONTH(d.D) * 100 + DAY(d.D) BETWEEN 320 AND 620 THEN 'Primavera'
        WHEN MONTH(d.D) * 100 + DAY(d.D) BETWEEN 621 AND 922 THEN 'Verao'
        WHEN MONTH(d.D) * 100 + DAY(d.D) BETWEEN 923 AND 1220 THEN 'Outono'
        ELSE 'Inverno'
    END,
    YEAR(d.D),
    CASE WHEN fe.D IS NULL THEN 0 ELSE 1 END,
    fe.Nome
FROM #Dias d
CROSS APPLY (SELECT (DATEDIFF(DAY, '19000101', d.D) % 7) + 1 AS DS) w   -- 1900-01-01 foi segunda-feira
LEFT JOIN #Feriados fe ON fe.D = d.D
WHERE NOT EXISTS (SELECT 1 FROM dbo.Dim_Data x WHERE x.SK_Data = YEAR(d.D) * 10000 + MONTH(d.D) * 100 + DAY(d.D));

/* Taxa de cambio: EUR = 1 para todos os dias do calendario (nao ha outras moedas na origem) */
INSERT INTO dbo.Dim_Taxa_Cambio (SK_Data, SK_Moeda, Taxa_Para_EUR)
SELECT dd.SK_Data, m.SK_Moeda, 1
FROM dbo.Dim_Data dd
CROSS JOIN dbo.Dim_Moeda m
WHERE m.Codigo_ISO = 'EUR' AND dd.SK_Data <> -1
  AND NOT EXISTS (SELECT 1 FROM dbo.Dim_Taxa_Cambio t WHERE t.SK_Data = dd.SK_Data AND t.SK_Moeda = m.SK_Moeda);

/* GBP: a carga de cotacoes (BCE / Banco de Portugal) fica a cargo do ETL quando existir sucursal no Reino Unido. */
DROP TABLE #Dias, #Pascoa, #Feriados;
GO
