/*==============================================================================
  Data Mart de Vendas - More Rhythm, SA
  Script DDL (SQL Server) - baseado em 02_modelo_dimensional_dicionario_scd.md
  Ordem: dimensoes -> factos -> membros "Desconhecido" -> dados de apoio
  Nota: o nome da base de dados e configuravel no projeto SSIS (parametros);
        aqui usa-se MoreRhythm_DM por omissao.
==============================================================================*/
IF DB_ID(N'MoreRhythm_DM') IS NULL
    CREATE DATABASE MoreRhythm_DM;
GO
USE MoreRhythm_DM;
GO

/*------------------------------ DIMENSAO DATA ------------------------------*/
CREATE TABLE dbo.Dim_Data (
    SK_Data           int          NOT NULL,            -- yyyymmdd; -1 = sem data
    Data              date         NOT NULL,
    Dia_Mes           tinyint      NOT NULL,
    Dia_Ano           smallint     NOT NULL,
    Dia_Semana        tinyint      NOT NULL,            -- 1=segunda ... 7=domingo (ISO)
    Nome_Dia_Semana   varchar(15)  NOT NULL,
    Fim_Semana        bit          NOT NULL,
    Ultimo_Dia_Mes    bit          NOT NULL,
    Semana_Ano        tinyint      NOT NULL,            -- semana ISO
    Ano_Semana_ISO    smallint     NOT NULL,
    Mes               tinyint      NOT NULL,
    Nome_Mes          varchar(15)  NOT NULL,
    Ano_Mes           int          NOT NULL,            -- yyyymm
    Trimestre         tinyint      NOT NULL,
    Quadrimestre      tinyint      NOT NULL,
    Semestre          tinyint      NOT NULL,
    Estacao_Ano       varchar(10)  NOT NULL,
    Ano               smallint     NOT NULL,
    Feriado_Nacional  bit          NOT NULL,
    Nome_Feriado      varchar(60)  NULL,
    CONSTRAINT PK_Dim_Data PRIMARY KEY CLUSTERED (SK_Data),
    CONSTRAINT UQ_Dim_Data_Data UNIQUE (Data)
);
GO

/*----------------------------- DIMENSAO CLIENTE ----------------------------*/
CREATE TABLE dbo.Dim_Cliente (
    SK_Cliente               int           IDENTITY(1,1) NOT NULL,
    BK_Cliente               numeric(9,0)  NOT NULL,     -- customers.number (sobrevivente)
    Nome                     nvarchar(55)  NOT NULL,     -- SCD1
    NIF                      varchar(20)   NOT NULL,     -- SCD1 ('N/D' se em falta, vazio ou 000000000)
    Contacto                 nvarchar(30)  NULL,         -- SCD1
    Email                    varchar(45)   NULL,         -- SCD1
    Telefone                 varchar(60)   NULL,         -- SCD1
    Telemovel                varchar(45)   NULL,         -- SCD1
    Morada                   nvarchar(55)  NULL,         -- SCD1
    Codigo_Postal            varchar(45)   NULL,         -- SCD1
    Cidade                   nvarchar(43)  NOT NULL,     -- SCD2
    Zona                     nvarchar(50)  NOT NULL,     -- SCD2 ('Zona desconhecida' se customers.zone NULL)
    Pais                     nvarchar(30)  NOT NULL,     -- SCD2 (derivado da zona; 'Desconhecido' se sem zona)
    Tipo_Cliente             nvarchar(20)  NOT NULL,     -- SCD2
    Segmento                 nvarchar(25)  NOT NULL,     -- SCD2
    Vendedor_Atribuido       nvarchar(30)  NULL,         -- SCD2 (seller = 0 -> NULL)
    Dias_Pagamento           smallint      NULL,         -- SCD1
    Data_Inicio              date          NOT NULL,
    Data_Fim                 date          NOT NULL CONSTRAINT DF_Dim_Cliente_Fim DEFAULT ('9999-12-31'),
    Versao_Atual             bit           NOT NULL CONSTRAINT DF_Dim_Cliente_Atual DEFAULT (1),
    Data_Criacao_Origem      datetime2(0)  NOT NULL,
    Data_Atualizacao_Origem  datetime2(0)  NOT NULL,
    CONSTRAINT PK_Dim_Cliente PRIMARY KEY CLUSTERED (SK_Cliente),
    CONSTRAINT UQ_Dim_Cliente_Versao UNIQUE (BK_Cliente, Data_Inicio)
);
GO

