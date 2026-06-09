-- ============================================================
-- FILE    : 001_bronze_tables.sql
-- LAYER   : Bronze (Raw Ingestion)
-- ENGINE  : Azure Synapse Analytics – Serverless SQL Pool
-- PURPOSE : External table definitions over ADLS Gen2 Delta /
--           Parquet files.  Tables are read-only projections of
--           raw data; no transformations are applied here.
-- NOTES   :
--   • Replace {storage_account} with the real storage account name.
--   • Replace {managed_identity_or_sas_credential} with the name
--     of the DATABASE SCOPED CREDENTIAL you have already created.
--   • All LOCATION paths use the abfss:// driver (ADLS Gen2 HNS).
--   • FORMAT = 'DELTA' requires Synapse Serverless GA support
--     (available in all regions as of 2024).
--   • Partitioning is surfaced via an ingestion_date virtual
--     partition column written by the ingest pipeline.
-- ============================================================

-- ------------------------------------------------------------
-- Section 0 : Database context
-- ------------------------------------------------------------
-- Run once per environment; comment out if DB already exists.
-- CREATE DATABASE bronze_db
--     COLLATE Latin1_General_100_BIN2_UTF8;
-- GO

USE bronze_db;
GO

-- ------------------------------------------------------------
-- Section 1 : Credential (placeholder – create beforehand)
-- ------------------------------------------------------------
-- CREATE DATABASE SCOPED CREDENTIAL BronzeCredential
--     WITH IDENTITY = 'Managed Identity';
-- GO

-- ------------------------------------------------------------
-- Section 2 : External Data Source
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.external_data_sources
    WHERE  name = 'BronzeDataSource'
)
BEGIN
    CREATE EXTERNAL DATA SOURCE BronzeDataSource
    WITH (
        LOCATION   = 'abfss://bronze@{storage_account}.dfs.core.windows.net',
        CREDENTIAL = BronzeCredential
    );
END
GO

-- ------------------------------------------------------------
-- Section 3 : External File Formats
-- ------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.external_file_formats
    WHERE  name = 'DeltaFormat'
)
BEGIN
    CREATE EXTERNAL FILE FORMAT DeltaFormat
    WITH (FORMAT_TYPE = DELTA);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.external_file_formats
    WHERE  name = 'ParquetFormat'
)
BEGIN
    CREATE EXTERNAL FILE FORMAT ParquetFormat
    WITH (
        FORMAT_TYPE = PARQUET,
        DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
    );
END
GO

-- ============================================================
-- Section 4 : Bronze External Tables
-- ============================================================

-- ------------------------------------------------------------
-- 4.1  brz_transaction_logs
--      Source : core banking / payment switch CDC feed
--      Format : Delta Lake
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.brz_transaction_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_transaction_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_transaction_logs
(
    -- Source identifiers
    transaction_id          NVARCHAR(64)        NOT NULL,   -- UUID / bank TXN ref
    correlation_id          NVARCHAR(64)        NULL,       -- end-to-end trace ID
    session_id              NVARCHAR(64)        NULL,

    -- Account / party
    account_id              NVARCHAR(32)        NOT NULL,
    customer_id             NVARCHAR(32)        NULL,
    debit_account_id        NVARCHAR(32)        NULL,
    credit_account_id       NVARCHAR(32)        NULL,

    -- Transaction attributes
    transaction_type        NVARCHAR(50)        NOT NULL,   -- TRANSFER, PAYMENT, …
    channel                 NVARCHAR(30)        NULL,       -- WEB, MOBILE, ATM, …
    currency_code           CHAR(3)             NOT NULL,
    amount                  DECIMAL(20, 4)      NOT NULL,
    fee_amount              DECIMAL(20, 4)      NULL,
    exchange_rate           DECIMAL(18, 8)      NULL,

    -- Status
    transaction_status      NVARCHAR(20)        NOT NULL,   -- INITIATED, COMPLETED, …
    failure_reason          NVARCHAR(500)       NULL,
    response_code           NVARCHAR(10)        NULL,

    -- Timestamps (UTC)
    initiated_at            DATETIME2(6)        NOT NULL,
    completed_at            DATETIME2(6)        NULL,
    processing_duration_ms  INT                 NULL,

    -- Network / device context
    ip_address              NVARCHAR(45)        NULL,
    device_id               NVARCHAR(64)        NULL,
    user_agent              NVARCHAR(500)       NULL,
    geo_country             CHAR(2)             NULL,
    geo_city                NVARCHAR(100)       NULL,

    -- AI / ML scoring (populated by real-time scoring service)
    risk_score_raw          FLOAT               NULL,
    risk_label_raw          NVARCHAR(20)        NULL,

    -- Metadata
    source_system           NVARCHAR(50)        NULL,
    record_version          INT                 NULL,
    is_deleted              BIT                 NULL,       -- soft-delete flag from CDC
    ingestion_date          DATE                NOT NULL    -- partition column
)
WITH (
    DATA_SOURCE       = BronzeDataSource,
    LOCATION          = '/transaction_logs/',
    FILE_FORMAT       = DeltaFormat
);
GO

