/*
  Staging Area - More Rhythm
  Tabelas tipadas stg_<origem> (12 tabelas) e tabelas de rejeicao dqp_<origem> (6 tabelas)

  Pre-requisito: 03_ddl_staging_area.sql (stg_load_control e restantes tabelas de apoio).
  Cada tabela guarda as colunas de negocio da origem com o mesmo nome, tipo, precisao e
  nulabilidade (lidos de INFORMATION_SCHEMA em MoreRhythm), mais as colunas tecnicas do
  contrato descrito em source-to-staging.md (seccao 9) e as colunas auxiliares usadas
  pelas regras de validacao e pelo mapeamento Staging -> Data Mart.

  Uma linha por registo e por lote de carga: a mesma chave de negocio pode aparecer em
  varios lotes, mas nunca duas vezes no mesmo (UQ_<tabela>_load).
  source_pk: colunas da chave primaria da origem, por ordem alfabetica, no formato
  coluna=valor e separadas por |.
  employees tem a coluna reservada [group], escrita entre parenteses retos.
*/
IF DB_ID(N'MoreRhythm_STG') IS NULL
    CREATE DATABASE MoreRhythm_STG;
GO
USE MoreRhythm_STG;
GO

/*---------------------------- stg_zones : Zonas geograficas ----------------------------*/
CREATE TABLE dbo.stg_zones (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_zones_src DEFAULT (N'zones'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_zones_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    code                  numeric(5,0) NOT NULL,
    zone                  varchar(50) NULL,
    CONSTRAINT PK_stg_zones PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_zones_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_zones_src CHECK (source_table = N'zones'),
    CONSTRAINT CK_stg_zones_pk CHECK (source_pk LIKE N'code=%'),
    CONSTRAINT CK_stg_zones_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_zones_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_zones_bk ON dbo.stg_zones (code, extraction_timestamp);
GO

/*---------------------------- stg_categories : Categorias de produtos ----------------------------*/
CREATE TABLE dbo.stg_categories (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_categories_src DEFAULT (N'categories'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_categories_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    Code                  int NOT NULL,
    Category              varchar(35) NULL,
    CONSTRAINT PK_stg_categories PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_categories_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_categories_src CHECK (source_table = N'categories'),
    CONSTRAINT CK_stg_categories_pk CHECK (source_pk LIKE N'Code=%'),
    CONSTRAINT CK_stg_categories_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_categories_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_categories_bk ON dbo.stg_categories (Code, extraction_timestamp);
GO

/*---------------------------- stg_families : Familias de produtos ----------------------------*/
CREATE TABLE dbo.stg_families (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_families_src DEFAULT (N'families'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_families_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    reference             varchar(18) NOT NULL,
    name                  varchar(60) NOT NULL,
    classification        varchar(20) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_stg_families PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_families_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_families_src CHECK (source_table = N'families'),
    CONSTRAINT CK_stg_families_pk CHECK (source_pk LIKE N'reference=%'),
    CONSTRAINT CK_stg_families_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_families_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_families_bk ON dbo.stg_families (reference, extraction_timestamp);
GO

/*---------------------------- stg_suplliers : Fornecedores (grafia da origem) ----------------------------*/
CREATE TABLE dbo.stg_suplliers (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_suplliers_src DEFAULT (N'suplliers'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_suplliers_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    number                numeric(10,0) NOT NULL,
    name                  varchar(55) NOT NULL,
    phone                 varchar(60) NOT NULL,
    contact               varchar(30) NOT NULL,
    address               varchar(55) NOT NULL,
    city                  varchar(43) NOT NULL,
    zip_code              varchar(45) NOT NULL,
    taxpayer_number       varchar(20) NOT NULL,
    zone                  numeric(5,0) NULL,
    type                  varchar(20) NOT NULL,
    days_pay_invoices     numeric(3,0) NOT NULL,
    contact_position      varchar(15) NOT NULL,
    email                 varchar(45) NOT NULL,
    nationality           varchar(20) NOT NULL,
    mobile                varchar(45) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_stg_suplliers PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_suplliers_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_suplliers_src CHECK (source_table = N'suplliers'),
    CONSTRAINT CK_stg_suplliers_pk CHECK (source_pk LIKE N'number=%'),
    CONSTRAINT CK_stg_suplliers_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_suplliers_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_suplliers_bk ON dbo.stg_suplliers (number, extraction_timestamp);
GO

/*---------------------------- stg_employees : Funcionarios ----------------------------*/
CREATE TABLE dbo.stg_employees (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_employees_src DEFAULT (N'employees'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_employees_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    number                numeric(6,0) NOT NULL,
    code                  varchar(20) NOT NULL,
    name                  varchar(30) NOT NULL,
    [group]               varchar(20) NOT NULL,
    departament           varchar(20) NOT NULL,
    email                 varchar(100) NOT NULL,
    chief                 numeric(6,0) NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_stg_employees PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_employees_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_employees_src CHECK (source_table = N'employees'),
    CONSTRAINT CK_stg_employees_pk CHECK (source_pk LIKE N'number=%'),
    CONSTRAINT CK_stg_employees_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_employees_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_employees_bk ON dbo.stg_employees (number, extraction_timestamp);
GO

/*---------------------------- stg_customers : Clientes ----------------------------*/
CREATE TABLE dbo.stg_customers (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_customers_src DEFAULT (N'customers'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_customers_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    number                numeric(10,0) NOT NULL,
    name                  varchar(55) NOT NULL,
    taxpayer_number       varchar(20) NOT NULL,
    phone                 varchar(60) NOT NULL,
    mobile                varchar(45) NOT NULL,
    contact               varchar(30) NOT NULL,
    email                 varchar(45) NOT NULL,
    address               varchar(55) NOT NULL,
    clity                 varchar(43) NOT NULL,
    zip_code              varchar(45) NOT NULL,
    zone                  numeric(5,0) NULL,
    type                  varchar(20) NOT NULL,
    seller                numeric(4,0) NOT NULL,
    days_pay_invoices     numeric(3,0) NOT NULL,
    BBAN                  varchar(28) NOT NULL,
    segment               varchar(25) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    -- colunas auxiliares da Staging
    normalised_name       varchar(55) NULL,   -- nome normalizado, so para comparacao (R01/R09)
    normalised_taxpayer   varchar(20) NULL,   -- NIF sem separadores, so para comparacao (R01)
    normalised_email      varchar(45) NULL,   -- email normalizado, so para comparacao (R09)
    normalised_address    varchar(55) NULL,   -- morada normalizada, so para comparacao (R09)
    CONSTRAINT PK_stg_customers PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_customers_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_customers_src CHECK (source_table = N'customers'),
    CONSTRAINT CK_stg_customers_pk CHECK (source_pk LIKE N'number=%'),
    CONSTRAINT CK_stg_customers_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_customers_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_customers_bk ON dbo.stg_customers (number, extraction_timestamp);
GO

/*---------------------------- stg_products : Produtos ----------------------------*/
CREATE TABLE dbo.stg_products (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_products_src DEFAULT (N'products'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_products_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    reference             char(18) NOT NULL,
    designation           char(60) NULL,
    family                varchar(18) NULL,
    stock                 numeric(13,3) NULL,
    current_sell_price    numeric(19,6) NULL,
    supplyer              numeric(10,0) NULL,
    minimum_stock         numeric(13,3) NULL,
    category              int NULL,
    classification        varchar(20) NULL,
    last_cost_price       numeric(19,6) NULL,
    vat_rate              numeric(2,0) NULL,
    create_date           date NULL,
    create_time           time NULL,
    last_update_date      date NULL,
    last_update_time      time NULL,
    -- colunas auxiliares da Staging
    classification_fallback bit NOT NULL CONSTRAINT DF_stg_products_fallback DEFAULT (0),   -- 1 se a classificacao vier do fallback da familia
    CONSTRAINT PK_stg_products PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_products_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_products_src CHECK (source_table = N'products'),
    CONSTRAINT CK_stg_products_pk CHECK (source_pk LIKE N'reference=%'),
    CONSTRAINT CK_stg_products_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_products_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_products_bk ON dbo.stg_products (reference, extraction_timestamp);
GO

/*---------------------------- stg_invoices : Cabecalhos de faturas ----------------------------*/
CREATE TABLE dbo.stg_invoices (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_invoices_src DEFAULT (N'invoices'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_invoices_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    invoice_stamp_id      char(25) NOT NULL,
    invoice_date          date NOT NULL,
    customer              numeric(10,0) NOT NULL,
    employee              numeric(6,0) NOT NULL,
    payment_date          date NOT NULL,
    currency              varchar(11) NOT NULL,
    products_total        numeric(19,6) NOT NULL,
    shipping_cost         numeric(19,6) NOT NULL,
    total_for_vat         numeric(19,6) NOT NULL,
    vat_value             numeric(19,6) NOT NULL,
    final_total           numeric(19,6) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    -- colunas auxiliares da Staging
    line_sum              numeric(19,6) NULL,   -- soma de line_total das linhas da fatura (R07)
    header_line_difference numeric(19,6) NULL,   -- products_total menos line_sum (R07)
    CONSTRAINT PK_stg_invoices PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_invoices_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_invoices_src CHECK (source_table = N'invoices'),
    CONSTRAINT CK_stg_invoices_pk CHECK (source_pk LIKE N'invoice[_]stamp[_]id=%'),
    CONSTRAINT CK_stg_invoices_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_invoices_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_invoices_bk ON dbo.stg_invoices (invoice_stamp_id, extraction_timestamp);
GO

/*---------------------------- stg_invoices_lines : Linhas de faturas ----------------------------*/
CREATE TABLE dbo.stg_invoices_lines (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_invoices_lines_src DEFAULT (N'invoices_lines'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_invoices_lines_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    invoice_line_stamp_id char(25) NOT NULL,
    invoice_stamp_id      char(25) NOT NULL,
    product               char(18) NOT NULL,
    quantity              numeric(14,4) NOT NULL,
    unit_price            numeric(19,6) NOT NULL,
    line_total            numeric(19,6) NOT NULL,
    line_vat              numeric(19,6) NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    -- colunas auxiliares da Staging
    frete_alocado         numeric(19,6) NULL,   -- frete da fatura alocado a esta linha
    CONSTRAINT PK_stg_invoices_lines PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_invoices_lines_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_invoices_lines_src CHECK (source_table = N'invoices_lines'),
    CONSTRAINT CK_stg_invoices_lines_pk CHECK (source_pk LIKE N'invoice[_]line[_]stamp[_]id=%'),
    CONSTRAINT CK_stg_invoices_lines_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_invoices_lines_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_invoices_lines_bk ON dbo.stg_invoices_lines (invoice_line_stamp_id, extraction_timestamp);
CREATE INDEX IX_stg_invoices_lines_invoice ON dbo.stg_invoices_lines (invoice_stamp_id);
GO

/*---------------------------- stg_purchases : Cabecalhos de compras ----------------------------*/
CREATE TABLE dbo.stg_purchases (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_purchases_src DEFAULT (N'purchases'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_purchases_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    purchase_stamp        char(25) NOT NULL,
    document_name         varchar(20) NOT NULL,
    document_number       varchar(20) NOT NULL,
    document_date         date NOT NULL,
    supplier              numeric(10,0) NOT NULL,
    employee              numeric(6,0) NOT NULL,
    payment_date          date NOT NULL,
    zone                  numeric(5,0) NOT NULL,
    products_total        numeric(19,6) NOT NULL,
    vat_value             numeric(19,6) NOT NULL,
    final_total           numeric(19,6) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_stg_purchases PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_purchases_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_purchases_src CHECK (source_table = N'purchases'),
    CONSTRAINT CK_stg_purchases_pk CHECK (source_pk LIKE N'purchase[_]stamp=%'),
    CONSTRAINT CK_stg_purchases_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_purchases_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_purchases_bk ON dbo.stg_purchases (purchase_stamp, extraction_timestamp);
GO

/*---------------------------- stg_purchases_lines : Linhas de compras ----------------------------*/
CREATE TABLE dbo.stg_purchases_lines (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_purchases_lines_src DEFAULT (N'purchases_lines'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_purchases_lines_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    purchase_line_stamp   char(25) NOT NULL,
    purchase_stamp        char(25) NOT NULL,
    document_name         varchar(20) NOT NULL,
    document_number       varchar(20) NOT NULL,
    document_date         date NOT NULL,
    product               char(18) NULL,
    quantity              numeric(14,4) NOT NULL,
    unit_price            numeric(19,6) NOT NULL,
    line_total            numeric(19,6) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NULL,
    CONSTRAINT PK_stg_purchases_lines PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_purchases_lines_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_purchases_lines_src CHECK (source_table = N'purchases_lines'),
    CONSTRAINT CK_stg_purchases_lines_pk CHECK (source_pk LIKE N'purchase[_]line[_]stamp=%'),
    CONSTRAINT CK_stg_purchases_lines_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_purchases_lines_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_purchases_lines_bk ON dbo.stg_purchases_lines (purchase_line_stamp, extraction_timestamp);
CREATE INDEX IX_stg_purchases_lines_purchase ON dbo.stg_purchases_lines (purchase_stamp);
GO

/*---------------------------- stg_stocks_movements : Movimentos de stock ----------------------------*/
CREATE TABLE dbo.stg_stocks_movements (
    stg_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    source_table          sysname NOT NULL CONSTRAINT DF_stg_stocks_movements_src DEFAULT (N'stocks_movements'),
    source_pk             nvarchar(250) NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL,
    validation_status     varchar(20) NOT NULL CONSTRAINT DF_stg_stocks_movements_status DEFAULT ('PENDING'),
    validation_rule       varchar(10) NULL,
    validation_message    nvarchar(1000) NULL,
    raw_row_hash          varbinary(32) NOT NULL,
    -- colunas de negocio (origem)
    stock_movement_stamp  char(25) NOT NULL,
    document_name         varchar(20) NOT NULL,
    document_number       varchar(20) NOT NULL,
    movement_date         date NOT NULL,
    product               char(18) NOT NULL,
    quantity              decimal(12,3) NOT NULL,
    unit_price            numeric(19,6) NOT NULL,
    total_value           numeric(19,6) NOT NULL,
    vat_value             numeric(19,6) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_stg_stocks_movements PRIMARY KEY (stg_row_id),
    CONSTRAINT FK_stg_stocks_movements_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id),
    CONSTRAINT CK_stg_stocks_movements_src CHECK (source_table = N'stocks_movements'),
    CONSTRAINT CK_stg_stocks_movements_pk CHECK (source_pk LIKE N'stock[_]movement[_]stamp=%'),
    CONSTRAINT CK_stg_stocks_movements_status CHECK (validation_status IN ('VALID', 'CORRIGIDO', 'PENDING', 'REJECTED')),
    CONSTRAINT UQ_stg_stocks_movements_load UNIQUE (load_id, source_pk)
);
GO
CREATE INDEX IX_stg_stocks_movements_bk ON dbo.stg_stocks_movements (stock_movement_stamp, extraction_timestamp);
GO

/*==============================================================================
  Tabelas DQP (Data Quality Problems): registos rejeitados, uma por tabela de origem em
  que as regras de limpeza rejeitam registos. Seguem o padrao usado nas aulas praticas
  (CardDQP, TransactionDQP, FactSalesDQP): os atributos do registo de origem mais a
  descricao do problema. Os registos nestas tabelas nao sao carregados no Data Mart; a sua
  correcao esta fora do ambito do trabalho. Um registo pode aparecer varias vezes se
  violar varias regras.
==============================================================================*/

/*---- dqp_customers : Clientes rejeitados (R03: sem zona; nome em falta) ----*/
CREATE TABLE dbo.dqp_customers (
    dqp_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL CONSTRAINT DF_dqp_customers_ts DEFAULT (SYSUTCDATETIME()),
    validation_rule       varchar(10) NOT NULL,
    DQP                   nvarchar(1000) NOT NULL,   -- descricao do problema de qualidade
    -- atributos do registo de origem
    number                numeric(10,0) NOT NULL,
    name                  varchar(55) NOT NULL,
    taxpayer_number       varchar(20) NOT NULL,
    phone                 varchar(60) NOT NULL,
    mobile                varchar(45) NOT NULL,
    contact               varchar(30) NOT NULL,
    email                 varchar(45) NOT NULL,
    address               varchar(55) NOT NULL,
    clity                 varchar(43) NOT NULL,
    zip_code              varchar(45) NOT NULL,
    zone                  numeric(5,0) NULL,
    type                  varchar(20) NOT NULL,
    seller                numeric(4,0) NOT NULL,
    days_pay_invoices     numeric(3,0) NOT NULL,
    BBAN                  varchar(28) NOT NULL,
    segment               varchar(25) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_dqp_customers PRIMARY KEY (dqp_row_id),
    CONSTRAINT FK_dqp_customers_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id)
);
GO

/*---- dqp_invoices : Faturas rejeitadas (R06, R07, R08 ou R11) ----*/
CREATE TABLE dbo.dqp_invoices (
    dqp_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL CONSTRAINT DF_dqp_invoices_ts DEFAULT (SYSUTCDATETIME()),
    validation_rule       varchar(10) NOT NULL,
    DQP                   nvarchar(1000) NOT NULL,   -- descricao do problema de qualidade
    -- atributos do registo de origem
    invoice_stamp_id      char(25) NOT NULL,
    invoice_date          date NOT NULL,
    customer              numeric(10,0) NOT NULL,
    employee              numeric(6,0) NOT NULL,
    payment_date          date NOT NULL,
    currency              varchar(11) NOT NULL,
    products_total        numeric(19,6) NOT NULL,
    shipping_cost         numeric(19,6) NOT NULL,
    total_for_vat         numeric(19,6) NOT NULL,
    vat_value             numeric(19,6) NOT NULL,
    final_total           numeric(19,6) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_dqp_invoices PRIMARY KEY (dqp_row_id),
    CONSTRAINT FK_dqp_invoices_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id)
);
GO

/*---- dqp_invoices_lines : Linhas de fatura de faturas rejeitadas (R06, R07, R08 ou R11) ----*/
CREATE TABLE dbo.dqp_invoices_lines (
    dqp_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL CONSTRAINT DF_dqp_invoices_lines_ts DEFAULT (SYSUTCDATETIME()),
    validation_rule       varchar(10) NOT NULL,
    DQP                   nvarchar(1000) NOT NULL,   -- descricao do problema de qualidade
    -- atributos do registo de origem
    invoice_line_stamp_id char(25) NOT NULL,
    invoice_stamp_id      char(25) NOT NULL,
    product               char(18) NOT NULL,
    quantity              numeric(14,4) NOT NULL,
    unit_price            numeric(19,6) NOT NULL,
    line_total            numeric(19,6) NOT NULL,
    line_vat              numeric(19,6) NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_dqp_invoices_lines PRIMARY KEY (dqp_row_id),
    CONSTRAINT FK_dqp_invoices_lines_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id)
);
GO

/*---- dqp_products : Produtos rejeitados (R04: sem designacao, familia ou categoria) ----*/
CREATE TABLE dbo.dqp_products (
    dqp_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL CONSTRAINT DF_dqp_products_ts DEFAULT (SYSUTCDATETIME()),
    validation_rule       varchar(10) NOT NULL,
    DQP                   nvarchar(1000) NOT NULL,   -- descricao do problema de qualidade
    -- atributos do registo de origem
    reference             char(18) NOT NULL,
    designation           char(60) NULL,
    family                varchar(18) NULL,
    stock                 numeric(13,3) NULL,
    current_sell_price    numeric(19,6) NULL,
    supplyer              numeric(10,0) NULL,
    minimum_stock         numeric(13,3) NULL,
    category              int NULL,
    classification        varchar(20) NULL,
    last_cost_price       numeric(19,6) NULL,
    vat_rate              numeric(2,0) NULL,
    create_date           date NULL,
    create_time           time NULL,
    last_update_date      date NULL,
    last_update_time      time NULL,
    CONSTRAINT PK_dqp_products PRIMARY KEY (dqp_row_id),
    CONSTRAINT FK_dqp_products_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id)
);
GO

/*---- dqp_purchases_lines : Linhas de compra rejeitadas (R05: sem produto) ----*/
CREATE TABLE dbo.dqp_purchases_lines (
    dqp_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL CONSTRAINT DF_dqp_purchases_lines_ts DEFAULT (SYSUTCDATETIME()),
    validation_rule       varchar(10) NOT NULL,
    DQP                   nvarchar(1000) NOT NULL,   -- descricao do problema de qualidade
    -- atributos do registo de origem
    purchase_line_stamp   char(25) NOT NULL,
    purchase_stamp        char(25) NOT NULL,
    document_name         varchar(20) NOT NULL,
    document_number       varchar(20) NOT NULL,
    document_date         date NOT NULL,
    product               char(18) NULL,
    quantity              numeric(14,4) NOT NULL,
    unit_price            numeric(19,6) NOT NULL,
    line_total            numeric(19,6) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NULL,
    CONSTRAINT PK_dqp_purchases_lines PRIMARY KEY (dqp_row_id),
    CONSTRAINT FK_dqp_purchases_lines_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id)
);
GO

/*---- dqp_suplliers : Fornecedores rejeitados (R03: sem zona) ----*/
CREATE TABLE dbo.dqp_suplliers (
    dqp_row_id            bigint IDENTITY(1,1) NOT NULL,
    load_id               bigint NOT NULL,
    extraction_timestamp  datetime2(3) NOT NULL CONSTRAINT DF_dqp_suplliers_ts DEFAULT (SYSUTCDATETIME()),
    validation_rule       varchar(10) NOT NULL,
    DQP                   nvarchar(1000) NOT NULL,   -- descricao do problema de qualidade
    -- atributos do registo de origem
    number                numeric(10,0) NOT NULL,
    name                  varchar(55) NOT NULL,
    phone                 varchar(60) NOT NULL,
    contact               varchar(30) NOT NULL,
    address               varchar(55) NOT NULL,
    city                  varchar(43) NOT NULL,
    zip_code              varchar(45) NOT NULL,
    taxpayer_number       varchar(20) NOT NULL,
    zone                  numeric(5,0) NULL,
    type                  varchar(20) NOT NULL,
    days_pay_invoices     numeric(3,0) NOT NULL,
    contact_position      varchar(15) NOT NULL,
    email                 varchar(45) NOT NULL,
    nationality           varchar(20) NOT NULL,
    mobile                varchar(45) NOT NULL,
    create_date           date NOT NULL,
    create_time           time NOT NULL,
    last_update_date      date NOT NULL,
    last_update_time      time NOT NULL,
    CONSTRAINT PK_dqp_suplliers PRIMARY KEY (dqp_row_id),
    CONSTRAINT FK_dqp_suplliers_load FOREIGN KEY (load_id) REFERENCES dbo.stg_load_control (load_id)
);
GO