/*----------------------------- DIMENSAO PRODUTO ----------------------------*/
CREATE TABLE dbo.Dim_Produto (
    SK_Produto               int           IDENTITY(1,1) NOT NULL,
    BK_Produto               char(18)      NOT NULL,     -- products.reference
    Designacao               nvarchar(60)  NOT NULL,     -- SCD1
    BK_Familia               varchar(18)   NOT NULL,
    Familia                  nvarchar(60)  NOT NULL,     -- SCD2
    Classificacao_Familia    nvarchar(20)  NULL,         -- SCD2
    BK_Categoria             int           NOT NULL,
    Categoria                nvarchar(35)  NOT NULL,     -- SCD2
    Classificacao_Produto    nvarchar(20)  NULL,         -- SCD2
    Taxa_IVA                 decimal(5,2)  NULL,         -- SCD2
    Data_Inicio              date          NOT NULL,
    Data_Fim                 date          NOT NULL CONSTRAINT DF_Dim_Produto_Fim DEFAULT ('9999-12-31'),
    Versao_Atual             bit           NOT NULL CONSTRAINT DF_Dim_Produto_Atual DEFAULT (1),
    Data_Criacao_Origem      datetime2(0)  NOT NULL,
    Data_Atualizacao_Origem  datetime2(0)  NOT NULL,
    CONSTRAINT PK_Dim_Produto PRIMARY KEY CLUSTERED (SK_Produto),
    CONSTRAINT UQ_Dim_Produto_Versao UNIQUE (BK_Produto, Data_Inicio)
);
GO

/*---------------------------- DIMENSAO FORNECEDOR --------------------------*/
CREATE TABLE dbo.Dim_Fornecedor (
    SK_Fornecedor            int           IDENTITY(1,1) NOT NULL,
    BK_Fornecedor            numeric(9,0)  NOT NULL,     -- suplliers.number
    Nome                     nvarchar(55)  NOT NULL,     -- SCD1
    NIF                      varchar(20)   NOT NULL,     -- SCD1
    Tipo_Fornecedor          nvarchar(20)  NOT NULL,     -- SCD2
    Nacionalidade            nvarchar(20)  NULL,         -- SCD1
    Cidade                   nvarchar(43)  NOT NULL,     -- SCD2
    Zona                     nvarchar(50)  NULL,         -- SCD2 (NULL -> 'Zona desconhecida' na carga)
    Morada                   nvarchar(55)  NULL,         -- SCD1
    Codigo_Postal            varchar(45)   NULL,         -- SCD1
    Contacto                 nvarchar(30)  NULL,         -- SCD1
    Cargo_Contacto           nvarchar(15)  NULL,         -- SCD1
    Email                    varchar(45)   NULL,         -- SCD1
    Telefone                 varchar(60)   NULL,         -- SCD1
    Telemovel                varchar(45)   NULL,         -- SCD1
    Dias_Pagamento           smallint      NULL,         -- SCD1
    Data_Inicio              date          NOT NULL,
    Data_Fim                 date          NOT NULL CONSTRAINT DF_Dim_Fornecedor_Fim DEFAULT ('9999-12-31'),
    Versao_Atual             bit           NOT NULL CONSTRAINT DF_Dim_Fornecedor_Atual DEFAULT (1),
    Data_Criacao_Origem      datetime2(0)  NOT NULL,
    Data_Atualizacao_Origem  datetime2(0)  NOT NULL,
    CONSTRAINT PK_Dim_Fornecedor PRIMARY KEY CLUSTERED (SK_Fornecedor),
    CONSTRAINT UQ_Dim_Fornecedor_Versao UNIQUE (BK_Fornecedor, Data_Inicio)
);
GO

