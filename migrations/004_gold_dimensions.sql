-- =============================================================================
-- FILE    : 004_gold_dimensions.sql
-- LAYER   : Gold (Conformed & Presentation-Ready)
-- ENGINE  : Azure Synapse Analytics – Dedicated SQL Pool
-- PURPOSE : Conformed dimension DDLs for the Gold layer.
--           Gold dimensions are flattened current-snapshot views of their
--           Silver counterparts – SCD2 history is collapsed to the single
--           is_current = 1 record for each natural key.  These tables are
--           optimised for BI tooling, self-service analytics, and ML
--           feature stores where the latest attribute state is required.
-- NOTES   :
--   • All tables use CLUSTERED COLUMNSTORE INDEX (CCI).
--   • All tables use DISTRIBUTION = REPLICATE (small, stable reference
--     data; broadcast avoids shuffle in analytical joins to fact tables).
--   • No SCD2 versioning columns (effective_from/to, is_current) –
--     Gold dims always represent the current state.
--   • scd_hash and audit pipeline columns are retained for lineage only.
--   • Run this script in the Dedicated Pool database context.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Section 0 : Schema guard
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO


-- =============================================================================
-- Section 1 : gld_dim_date
--   Full Gregorian + fiscal calendar with banking business day flags.
--   Identical to Silver; kept in Gold schema so Gold queries need only
--   reference the Gold schema – no cross-schema joins required.
-- =============================================================================
IF OBJECT_ID('gold.gld_dim_date', 'U') IS NOT NULL
    DROP TABLE gold.gld_dim_date;
GO