-- ------------------------------------------------------------
-- 4.2  brz_auth_logs
--      Source : IAM / authentication service
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.brz_auth_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_auth_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_auth_logs
(
    -- Identifiers
    auth_event_id           NVARCHAR(64)        NOT NULL,
    correlation_id          NVARCHAR(64)        NULL,
    session_id              NVARCHAR(64)        NULL,

    -- Principal
    user_id                 NVARCHAR(64)        NULL,
    account_id              NVARCHAR(32)        NULL,
    customer_id             NVARCHAR(32)        NULL,
    service_principal_id    NVARCHAR(64)        NULL,

    -- Auth event
    event_type              NVARCHAR(50)        NOT NULL,   -- LOGIN, LOGOUT, MFA_CHALLENGE, …
    auth_method             NVARCHAR(30)        NULL,       -- PASSWORD, OTP, BIOMETRIC, …
    auth_result             NVARCHAR(20)        NOT NULL,   -- SUCCESS, FAILURE, LOCKED
    failure_reason          NVARCHAR(500)       NULL,
    step_up_required        BIT                 NULL,

    -- Channel / device
    channel                 NVARCHAR(30)        NULL,
    ip_address              NVARCHAR(45)        NULL,
    device_id               NVARCHAR(64)        NULL,
    device_type             NVARCHAR(30)        NULL,
    user_agent              NVARCHAR(500)       NULL,
    geo_country             CHAR(2)             NULL,
    geo_city                NVARCHAR(100)       NULL,

    -- Timestamps
    event_timestamp         DATETIME2(6)        NOT NULL,
    token_issued_at         DATETIME2(6)        NULL,
    token_expires_at        DATETIME2(6)        NULL,

    -- Risk
    risk_score_raw          FLOAT               NULL,
    risk_label_raw          NVARCHAR(20)        NULL,

    -- Metadata
    source_system           NVARCHAR(50)        NULL,
    record_version          INT                 NULL,
    is_deleted              BIT                 NULL,
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE       = BronzeDataSource,
    LOCATION          = '/auth_logs/',
    FILE_FORMAT       = DeltaFormat
);
GO