/*---------------------------- DIMENSAO FUNCIONARIO -------------------------*/
CREATE TABLE dbo.Dim_Funcionario (
    SK_Funcionario           int           IDENTITY(1,1) NOT NULL,
    BK_Funcionario           numeric(5,0)  NOT NULL,     -- employees.number
    Codigo                   varchar(20)   NOT NULL,     -- SCD1
    Nome                     nvarchar(30)  NOT NULL,     -- SCD1
    Email                    varchar(100)  NOT NULL,     -- SCD1
    Grupo                    nvarchar(20)  NOT NULL,     -- SCD2
    Departamento             nvarchar(20)  NOT NULL,     -- SCD2
    BK_Chefe                 numeric(5,0)  NULL,         -- SCD2
    Nome_Chefe               nvarchar(30)  NULL,         -- SCD2
    Data_Inicio              date          NOT NULL,
    Data_Fim                 date          NOT NULL CONSTRAINT DF_Dim_Funcionario_Fim DEFAULT ('9999-12-31'),
    Versao_Atual             bit           NOT NULL CONSTRAINT DF_Dim_Funcionario_Atual DEFAULT (1),
    Data_Criacao_Origem      datetime2(0)  NOT NULL,
    Data_Atualizacao_Origem  datetime2(0)  NOT NULL,
    CONSTRAINT PK_Dim_Funcionario PRIMARY KEY CLUSTERED (SK_Funcionario),
    CONSTRAINT UQ_Dim_Funcionario_Versao UNIQUE (BK_Funcionario, Data_Inicio)
);
GO

/*------------------------- DIMENSAO MOEDA / TAXAS --------------------------*/
CREATE TABLE dbo.Dim_Moeda (
    SK_Moeda     smallint     IDENTITY(1,1) NOT NULL,
    Codigo_ISO   char(3)      NOT NULL,                  -- EUR, GBP
    Nome         nvarchar(30) NOT NULL,
    Simbolo      nvarchar(3)  NOT NULL,
    CONSTRAINT PK_Dim_Moeda PRIMARY KEY CLUSTERED (SK_Moeda),
    CONSTRAINT UQ_Dim_Moeda_ISO UNIQUE (Codigo_ISO)
);
GO

CREATE TABLE dbo.Dim_Taxa_Cambio (
    SK_Data        int            NOT NULL,
    SK_Moeda       smallint       NOT NULL,
    Taxa_Para_EUR  decimal(18,8)  NOT NULL,              -- 1 unidade da moeda = X EUR
    CONSTRAINT PK_Dim_Taxa_Cambio PRIMARY KEY CLUSTERED (SK_Data, SK_Moeda),
    CONSTRAINT FK_Taxa_Data  FOREIGN KEY (SK_Data)  REFERENCES dbo.Dim_Data (SK_Data),
    CONSTRAINT FK_Taxa_Moeda FOREIGN KEY (SK_Moeda) REFERENCES dbo.Dim_Moeda (SK_Moeda),
    CONSTRAINT CK_Taxa_Positiva CHECK (Taxa_Para_EUR > 0)
);
GO

