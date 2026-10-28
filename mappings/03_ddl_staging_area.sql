/*
  Staging Area - More Rhythm
  SQL Server

  A camada raw preserva cada registo como foi extraído. As tabelas tipadas
  stg_<origem> são populadas pelo processo de ingestão a partir de raw_row_json,
  mantendo os mesmos nomes e tipos da origem.
*/
IF DB_ID(N'MoreRhythm_STG') IS NULL
    CREATE DATABASE MoreRhythm_STG;
GO
USE MoreRhythm_STG;
GO

CREATE TABLE dbo.stg_load_control (
    load_id                  bigint IDENTITY(1,1) NOT NULL,
    source_system            sysname NOT NULL,
    extraction_started_at    datetime2(3) NOT NULL,
    extraction_finished_at   datetime2(3) NULL,
    status                   varchar(20) NOT NULL,
    rows_extracted           int NOT NULL CONSTRAINT DF_stg_load_extracted DEFAULT (0),
    rows_validated           int NOT NULL CONSTRAINT DF_stg_load_validated DEFAULT (0),
    rows_rejected            int NOT NULL CONSTRAINT DF_stg_load_rejected DEFAULT (0),
    error_message             nvarchar(2000) NULL,
    CONSTRAINT PK_stg_load_control PRIMARY KEY (load_id),
    CONSTRAINT CK_stg_load_status CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED'))
);
GO

CREATE TABLE dbo.stg_raw_rows (
    stg_row_id               bigint IDENTITY(1,1) NOT NULL,
    load_id                  bigint NOT NULL,
    source_table              sysname NOT NULL,
    source_pk                nvarchar(250) NOT NULL,
    extraction_timestamp      datetime2(3) NOT NULL,
    raw_row_json              nvarchar(max) NOT NULL,
    raw_row_hash              varbinary(32) NOT NULL,
    validation_status          varchar(20) NOT NULL CONSTRAINT DF_stg_raw_status DEFAULT ('PENDING'),
    validation_rule            varchar(10) NULL,
    validation_message         nvarchar(1000) NULL,
    CONSTRAINT PK_stg_raw_rows PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_raw_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_raw_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_raw_row_load UNIQUE (load_id, source_table, source_pk)
);
GO

CREATE INDEX IX_stg_raw_business_key
    ON dbo.stg_raw_rows (source_table, source_pk, extraction_timestamp);
GO

CREATE TABLE dbo.stg_rejections (
    rejection_id             bigint IDENTITY(1,1) NOT NULL,
    load_id                  bigint NOT NULL,
    source_table              sysname NOT NULL,
    source_pk                nvarchar(250) NOT NULL,
    raw_row_json              nvarchar(max) NOT NULL,
    validation_rule            varchar(10) NOT NULL,
    validation_message         nvarchar(1000) NOT NULL,
    rejected_at               datetime2(3) NOT NULL CONSTRAINT DF_stg_rej_at DEFAULT (SYSUTCDATETIME()),
    resolution_status          varchar(20) NOT NULL CONSTRAINT DF_stg_rej_resolution DEFAULT ('OPEN'),
    CONSTRAINT PK_stg_rejections PRIMARY KEY (rejection_id),
    CONSTRAINT FK_stg_rej_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_rej_resolution CHECK (resolution_status IN ('OPEN', 'RESOLVED', 'CANCELLED'))
);
GO

CREATE INDEX IX_stg_rejections_lookup
    ON dbo.stg_rejections (source_table, source_pk, resolution_status);
GO

CREATE TABLE dbo.stg_customer_duplicate_groups (
    duplicate_group_id       int IDENTITY(1,1) NOT NULL,
    source_customer_number   numeric(9,0) NOT NULL,
    normalized_taxpayer      varchar(20) NULL,
    normalized_name          nvarchar(255) NULL,
    review_status             varchar(20) NOT NULL CONSTRAINT DF_stg_dup_status DEFAULT ('PENDING_REVIEW'),
    survivor_customer_number numeric(9,0) NULL,
    reviewed_at               datetime2(3) NULL,
    review_note               nvarchar(1000) NULL,
    CONSTRAINT PK_stg_duplicate_groups PRIMARY KEY (duplicate_group_id),
    CONSTRAINT UQ_stg_duplicate_customer UNIQUE (source_customer_number),
    CONSTRAINT CK_stg_dup_status CHECK (review_status IN ('PENDING_REVIEW', 'CONFIRMED', 'DISMISSED'))
);
GO

/*
  As tabelas tipadas stg_categories, stg_customers, stg_employees,
  stg_families, stg_invoices, stg_invoices_lines, stg_products,
  stg_purchases, stg_purchases_lines, stg_stocks_movements,
  stg_suplliers e stg_zones devem ser geradas a partir de
  data-profiling/inventario.md, acrescentando os metadados definidos em
  mappings/source-to-staging.md. A camada raw e as rejeições acima são a
  estrutura física mínima executável e não substituem essas tabelas tipadas.
*/