CREATE TABLE gold.gld_dim_date
(
    -- Surrogate key (YYYYMMDD integer)
    date_sk                     INT             NOT NULL,

    -- Natural key
    full_date                   DATE            NOT NULL,

    -- Gregorian calendar attributes
    calendar_year               SMALLINT        NOT NULL,
    calendar_quarter            TINYINT         NOT NULL,   -- 1–4
    calendar_month_num          TINYINT         NOT NULL,   -- 1–12
    calendar_month_name         NVARCHAR(10)    NOT NULL,
    calendar_month_abbr         CHAR(3)         NOT NULL,
    calendar_week_num           TINYINT         NOT NULL,   -- ISO 8601 week 1–53
    day_of_year                 SMALLINT        NOT NULL,   -- 1–366
    day_of_month                TINYINT         NOT NULL,   -- 1–31
    day_of_week_num             TINYINT         NOT NULL,   -- 1 = Sunday, 7 = Saturday
    day_of_week_name            NVARCHAR(10)    NOT NULL,
    day_of_week_abbr            CHAR(3)         NOT NULL,

    -- Formatted labels (convenient for reporting)
    quarter_label               NVARCHAR(8)     NULL,       -- e.g. 2025-Q2
    year_month_label            NVARCHAR(8)     NULL,       -- e.g. 2025-06

    -- Business calendar flags
    is_weekday                  BIT             NOT NULL    DEFAULT 1,
    is_weekend                  BIT             NOT NULL    DEFAULT 0,
    is_public_holiday           BIT             NOT NULL    DEFAULT 0,
    public_holiday_name         NVARCHAR(100)   NULL,
    is_last_day_of_month        BIT             NOT NULL    DEFAULT 0,
    is_last_day_of_quarter      BIT             NOT NULL    DEFAULT 0,
    is_last_day_of_year         BIT             NOT NULL    DEFAULT 0,

    -- Fiscal calendar
    fiscal_year                 SMALLINT        NOT NULL,
    fiscal_quarter              TINYINT         NOT NULL,
    fiscal_month_num            TINYINT         NOT NULL,
    fiscal_period_name          NVARCHAR(20)    NULL,

    -- Relative helpers (refreshed daily)
    days_from_today             INT             NULL,
    is_current_day              BIT             NOT NULL    DEFAULT 0,
    is_current_month            BIT             NOT NULL    DEFAULT 0,
    is_current_quarter          BIT             NOT NULL    DEFAULT 0,
    is_current_year             BIT             NOT NULL    DEFAULT 0,

    -- Audit
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- Point-lookup index retained for BI tool date-picker queries
CREATE NONCLUSTERED INDEX nix_gld_dim_date_sk
    ON gold.gld_dim_date (date_sk)
    WITH (DATA_COMPRESSION = PAGE);
GO


-- =============================================================================
-- Section 2 : gld_dim_account
--   Flattened current-snapshot account dimension (no SCD2 history).
--   Enriched with derived risk and segment attributes for reporting.
-- =============================================================================
IF OBJECT_ID('gold.gld_dim_account', 'U') IS NOT NULL
    DROP TABLE gold.gld_dim_account;
GO

CREATE TABLE gold.gld_dim_account
(
    -- Surrogate key (matches current Silver SK for lineage)
    account_sk                  BIGINT          NOT NULL,

    -- Natural / business key
    account_id                  NVARCHAR(32)    NOT NULL,

    -- Classification
    account_type                NVARCHAR(50)    NOT NULL,
    account_sub_type            NVARCHAR(50)    NULL,
    product_code                NVARCHAR(30)    NULL,

    -- Financial attributes
    currency_code               CHAR(3)         NOT NULL,
    credit_limit                DECIMAL(20, 4)  NULL,
    overdraft_limit             DECIMAL(20, 4)  NULL,

    -- Branch / geography
    branch_code                 NVARCHAR(20)    NULL,
    branch_name                 NVARCHAR(100)   NULL,
    region                      NVARCHAR(50)    NULL,
    country_code                CHAR(2)         NULL,

    -- Status & risk
    account_status              NVARCHAR(20)    NOT NULL,
    account_segment             NVARCHAR(30)    NULL,
    risk_rating                 NVARCHAR(10)    NULL,
    aml_risk_category           NVARCHAR(20)    NULL,

    -- Lifecycle
    opened_date                 DATE            NULL,
    account_age_days            INT             NULL,       -- Derived: DATEDIFF(DAY, opened_date, GETUTCDATE())

    -- Customer link
    primary_customer_id         NVARCHAR(32)    NULL,

    -- Audit / lineage
    silver_account_sk           BIGINT          NULL,       -- Source SK from silver.slv_dim_account
    silver_effective_from       DATE            NULL,
    source_system               NVARCHAR(50)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 3 : gld_dim_customer
--   Current-snapshot customer dimension with enriched segmentation and
--   derived attributes; PII fields remain masked / tokenised.
-- =============================================================================
IF OBJECT_ID('gold.gld_dim_customer', 'U') IS NOT NULL
    DROP TABLE gold.gld_dim_customer;
GO

CREATE TABLE gold.gld_dim_customer
(
    -- Surrogate key
    customer_sk                 BIGINT          NOT NULL,

    -- Natural key
    customer_id                 NVARCHAR(32)    NOT NULL,

    -- Demographics (masked / aggregated for PII compliance)
    customer_type               NVARCHAR(20)    NOT NULL,
    full_name                   NVARCHAR(200)   NULL,       -- Tokenised display name
    age_band                    NVARCHAR(10)    NULL,       -- e.g. 25-34, 35-44
    gender                      NVARCHAR(10)    NULL,
    nationality                 CHAR(2)         NULL,

    -- Contact (domain-only; no local-part of email address)
    email_domain                NVARCHAR(100)   NULL,
    mobile_country_code         NVARCHAR(5)     NULL,
    preferred_channel           NVARCHAR(30)    NULL,
    preferred_language          CHAR(5)         NULL,

    -- Address (region-level only)
    address_country_code        CHAR(2)         NULL,
    address_region              NVARCHAR(100)   NULL,
    address_city                NVARCHAR(100)   NULL,

    -- KYC / CDD (status only; sensitive detail in vault)
    kyc_status                  NVARCHAR(20)    NULL,
    kyc_level                   NVARCHAR(20)    NULL,
    aml_risk_rating             NVARCHAR(10)    NULL,
    pep_flag                    BIT             NULL,
    sanctions_flag              BIT             NULL,
    adverse_media_flag          BIT             NULL,

    -- Segmentation & lifecycle
    customer_segment            NVARCHAR(30)    NULL,
    customer_sub_segment        NVARCHAR(30)    NULL,
    customer_tenure_years       DECIMAL(5, 2)   NULL,
    onboarding_channel          NVARCHAR(30)    NULL,
    onboarding_date             DATE            NULL,
    churn_risk_score            FLOAT           NULL,
    churn_risk_band             NVARCHAR(10)    NULL,       -- LOW, MEDIUM, HIGH

    -- Audit / lineage
    silver_customer_sk          BIGINT          NULL,
    silver_effective_from       DATE            NULL,
    source_system               NVARCHAR(50)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 4 : gld_dim_channel
-- =============================================================================
IF OBJECT_ID('gold.gld_dim_channel', 'U') IS NOT NULL
    DROP TABLE gold.gld_dim_channel;
GO

CREATE TABLE gold.gld_dim_channel
(
    -- Surrogate key
    channel_sk                  INT             NOT NULL,

    -- Natural key
    channel_code                NVARCHAR(30)    NOT NULL,

    -- Descriptive attributes
    channel_name                NVARCHAR(100)   NOT NULL,
    channel_category            NVARCHAR(50)    NULL,       -- DIGITAL, PHYSICAL, ASSISTED
    channel_description         NVARCHAR(500)   NULL,
    parent_channel_code         NVARCHAR(30)    NULL,

    -- Flags
    is_digital                  BIT             NOT NULL    DEFAULT 1,
    is_self_service             BIT             NOT NULL    DEFAULT 1,
    is_real_time                BIT             NOT NULL    DEFAULT 1,
    is_active                   BIT             NOT NULL    DEFAULT 1,
    supported_auth_methods      NVARCHAR(200)   NULL,
    sort_order                  TINYINT         NULL,

    -- Audit / lineage
    silver_channel_sk           INT             NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 5 : gld_dim_transaction_type
-- =============================================================================
IF OBJECT_ID('gold.gld_dim_transaction_type', 'U') IS NOT NULL
    DROP TABLE gold.gld_dim_transaction_type;
GO

CREATE TABLE gold.gld_dim_transaction_type
(
    -- Surrogate key
    transaction_type_sk         INT             NOT NULL,

    -- Natural key
    transaction_type_code       NVARCHAR(50)    NOT NULL,

    -- Descriptive attributes
    transaction_type_name       NVARCHAR(100)   NOT NULL,
    transaction_category        NVARCHAR(50)    NULL,
    transaction_sub_category    NVARCHAR(50)    NULL,
    parent_type_code            NVARCHAR(50)    NULL,
    reporting_group             NVARCHAR(50)    NULL,

    -- Flags & rules
    is_reversible               BIT             NOT NULL    DEFAULT 1,
    requires_authorisation      BIT             NOT NULL    DEFAULT 0,
    is_fee_bearing              BIT             NOT NULL    DEFAULT 0,
    affects_balance             BIT             NOT NULL    DEFAULT 1,

    -- Regulatory
    regulatory_category         NVARCHAR(50)    NULL,
    reporting_threshold_ccy     NVARCHAR(3)     NULL,
    reporting_threshold_amt     DECIMAL(20, 4)  NULL,

    is_active                   BIT             NOT NULL    DEFAULT 1,

    -- Audit / lineage
    silver_txn_type_sk          INT             NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 6 : gld_dim_service
-- =============================================================================
IF OBJECT_ID('gold.gld_dim_service', 'U') IS NOT NULL
    DROP TABLE gold.gld_dim_service;
GO

CREATE TABLE gold.gld_dim_service
(
    -- Surrogate key
    service_sk                  INT             NOT NULL,

    -- Natural key
    service_name                NVARCHAR(100)   NOT NULL,

    -- Descriptive attributes
    service_code                NVARCHAR(50)    NULL,
    service_version             NVARCHAR(20)    NULL,
    service_description         NVARCHAR(500)   NULL,
    service_owner_team          NVARCHAR(100)   NULL,
    service_domain              NVARCHAR(50)    NULL,
    service_subdomain           NVARCHAR(50)    NULL,
    service_tier                NVARCHAR(10)    NULL,

    -- Infrastructure
    environment                 NVARCHAR(20)    NULL,
    hosting_platform            NVARCHAR(30)    NULL,
    region                      NVARCHAR(30)    NULL,
    namespace                   NVARCHAR(100)   NULL,

    -- SLA
    sla_tier                    NVARCHAR(10)    NULL,
    rto_minutes                 INT             NULL,
    rpo_minutes                 INT             NULL,

    is_active                   BIT             NOT NULL    DEFAULT 1,

    -- Audit / lineage
    silver_service_sk           INT             NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- =============================================================================
-- End of 004_gold_dimensions.sql
-- =============================================================================
