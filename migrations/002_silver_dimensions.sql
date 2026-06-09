-- ============================================================
-- FILE    : 002_silver_dimensions.sql
-- LAYER   : Silver (Cleansed & Conformed)
-- ENGINE  : Azure Synapse Analytics – Dedicated SQL Pool
-- PURPOSE : Dimension table DDLs for the Silver layer.
--           These tables receive cleansed, deduplicated data
--           from Bronze via ADF / Synapse pipelines.
-- NOTES   :
--   • All tables use CLUSTERED COLUMNSTORE INDEX (CCI).
--   • Small / low-cardinality dims use DISTRIBUTION = REPLICATE.
--   • Large dims (account, customer) use DISTRIBUTION = HASH.
--   • SCD Type 2 dims include effective_from, effective_to,
--     is_current and a natural key alongside the surrogate key.
--   • Surrogate keys are INT IDENTITY(1,1) – never exposed to
--     upstream consumers (use natural key for joins from Bronze).
--   • Run this script in the Dedicated Pool database context.
-- ============================================================

-- ------------------------------------------------------------
-- Section 0 : Schema
-- ------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO

-- ============================================================
-- Section 1 : slv_dim_date
--   • Static calendar dimension, pre-populated by pipeline.
--   • No SCD – dates never change.
--   • REPLICATE: small table (~50 000 rows for 100-year span).
-- ============================================================
IF OBJECT_ID('silver.slv_dim_date', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_date;
GO

CREATE TABLE silver.slv_dim_date
(
    -- Surrogate key
    date_sk                 INT             NOT NULL,   -- YYYYMMDD integer key

    -- Natural key
    full_date               DATE            NOT NULL,

    -- Calendar attributes
    calendar_year           SMALLINT        NOT NULL,
    calendar_quarter        TINYINT         NOT NULL,   -- 1–4
    calendar_month_num      TINYINT         NOT NULL,   -- 1–12
    calendar_month_name     NVARCHAR(10)    NOT NULL,
    calendar_month_abbr     CHAR(3)         NOT NULL,
    calendar_week_num       TINYINT         NOT NULL,   -- ISO week 1–53
    day_of_year             SMALLINT        NOT NULL,   -- 1–366
    day_of_month            TINYINT         NOT NULL,   -- 1–31
    day_of_week_num         TINYINT         NOT NULL,   -- 1 = Sunday, 7 = Saturday
    day_of_week_name        NVARCHAR(10)    NOT NULL,
    day_of_week_abbr        CHAR(3)         NOT NULL,

    -- Business calendar flags
    is_weekday              BIT             NOT NULL    DEFAULT 1,
    is_weekend              BIT             NOT NULL    DEFAULT 0,
    is_public_holiday       BIT             NOT NULL    DEFAULT 0,
    public_holiday_name     NVARCHAR(100)   NULL,
    is_last_day_of_month    BIT             NOT NULL    DEFAULT 0,
    is_last_day_of_quarter  BIT             NOT NULL    DEFAULT 0,
    is_last_day_of_year     BIT             NOT NULL    DEFAULT 0,

    -- Fiscal calendar (adjust offsets for your fiscal year)
    fiscal_year             SMALLINT        NOT NULL,
    fiscal_quarter          TINYINT         NOT NULL,
    fiscal_month_num        TINYINT         NOT NULL,
    fiscal_period_name      NVARCHAR(20)    NULL,

    -- Relative helpers
    days_from_today         INT             NULL,       -- populated by refresh proc
    is_current_month        BIT             NOT NULL    DEFAULT 0,
    is_current_year         BIT             NOT NULL    DEFAULT 0,

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- ------------------------------------------------------------
-- Index hint for point-lookup performance on date_sk
-- ------------------------------------------------------------
CREATE NONCLUSTERED INDEX nix_slv_dim_date_sk
    ON silver.slv_dim_date (date_sk)
    WITH (DATA_COMPRESSION = PAGE);
GO

-- ============================================================
-- Section 2 : slv_dim_account  (SCD Type 2)
--   • Large table – HASH distribution on natural key hash.
-- ============================================================
IF OBJECT_ID('silver.slv_dim_account', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_account;
GO

CREATE TABLE silver.slv_dim_account
(
    -- Surrogate key
    account_sk              BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural / business key
    account_id              NVARCHAR(32)    NOT NULL,

    -- Account attributes
    account_type            NVARCHAR(50)    NOT NULL,   -- SAVINGS, CURRENT, LOAN, …
    account_sub_type        NVARCHAR(50)    NULL,
    product_code            NVARCHAR(30)    NULL,
    currency_code           CHAR(3)         NOT NULL,
    branch_code             NVARCHAR(20)    NULL,
    branch_name             NVARCHAR(100)   NULL,
    region                  NVARCHAR(50)    NULL,
    country_code            CHAR(2)         NULL,
    account_status          NVARCHAR(20)    NOT NULL,   -- ACTIVE, DORMANT, CLOSED
    account_segment         NVARCHAR(30)    NULL,       -- RETAIL, SME, CORPORATE
    risk_rating             NVARCHAR(10)    NULL,       -- A, B, C, D
    credit_limit            DECIMAL(20, 4)  NULL,
    opened_date             DATE            NULL,
    closed_date             DATE            NULL,

    -- Ownership link (FK to customer dim – degenerate here)
    primary_customer_id     NVARCHAR(32)    NULL,

    -- SCD2 columns
    effective_from          DATE            NOT NULL,
    effective_to            DATE            NOT NULL    DEFAULT '9999-12-31',
    is_current              BIT             NOT NULL    DEFAULT 1,
    scd_hash                BINARY(32)      NULL,       -- SHA2_256 of tracked cols

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    source_system           NVARCHAR(50)    NULL,
    batch_id                NVARCHAR(64)    NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(account_id)
);
GO

-- ============================================================
-- Section 3 : slv_dim_customer  (SCD Type 2)
-- ============================================================
IF OBJECT_ID('silver.slv_dim_customer', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_customer;
GO

CREATE TABLE silver.slv_dim_customer
(
    -- Surrogate key
    customer_sk             BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    customer_id             NVARCHAR(32)    NOT NULL,

    -- Demographics
    customer_type           NVARCHAR(20)    NOT NULL,   -- INDIVIDUAL, CORPORATE
    first_name              NVARCHAR(100)   NULL,
    last_name               NVARCHAR(100)   NULL,
    full_name               NVARCHAR(200)   NULL,
    date_of_birth           DATE            NULL,
    gender                  NVARCHAR(10)    NULL,
    nationality             CHAR(2)         NULL,
    tax_id_masked           NVARCHAR(20)    NULL,       -- masked for PII

    -- Contact (tokenised / masked at source)
    email_domain            NVARCHAR(100)   NULL,       -- domain only, no local-part
    mobile_country_code     NVARCHAR(5)     NULL,
    preferred_channel       NVARCHAR(30)    NULL,
    preferred_language      CHAR(5)         NULL,

    -- KYC / CDD
    kyc_status              NVARCHAR(20)    NULL,       -- VERIFIED, PENDING, FAILED
    kyc_verified_date       DATE            NULL,
    aml_risk_rating         NVARCHAR(10)    NULL,
    pep_flag                BIT             NULL,
    sanctions_flag          BIT             NULL,

    -- Segmentation
    customer_segment        NVARCHAR(30)    NULL,       -- MASS, PREMIUM, PRIVATE
    customer_tenure_years   DECIMAL(5,2)    NULL,
    onboarding_channel      NVARCHAR(30)    NULL,
    onboarding_date         DATE            NULL,

    -- SCD2 columns
    effective_from          DATE            NOT NULL,
    effective_to            DATE            NOT NULL    DEFAULT '9999-12-31',
    is_current              BIT             NOT NULL    DEFAULT 1,
    scd_hash                BINARY(32)      NULL,

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    source_system           NVARCHAR(50)    NULL,
    batch_id                NVARCHAR(64)    NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(customer_id)
);
GO

-- ============================================================
-- Section 4 : slv_dim_channel  (Type 1 – no SCD)
-- ============================================================
IF OBJECT_ID('silver.slv_dim_channel', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_channel;
GO

CREATE TABLE silver.slv_dim_channel
(
    channel_sk              INT             NOT NULL    IDENTITY(1,1),
    channel_code            NVARCHAR(30)    NOT NULL,   -- WEB, MOBILE, ATM, BRANCH
    channel_name            NVARCHAR(100)   NOT NULL,
    channel_category        NVARCHAR(50)    NULL,       -- DIGITAL, PHYSICAL, …
    channel_description     NVARCHAR(500)   NULL,
    is_digital              BIT             NOT NULL    DEFAULT 1,
    is_active               BIT             NOT NULL    DEFAULT 1,
    sort_order              TINYINT         NULL,
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- ============================================================
-- Section 5 : slv_dim_transaction_type
-- ============================================================
IF OBJECT_ID('silver.slv_dim_transaction_type', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_transaction_type;
GO

CREATE TABLE silver.slv_dim_transaction_type
(
    transaction_type_sk     INT             NOT NULL    IDENTITY(1,1),
    transaction_type_code   NVARCHAR(50)    NOT NULL,
    transaction_type_name   NVARCHAR(100)   NOT NULL,
    transaction_category    NVARCHAR(50)    NULL,   -- DEBIT, CREDIT, FEE, REVERSAL
    parent_type_code        NVARCHAR(50)    NULL,   -- hierarchical grouping
    is_reversible           BIT             NOT NULL    DEFAULT 1,
    requires_authorisation  BIT             NOT NULL    DEFAULT 0,
    reporting_group         NVARCHAR(50)    NULL,
    regulatory_category     NVARCHAR(50)    NULL,
    is_active               BIT             NOT NULL    DEFAULT 1,
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- ============================================================
-- Section 6 : slv_dim_service
--   Represents internal microservices / application services.
-- ============================================================
IF OBJECT_ID('silver.slv_dim_service', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_service;
GO

CREATE TABLE silver.slv_dim_service
(
    service_sk              INT             NOT NULL    IDENTITY(1,1),
    service_name            NVARCHAR(100)   NOT NULL,
    service_code            NVARCHAR(50)    NULL,
    service_version         NVARCHAR(20)    NULL,
    service_owner_team      NVARCHAR(100)   NULL,
    service_domain          NVARCHAR(50)    NULL,   -- PAYMENTS, AUTH, FRAUD, …
    environment             NVARCHAR(20)    NULL,   -- PROD, UAT, DEV
    hosting_platform        NVARCHAR(30)    NULL,   -- AKS, AZURE_FUNCTIONS, VM
    region                  NVARCHAR(30)    NULL,
    sla_tier                NVARCHAR(10)    NULL,   -- P0, P1, P2
    is_active               BIT             NOT NULL    DEFAULT 1,
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- ============================================================
-- Section 7 : slv_dim_error_type
-- ============================================================
IF OBJECT_ID('silver.slv_dim_error_type', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_error_type;
GO

CREATE TABLE silver.slv_dim_error_type
(
    error_type_sk           INT             NOT NULL    IDENTITY(1,1),
    error_type_code         NVARCHAR(50)    NOT NULL,
    error_type_name         NVARCHAR(100)   NOT NULL,
    error_category          NVARCHAR(50)    NULL,   -- SYSTEM, BUSINESS, NETWORK, …
    severity_default        NVARCHAR(10)    NULL,   -- INFO, WARN, ERROR, CRITICAL
    is_retriable            BIT             NOT NULL    DEFAULT 0,
    expected_in_prod        BIT             NOT NULL    DEFAULT 0,
    resolution_playbook_url NVARCHAR(500)   NULL,
    owning_team             NVARCHAR(100)   NULL,
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- ============================================================
-- Section 8 : slv_dim_auth_event_type
-- ============================================================
IF OBJECT_ID('silver.slv_dim_auth_event_type', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_auth_event_type;
GO

CREATE TABLE silver.slv_dim_auth_event_type
(
    auth_event_type_sk      INT             NOT NULL    IDENTITY(1,1),
    event_type_code         NVARCHAR(50)    NOT NULL,
    event_type_name         NVARCHAR(100)   NOT NULL,
    event_category          NVARCHAR(50)    NULL,   -- AUTHENTICATION, AUTHORISATION
    auth_method_group       NVARCHAR(50)    NULL,   -- PASSWORD, BIOMETRIC, OTP, TOKEN
    mfa_required            BIT             NOT NULL    DEFAULT 0,
    risk_indicator_flag     BIT             NOT NULL    DEFAULT 0,
    regulatory_relevant     BIT             NOT NULL    DEFAULT 0,
    is_active               BIT             NOT NULL    DEFAULT 1,
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- ============================================================
-- End of 002_silver_dimensions.sql
-- ============================================================