-- ------------------------------------------------------------
-- 4.3  brz_api_gateway_logs
--      Source : API Management / Kong / NGINX access logs
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.brz_api_gateway_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_api_gateway_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_api_gateway_logs
(
    -- Request identifiers
    request_id              NVARCHAR(64)        NOT NULL,
    correlation_id          NVARCHAR(64)        NULL,
    trace_id                NVARCHAR(64)        NULL,
    span_id                 NVARCHAR(32)        NULL,

    -- API surface
    api_name                NVARCHAR(100)       NULL,
    api_version             NVARCHAR(20)        NULL,
    operation_id            NVARCHAR(100)       NULL,
    http_method             NVARCHAR(10)        NOT NULL,
    request_path            NVARCHAR(2048)      NOT NULL,
    query_string            NVARCHAR(4000)      NULL,

    -- Client
    consumer_id             NVARCHAR(64)        NULL,
    subscription_key_id     NVARCHAR(64)        NULL,
    ip_address              NVARCHAR(45)        NULL,
    user_agent              NVARCHAR(500)       NULL,

    -- Response
    http_status_code        SMALLINT            NOT NULL,
    response_size_bytes     INT                 NULL,
    backend_latency_ms      INT                 NULL,
    gateway_latency_ms      INT                 NULL,
    total_latency_ms        INT                 NULL,
    error_code              NVARCHAR(50)        NULL,
    error_message           NVARCHAR(1000)      NULL,

    -- Security
    tls_version             NVARCHAR(10)        NULL,
    auth_scheme             NVARCHAR(30)        NULL,
    jwt_subject             NVARCHAR(128)       NULL,

    -- Timestamps
    request_timestamp       DATETIME2(6)        NOT NULL,
    response_timestamp      DATETIME2(6)        NULL,

    -- Metadata
    region                  NVARCHAR(30)        NULL,
    gateway_node_id         NVARCHAR(64)        NULL,
    source_system           NVARCHAR(50)        NULL,
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE       = BronzeDataSource,
    LOCATION          = '/api_gateway_logs/',
    FILE_FORMAT       = DeltaFormat
);
GO

-- ------------------------------------------------------------
-- 4.4  brz_application_error_logs
--      Source : Application Insights / Splunk HEC
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.brz_application_error_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_application_error_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_application_error_logs
(
    -- Identifiers
    error_event_id          NVARCHAR(64)        NOT NULL,
    correlation_id          NVARCHAR(64)        NULL,
    trace_id                NVARCHAR(64)        NULL,
    span_id                 NVARCHAR(32)        NULL,

    -- Application context
    application_name        NVARCHAR(100)       NOT NULL,
    application_version     NVARCHAR(30)        NULL,
    environment             NVARCHAR(20)        NULL,   -- PROD, UAT, …
    service_name            NVARCHAR(100)       NULL,
    host_name               NVARCHAR(100)       NULL,
    container_id            NVARCHAR(128)       NULL,
    pod_name                NVARCHAR(128)       NULL,

    -- Error details
    severity_level          NVARCHAR(10)        NOT NULL,   -- ERROR, CRITICAL, WARN
    error_type              NVARCHAR(100)       NULL,
    error_code              NVARCHAR(50)        NULL,
    error_message           NVARCHAR(4000)      NULL,
    stack_trace             NVARCHAR(MAX)       NULL,
    inner_exception         NVARCHAR(4000)      NULL,

    -- Context
    operation_name          NVARCHAR(200)       NULL,
    user_id                 NVARCHAR(64)        NULL,
    session_id              NVARCHAR(64)        NULL,
    request_id              NVARCHAR(64)        NULL,
    custom_dimensions       NVARCHAR(MAX)       NULL,   -- JSON blob

    -- Timestamps
    event_timestamp         DATETIME2(6)        NOT NULL,

    -- Metadata
    source_system           NVARCHAR(50)        NULL,
    log_stream              NVARCHAR(50)        NULL,
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE       = BronzeDataSource,
    LOCATION          = '/application_error_logs/',
    FILE_FORMAT       = DeltaFormat
);
GO