/*------------------------------ TABELA DE FACTOS ---------------------------*/
CREATE TABLE dbo.Fact_Vendas (
    SK_Venda                 bigint        IDENTITY(1,1) NOT NULL,
    SK_Data_Fatura           int           NOT NULL,
    SK_Data_Pagamento        int           NOT NULL,     -- -1 = sem data de pagamento
    SK_Cliente               int           NOT NULL,
    SK_Produto               int           NOT NULL,
    SK_Fornecedor            int           NOT NULL,     -- -1 = produto sem fornecedor
    SK_Funcionario           int           NOT NULL,
    SK_Moeda                 smallint      NOT NULL,
    Numero_Fatura           char(25)      NOT NULL,     -- dimensao degenerada
    BK_Linha_Fatura          char(25)      NOT NULL,     -- invoices_lines.invoice_line_stamp_id
    Quantidade               decimal(14,4) NOT NULL,     -- negativa em devolucoes
    Preco_Unitario           decimal(19,6) NOT NULL,     -- nao aditivo
    Valor_Liquido            decimal(19,6) NOT NULL,     -- sem IVA e sem frete
    Valor_IVA                decimal(19,6) NOT NULL,
    Frete_Alocado            decimal(19,6) NOT NULL,
    Taxa_Cambio              decimal(18,8) NOT NULL,
    Valor_Liquido_EUR        decimal(19,6) NOT NULL,
    Valor_IVA_EUR            decimal(19,6) NOT NULL,
    Frete_Alocado_EUR        decimal(19,6) NOT NULL,
    Data_Criacao_Origem      datetime2(0)  NOT NULL,
    Data_Atualizacao_Origem  datetime2(0)  NOT NULL,
    ID_Lote_ETL              int           NOT NULL,
    CONSTRAINT PK_Fact_Vendas PRIMARY KEY CLUSTERED (SK_Venda),
    CONSTRAINT UQ_Fact_Vendas_Linha UNIQUE (BK_Linha_Fatura),
    CONSTRAINT FK_Fact_Data_Fatura     FOREIGN KEY (SK_Data_Fatura)     REFERENCES dbo.Dim_Data (SK_Data),
    CONSTRAINT FK_Fact_Data_Pagamento  FOREIGN KEY (SK_Data_Pagamento)  REFERENCES dbo.Dim_Data (SK_Data),
    CONSTRAINT FK_Fact_Cliente         FOREIGN KEY (SK_Cliente)         REFERENCES dbo.Dim_Cliente (SK_Cliente),
    CONSTRAINT FK_Fact_Produto         FOREIGN KEY (SK_Produto)         REFERENCES dbo.Dim_Produto (SK_Produto),
    CONSTRAINT FK_Fact_Fornecedor      FOREIGN KEY (SK_Fornecedor)      REFERENCES dbo.Dim_Fornecedor (SK_Fornecedor),
    CONSTRAINT FK_Fact_Funcionario     FOREIGN KEY (SK_Funcionario)     REFERENCES dbo.Dim_Funcionario (SK_Funcionario),
    CONSTRAINT FK_Fact_Moeda           FOREIGN KEY (SK_Moeda)           REFERENCES dbo.Dim_Moeda (SK_Moeda)
);
GO

-- Indices nas chaves estrangeiras (consultas por dimensao)
CREATE NONCLUSTERED INDEX IX_Fact_Data_Fatura ON dbo.Fact_Vendas (SK_Data_Fatura);
CREATE NONCLUSTERED INDEX IX_Fact_Cliente     ON dbo.Fact_Vendas (SK_Cliente);
CREATE NONCLUSTERED INDEX IX_Fact_Produto     ON dbo.Fact_Vendas (SK_Produto);
CREATE NONCLUSTERED INDEX IX_Fact_Fornecedor  ON dbo.Fact_Vendas (SK_Fornecedor);
CREATE NONCLUSTERED INDEX IX_Fact_Funcionario ON dbo.Fact_Vendas (SK_Funcionario);
CREATE NONCLUSTERED INDEX IX_Fact_Numero_Fatura ON dbo.Fact_Vendas (Numero_Fatura);
-- Pesquisa da versao vigente na carga (SCD2)
CREATE NONCLUSTERED INDEX IX_Dim_Cliente_Atual     ON dbo.Dim_Cliente     (BK_Cliente)     INCLUDE (Data_Inicio, Data_Fim) WHERE Versao_Atual = 1;
CREATE NONCLUSTERED INDEX IX_Dim_Produto_Atual     ON dbo.Dim_Produto     (BK_Produto)     INCLUDE (Data_Inicio, Data_Fim) WHERE Versao_Atual = 1;
CREATE NONCLUSTERED INDEX IX_Dim_Fornecedor_Atual  ON dbo.Dim_Fornecedor  (BK_Fornecedor)  INCLUDE (Data_Inicio, Data_Fim) WHERE Versao_Atual = 1;
CREATE NONCLUSTERED INDEX IX_Dim_Funcionario_Atual ON dbo.Dim_Funcionario (BK_Funcionario) INCLUDE (Data_Inicio, Data_Fim) WHERE Versao_Atual = 1;
GO

