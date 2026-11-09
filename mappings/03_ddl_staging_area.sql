/*
  Staging Area - More Rhythm
  SQL Server

  Estruturas de apoio (este ficheiro):
    stg_load_control                controlo das execucoes de carga
    stg_rejections                  registos rejeitados, com os valores originais em JSON
    stg_customer_duplicate_groups   clientes duplicados e respetivo sobrevivente

  As 12 tabelas stg_<origem> (uma por tabela da origem) estao em
  05_ddl_staging_tabelas_tipadas.sql. Guardam todos os registos extraidos com os nomes e
  tipos da origem, mais o estado de validacao; os valores nao sao convertidos nem
  corrigidos nessas tabelas. O JSON so e usado para os registos rejeitados, de modo a nao
  guardar duas vezes os registos validos.

  Ordem de execucao: 03, 05 e, para testar, 06_testes_staging.sql.
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

/*
  Clientes duplicados (regra R01). Uma linha por cliente de origem que pertence a um
  grupo: o sobrevivente (survivor_customer_number = source_customer_number) e os clientes
  absorvidos. A decisao e persistente: so se desfaz por revisao explicita
  (review_status = 'DISMISSED'). O duplicate_group_id e atribuido pelo processo (menor
  numero de cliente do grupo no momento da criacao) e nao e gerado automaticamente.
  Um cliente com linha nesta tabela nao e reavaliado em cargas seguintes.
*/
CREATE TABLE dbo.stg_customer_duplicate_groups (
    source_customer_number     numeric(10,0) NOT NULL,   -- customers.number
    duplicate_group_id         int NOT NULL,
    survivor_customer_number   numeric(10,0) NOT NULL,   -- cliente que passa a representar o grupo
    name_similarity            decimal(3,2) NULL,        -- semelhanca do nome com o sobrevivente (0 a 1)
    corroborating_attributes   tinyint NULL,             -- atributos corroborantes (0 a 6)
    review_status              varchar(20) NOT NULL CONSTRAINT DF_stg_dup_status DEFAULT ('ACTIVE'),
    decided_load_id            bigint NOT NULL,          -- carga em que a decisao foi tomada
    decided_at                 datetime2(3) NOT NULL CONSTRAINT DF_stg_dup_decided DEFAULT (SYSUTCDATETIME()),
    reviewed_at                datetime2(3) NULL,        -- revisao que desfez a decisao
    review_note                nvarchar(1000) NULL,      -- valores validos e diferentes entre os membros
    CONSTRAINT PK_stg_duplicate_groups PRIMARY KEY (source_customer_number),
    CONSTRAINT FK_stg_dup_survivor FOREIGN KEY (survivor_customer_number)
        REFERENCES dbo.stg_customer_duplicate_groups (source_customer_number),
    CONSTRAINT FK_stg_dup_load FOREIGN KEY (decided_load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_dup_status CHECK (review_status IN ('ACTIVE', 'DISMISSED')),
    CONSTRAINT CK_stg_dup_similarity CHECK (name_similarity BETWEEN 0 AND 1),
    CONSTRAINT CK_stg_dup_corrob CHECK (corroborating_attributes BETWEEN 0 AND 6),
    CONSTRAINT CK_stg_dup_member CHECK (
        survivor_customer_number = source_customer_number
        OR (name_similarity IS NOT NULL AND corroborating_attributes IS NOT NULL)),
    CONSTRAINT CK_stg_dup_dismissed CHECK (review_status = 'ACTIVE' OR reviewed_at IS NOT NULL)
);
GO

CREATE INDEX IX_stg_dup_group ON dbo.stg_customer_duplicate_groups (duplicate_group_id);
GO
CREATE INDEX IX_stg_dup_survivor ON dbo.stg_customer_duplicate_groups (survivor_customer_number);
GO