-- ------------------------------------------------------------
-- 4.5  brz_audit_logs
--      Source : Banking core system audit trail / HSM audit
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.brz_audit_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_audit_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_audit_logs
(
    -- Identifiers
    audit_event_id          NVARCHAR(64)        NOT NULL,
    correlation_id          NVARCHAR(64)        NULL,

    -- Actor
    actor_user_id           NVARCHAR(64)        NOT NULL,
    actor_role              NVARCHAR(100)       NULL,
    actor_department        NVARCHAR(100)       NULL,
    actor_ip_address        NVARCHAR(45)        NULL,
    actor_device_id         NVARCHAR(64)        NULL,

    -- Action
    action_type             NVARCHAR(50)        NOT NULL,   -- READ, WRITE, DELETE, APPROVE
    action_result           NVARCHAR(20)        NOT NULL,   -- SUCCESS, FAILURE, DENIED
    resource_type           NVARCHAR(100)       NULL,
    resource_id             NVARCHAR(128)       NULL,
    resource_owner_id       NVARCHAR(64)        NULL,

    -- Change capture
    old_value               NVARCHAR(MAX)       NULL,   -- JSON
    new_value               NVARCHAR(MAX)       NULL,   -- JSON
    change_summary          NVARCHAR(1000)      NULL,

    -- Regulatory / compliance tagging
    regulatory_flag         NVARCHAR(50)        NULL,   -- GDPR, PCI-DSS, SOX, …
    data_classification     NVARCHAR(30)        NULL,   -- PUBLIC, INTERNAL, CONFIDENTIAL

    -- Application context
    application_name        NVARCHAR(100)       NULL,
    service_name            NVARCHAR(100)       NULL,
    environment             NVARCHAR(20)        NULL,

    -- Timestamps
    event_timestamp         DATETIME2(6)        NOT NULL,

    -- Metadata
    source_system           NVARCHAR(50)        NULL,
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE       = BronzeDataSource,
    LOCATION          = '/audit_logs/',
    FILE_FORMAT       = DeltaFormat
);
GO

-- ------------------------------------------------------------
-- 4.6  brz_fraud_alert_logs
--      Source : Fraud detection engine (real-time + batch)
-- ------------------------------------------------------------
IF OBJECT_ID('dbo.brz_fraud_alert_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_fraud_alert_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_fraud_alert_logs
(
    -- Identifiers
    alert_id                NVARCHAR(64)        NOT NULL,
    transaction_id          NVARCHAR(64)        NULL,
    correlation_id          NVARCHAR(64)        NULL,

    -- Linked entities
    account_id              NVARCHAR(32)        NULL,
    customer_id             NVARCHAR(32)        NULL,

    -- Alert details
    alert_type              NVARCHAR(50)        NOT NULL,   -- CARD_NOT_PRESENT, ATO, …
    alert_severity          NVARCHAR(10)        NOT NULL,   -- LOW, MEDIUM, HIGH, CRITICAL
    alert_status            NVARCHAR(20)        NOT NULL,   -- OPEN, REVIEWING, CLOSED
    fraud_score             FLOAT               NULL,
    fraud_model_version     NVARCHAR(30)        NULL,
    triggered_rules         NVARCHAR(MAX)       NULL,   -- JSON array of rule names
    contributing_features   NVARCHAR(MAX)       NULL,   -- JSON feature importance map

    -- Investigation
    analyst_id              NVARCHAR(64)        NULL,
    investigation_notes     NVARCHAR(4000)      NULL,
    resolution              NVARCHAR(50)        NULL,   -- CONFIRMED_FRAUD, FALSE_POSITIVE
    resolved_at             DATETIME2(6)        NULL,

    -- Amounts
    at_risk_amount          DECIMAL(20, 4)      NULL,
    currency_code           CHAR(3)             NULL,

    -- Timestamps
    alert_raised_at         DATETIME2(6)        NOT NULL,
    alert_updated_at        DATETIME2(6)        NULL,

    -- Metadata
    source_system           NVARCHAR(50)        NULL,
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE       = BronzeDataSource,
    LOCATION          = '/fraud_alert_logs/',
    FILE_FORMAT       = DeltaFormat
);
GO

-- ============================================================
-- End of 001_bronze_tables.sql
-- ============================================================