/*------------------- MEMBROS "DESCONHECIDO" (SK = -1) ----------------------*/
INSERT INTO dbo.Dim_Data (SK_Data, Data, Dia_Mes, Dia_Ano, Dia_Semana, Nome_Dia_Semana, Fim_Semana, Ultimo_Dia_Mes,
                          Semana_Ano, Ano_Semana_ISO, Mes, Nome_Mes, Ano_Mes, Trimestre, Quadrimestre, Semestre,
                          Estacao_Ano, Ano, Feriado_Nacional, Nome_Feriado)
VALUES (-1, '1900-01-01', 1, 1, 1, 'Sem data', 0, 0, 1, 1900, 1, 'Sem data', 190001, 1, 1, 1, 'Sem data', 1900, 0, NULL);

SET IDENTITY_INSERT dbo.Dim_Cliente ON;
INSERT INTO dbo.Dim_Cliente (SK_Cliente, BK_Cliente, Nome, NIF, Cidade, Zona, Pais, Tipo_Cliente, Segmento,
                             Data_Inicio, Data_Fim, Versao_Atual, Data_Criacao_Origem, Data_Atualizacao_Origem)
VALUES (-1, -1, N'Desconhecido', 'N/D', N'Desconhecida', N'Desconhecida', N'Desconhecido', N'Desconhecido', N'Desconhecido',
        '1900-01-01', '9999-12-31', 1, '1900-01-01', '1900-01-01');
SET IDENTITY_INSERT dbo.Dim_Cliente OFF;

SET IDENTITY_INSERT dbo.Dim_Produto ON;
INSERT INTO dbo.Dim_Produto (SK_Produto, BK_Produto, Designacao, BK_Familia, Familia, BK_Categoria, Categoria,
                             Data_Inicio, Data_Fim, Versao_Atual, Data_Criacao_Origem, Data_Atualizacao_Origem)
VALUES (-1, 'N/D', N'Desconhecido', 'N/D', N'Desconhecida', -1, N'Desconhecida',
        '1900-01-01', '9999-12-31', 1, '1900-01-01', '1900-01-01');
SET IDENTITY_INSERT dbo.Dim_Produto OFF;

SET IDENTITY_INSERT dbo.Dim_Fornecedor ON;
INSERT INTO dbo.Dim_Fornecedor (SK_Fornecedor, BK_Fornecedor, Nome, NIF, Tipo_Fornecedor, Cidade, Zona,
                                Data_Inicio, Data_Fim, Versao_Atual, Data_Criacao_Origem, Data_Atualizacao_Origem)
-- SK -1 = produtos sem fornecedor na origem (products.supplyer NULL)
VALUES (-1, -1, N'Sem fornecedor', 'N/D', N'Desconhecido', N'Desconhecida', N'Zona desconhecida',
        '1900-01-01', '9999-12-31', 1, '1900-01-01', '1900-01-01');
SET IDENTITY_INSERT dbo.Dim_Fornecedor OFF;

SET IDENTITY_INSERT dbo.Dim_Funcionario ON;
INSERT INTO dbo.Dim_Funcionario (SK_Funcionario, BK_Funcionario, Codigo, Nome, Email, Grupo, Departamento,
                                 Data_Inicio, Data_Fim, Versao_Atual, Data_Criacao_Origem, Data_Atualizacao_Origem)
VALUES (-1, -1, 'N/D', N'Desconhecido', 'N/D', N'Desconhecido', N'Desconhecido',
        '1900-01-01', '9999-12-31', 1, '1900-01-01', '1900-01-01');
SET IDENTITY_INSERT dbo.Dim_Funcionario OFF;
GO

/*-------------------------- DADOS DE APOIO: MOEDAS -------------------------*/
INSERT INTO dbo.Dim_Moeda (Codigo_ISO, Nome, Simbolo) VALUES
    ('EUR', N'Euro',             N'€'),
    ('GBP', N'Libra esterlina',  N'£');   -- sucursal futura no Reino Unido
GO
