-- =============================================================================
-- FILE    : 002_silver_dimensions.sql
-- LAYER   : Silver (Cleansed & Conformed)
-- ENGINE  : Azure Synapse Analytics – Dedicated SQL Pool
-- PURPOSE : Dimension table DDLs for the Silver layer.
--           These tables receive cleansed, deduplicated, and standardised
--           data from Bronze via ADF / Synapse pipelines.
-- NOTES   :
--   • All tables use CLUSTERED COLUMNSTORE INDEX (CCI) for analytical
--     query performance.
--   • Small / low-cardinality dims → DISTRIBUTION = REPLICATE.
--   • Large dims (account, customer) → DISTRIBUTION = HASH on natural key.
--   • SCD Type 2 dims include effective_from, effective_to, is_current,
--     and a SHA2_256 hash column (scd_hash) for change detection.
--   • Surrogate keys are BIGINT / INT IDENTITY(1,1) – internal only.
--   • Run this script in the Dedicated Pool database context.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Section 0 : Schema
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO


-- =============================================================================
-- Section 1 : slv_dim_date
--   Static calendar dimension pre-populated by pipeline.
--   No SCD – calendar dates are immutable.
--   REPLICATE: ~50 000 rows across a 100-year span.
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_date', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_date;
GO

CREATE TABLE silver.slv_dim_date
(
    -- Surrogate key (YYYYMMDD integer – efficient predicate pushdown)
    date_sk                 INT             NOT NULL,

    -- Natural key
    full_date               DATE            NOT NULL,

    -- Gregorian calendar attributes
    calendar_year           SMALLINT        NOT NULL,
    calendar_quarter        TINYINT         NOT NULL,   -- 1–4
    calendar_month_num      TINYINT         NOT NULL,   -- 1–12
    calendar_month_name     NVARCHAR(10)    NOT NULL,   -- January … December
    calendar_month_abbr     CHAR(3)         NOT NULL,   -- Jan … Dec
    calendar_week_num       TINYINT         NOT NULL,   -- ISO 8601 week: 1–53
    day_of_year             SMALLINT        NOT NULL,   -- 1–366
    day_of_month            TINYINT         NOT NULL,   -- 1–31
    day_of_week_num         TINYINT         NOT NULL,   -- 1 = Sunday, 7 = Saturday
    day_of_week_name        NVARCHAR(10)    NOT NULL,
    day_of_week_abbr        CHAR(3)         NOT NULL,

    -- Quarter / year labels
    quarter_label           NVARCHAR(8)     NULL,       -- e.g. 2025-Q1
    year_month_label        NVARCHAR(8)     NULL,       -- e.g. 2025-01

    -- Business calendar flags
    is_weekday              BIT             NOT NULL    DEFAULT 1,
    is_weekend              BIT             NOT NULL    DEFAULT 0,
    is_public_holiday       BIT             NOT NULL    DEFAULT 0,
    public_holiday_name     NVARCHAR(100)   NULL,
    is_last_day_of_month    BIT             NOT NULL    DEFAULT 0,
    is_last_day_of_quarter  BIT             NOT NULL    DEFAULT 0,
    is_last_day_of_year     BIT             NOT NULL    DEFAULT 0,

    -- Fiscal calendar (adjust fiscal year start offset per policy)
    fiscal_year             SMALLINT        NOT NULL,
    fiscal_quarter          TINYINT         NOT NULL,
    fiscal_month_num        TINYINT         NOT NULL,
    fiscal_period_name      NVARCHAR(20)    NULL,       -- e.g. FY2025-M03

    -- Relative helpers (refreshed by a daily stored procedure)
    days_from_today         INT             NULL,
    is_current_day          BIT             NOT NULL    DEFAULT 0,
    is_current_month        BIT             NOT NULL    DEFAULT 0,
    is_current_quarter      BIT             NOT NULL    DEFAULT 0,
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

-- Point-lookup optimisation on the integer surrogate key
CREATE NONCLUSTERED INDEX nix_slv_dim_date_sk
    ON silver.slv_dim_date (date_sk)
    WITH (DATA_COMPRESSION = PAGE);
GO


-- =============================================================================
-- Section 2 : slv_dim_account  (SCD Type 2)
--   Large table – HASH distribution on natural key for even distribution.
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_account', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_account;
GO

CREATE TABLE silver.slv_dim_account
(
    -- Surrogate key
    account_sk              BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural / business key
    account_id              NVARCHAR(32)    NOT NULL,

    -- Account classification
    account_type            NVARCHAR(50)    NOT NULL,   -- SAVINGS, CURRENT, LOAN, CREDIT_CARD
    account_sub_type        NVARCHAR(50)    NULL,
    product_code            NVARCHAR(30)    NULL,

    -- Financial attributes
    currency_code           CHAR(3)         NOT NULL,   -- ISO 4217
    credit_limit            DECIMAL(20, 4)  NULL,
    overdraft_limit         DECIMAL(20, 4)  NULL,

    -- Branch / geography
    branch_code             NVARCHAR(20)    NULL,
    branch_name             NVARCHAR(100)   NULL,
    region                  NVARCHAR(50)    NULL,
    country_code            CHAR(2)         NULL,       -- ISO 3166-1 alpha-2

    -- Status & risk
    account_status          NVARCHAR(20)    NOT NULL,   -- ACTIVE, DORMANT, CLOSED, FROZEN
    account_segment         NVARCHAR(30)    NULL,       -- RETAIL, SME, CORPORATE, PRIVATE
    risk_rating             NVARCHAR(10)    NULL,       -- A, B, C, D
    aml_risk_category       NVARCHAR(20)    NULL,

    -- Lifecycle dates
    opened_date             DATE            NULL,
    closed_date             DATE            NULL,

    -- Ownership link
    primary_customer_id     NVARCHAR(32)    NULL,

    -- SCD Type 2 versioning columns
    effective_from          DATE            NOT NULL,
    effective_to            DATE            NOT NULL    DEFAULT '9999-12-31',
    is_current              BIT             NOT NULL    DEFAULT 1,
    scd_hash                BINARY(32)      NULL,       -- SHA2_256 of all tracked attribute cols

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


-- =============================================================================
-- Section 3 : slv_dim_customer  (SCD Type 2)
-- =============================================================================
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
    nationality             CHAR(2)         NULL,       -- ISO 3166-1 alpha-2
    tax_id_masked           NVARCHAR(20)    NULL,       -- Masked / tokenised for PII compliance

    -- Contact (tokenised / domain-only for PII protection)
    email_domain            NVARCHAR(100)   NULL,       -- Domain portion only; local-part excluded
    mobile_country_code     NVARCHAR(5)     NULL,
    preferred_channel       NVARCHAR(30)    NULL,
    preferred_language      CHAR(5)         NULL,       -- BCP-47 e.g. en-GB

    -- Address (region-level only – full address stored in vault)
    address_country_code    CHAR(2)         NULL,
    address_region          NVARCHAR(100)   NULL,
    address_city            NVARCHAR(100)   NULL,
    address_postcode_prefix NVARCHAR(10)    NULL,       -- First 3–4 chars only

    -- KYC / CDD
    kyc_status              NVARCHAR(20)    NULL,       -- VERIFIED, PENDING, FAILED, EXPIRED
    kyc_verified_date       DATE            NULL,
    kyc_level               NVARCHAR(20)    NULL,       -- BASIC, STANDARD, ENHANCED
    aml_risk_rating         NVARCHAR(10)    NULL,
    pep_flag                BIT             NULL,       -- Politically Exposed Person
    sanctions_flag          BIT             NULL,
    adverse_media_flag      BIT             NULL,

    -- Segmentation / lifecycle
    customer_segment        NVARCHAR(30)    NULL,       -- MASS, PREMIUM, PRIVATE, CORPORATE
    customer_sub_segment    NVARCHAR(30)    NULL,
    customer_tenure_years   DECIMAL(5, 2)   NULL,
    onboarding_channel      NVARCHAR(30)    NULL,
    onboarding_date         DATE            NULL,
    churn_risk_score        FLOAT           NULL,

    -- SCD Type 2 versioning columns
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


-- =============================================================================
-- Section 4 : slv_dim_channel  (Type 1 – overwrite, no SCD)
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_channel', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_channel;
GO

CREATE TABLE silver.slv_dim_channel
(
    -- Surrogate key
    channel_sk              INT             NOT NULL    IDENTITY(1,1),

    -- Natural key
    channel_code            NVARCHAR(30)    NOT NULL,   -- WEB, MOBILE, ATM, BRANCH, CALL_CENTRE

    -- Descriptive attributes
    channel_name            NVARCHAR(100)   NOT NULL,
    channel_category        NVARCHAR(50)    NULL,       -- DIGITAL, PHYSICAL, ASSISTED
    channel_description     NVARCHAR(500)   NULL,
    parent_channel_code     NVARCHAR(30)    NULL,       -- For hierarchical grouping

    -- Flags
    is_digital              BIT             NOT NULL    DEFAULT 1,
    is_self_service         BIT             NOT NULL    DEFAULT 1,
    is_real_time            BIT             NOT NULL    DEFAULT 1,
    is_active               BIT             NOT NULL    DEFAULT 1,

    -- Operational metadata
    supported_auth_methods  NVARCHAR(200)   NULL,       -- Comma-separated
    sort_order              TINYINT         NULL,

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 5 : slv_dim_transaction_type
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_transaction_type', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_transaction_type;
GO

CREATE TABLE silver.slv_dim_transaction_type
(
    -- Surrogate key
    transaction_type_sk     INT             NOT NULL    IDENTITY(1,1),

    -- Natural key
    transaction_type_code   NVARCHAR(50)    NOT NULL,

    -- Descriptive attributes
    transaction_type_name   NVARCHAR(100)   NOT NULL,
    transaction_category    NVARCHAR(50)    NULL,       -- DEBIT, CREDIT, FEE, REVERSAL, TRANSFER
    transaction_sub_category NVARCHAR(50)   NULL,
    parent_type_code        NVARCHAR(50)    NULL,       -- Hierarchical grouping
    reporting_group         NVARCHAR(50)    NULL,

    -- Flags & rules
    is_reversible           BIT             NOT NULL    DEFAULT 1,
    requires_authorisation  BIT             NOT NULL    DEFAULT 0,
    is_fee_bearing          BIT             NOT NULL    DEFAULT 0,
    affects_balance         BIT             NOT NULL    DEFAULT 1,

    -- Regulatory
    regulatory_category     NVARCHAR(50)    NULL,       -- PSD2, SWIFT, SEPA, BACS
    reporting_threshold_ccy NVARCHAR(3)     NULL,       -- Currency for threshold
    reporting_threshold_amt DECIMAL(20, 4)  NULL,       -- Amount above which regulatory reporting applies

    is_active               BIT             NOT NULL    DEFAULT 1,

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 6 : slv_dim_service
--   Represents internal microservices and application services.
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_service', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_service;
GO

CREATE TABLE silver.slv_dim_service
(
    -- Surrogate key
    service_sk              INT             NOT NULL    IDENTITY(1,1),

    -- Natural key
    service_name            NVARCHAR(100)   NOT NULL,

    -- Descriptive attributes
    service_code            NVARCHAR(50)    NULL,
    service_version         NVARCHAR(20)    NULL,
    service_description     NVARCHAR(500)   NULL,
    service_owner_team      NVARCHAR(100)   NULL,
    service_owner_email     NVARCHAR(200)   NULL,

    -- Taxonomy
    service_domain          NVARCHAR(50)    NULL,       -- PAYMENTS, AUTH, FRAUD, CORE_BANKING
    service_subdomain       NVARCHAR(50)    NULL,
    service_tier            NVARCHAR(10)    NULL,       -- FRONTEND, BACKEND, DATA, INTEGRATION

    -- Infrastructure metadata
    environment             NVARCHAR(20)    NULL,       -- PROD, UAT, DEV, DR
    hosting_platform        NVARCHAR(30)    NULL,       -- AKS, AZURE_FUNCTIONS, VM, APP_SERVICE
    region                  NVARCHAR(30)    NULL,
    namespace               NVARCHAR(100)   NULL,       -- Kubernetes namespace

    -- SLA & criticality
    sla_tier                NVARCHAR(10)    NULL,       -- P0, P1, P2, P3
    rto_minutes             INT             NULL,       -- Recovery Time Objective
    rpo_minutes             INT             NULL,       -- Recovery Point Objective

    is_active               BIT             NOT NULL    DEFAULT 1,

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 7 : slv_dim_error_type
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_error_type', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_error_type;
GO

CREATE TABLE silver.slv_dim_error_type
(
    -- Surrogate key
    error_type_sk               INT             NOT NULL    IDENTITY(1,1),

    -- Natural key
    error_type_code             NVARCHAR(50)    NOT NULL,

    -- Descriptive attributes
    error_type_name             NVARCHAR(100)   NOT NULL,
    error_category              NVARCHAR(50)    NULL,       -- SYSTEM, BUSINESS, NETWORK, SECURITY, DATA
    error_subcategory           NVARCHAR(50)    NULL,
    severity_default            NVARCHAR(10)    NULL,       -- INFO, WARN, ERROR, CRITICAL

    -- Operational guidance
    is_retriable                BIT             NOT NULL    DEFAULT 0,
    max_retry_count             INT             NULL,
    expected_in_prod            BIT             NOT NULL    DEFAULT 0,   -- Known / acceptable error
    requires_alerting           BIT             NOT NULL    DEFAULT 1,
    resolution_playbook_url     NVARCHAR(500)   NULL,
    owning_team                 NVARCHAR(100)   NULL,

    -- AI classification hint
    ai_classification_label     NVARCHAR(100)   NULL,

    is_active                   BIT             NOT NULL    DEFAULT 1,

    -- Audit
    created_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO


-- =============================================================================
-- Section 8 : slv_dim_auth_event_type
-- =============================================================================
IF OBJECT_ID('silver.slv_dim_auth_event_type', 'U') IS NOT NULL
    DROP TABLE silver.slv_dim_auth_event_type;
GO

CREATE TABLE silver.slv_dim_auth_event_type
(
    -- Surrogate key
    auth_event_type_sk      INT             NOT NULL    IDENTITY(1,1),

    -- Natural key
    event_type_code         NVARCHAR(50)    NOT NULL,

    -- Descriptive attributes
    event_type_name         NVARCHAR(100)   NOT NULL,
    event_category          NVARCHAR(50)    NULL,       -- AUTHENTICATION, AUTHORISATION, SESSION
    event_subcategory       NVARCHAR(50)    NULL,
    auth_method_group       NVARCHAR(50)    NULL,       -- PASSWORD, BIOMETRIC, OTP, TOKEN, CERTIFICATE

    -- Risk / compliance flags
    mfa_required            BIT             NOT NULL    DEFAULT 0,
    risk_indicator_flag     BIT             NOT NULL    DEFAULT 0,   -- Signals elevated risk
    regulatory_relevant     BIT             NOT NULL    DEFAULT 0,   -- Relevant for PSD2 SCA / audit
    is_session_terminating  BIT             NOT NULL    DEFAULT 0,   -- e.g. LOGOUT, FORCE_EXPIRE

    -- Fraud detection integration
    triggers_fraud_check    BIT             NOT NULL    DEFAULT 0,

    is_active               BIT             NOT NULL    DEFAULT 1,

    -- Audit
    created_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    updated_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = REPLICATE
);
GO

-- =============================================================================
-- End of 002_silver_dimensions.sql
-- =============================================================================
