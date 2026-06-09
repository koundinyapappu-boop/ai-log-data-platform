-- =============================================================================
-- FILE    : 001_bronze_tables.sql
-- LAYER   : Bronze (Raw Ingestion)
-- ENGINE  : Azure Synapse Analytics – Serverless SQL Pool
-- PURPOSE : External table DDLs over ADLS Gen2 Delta/Parquet files.
--           Tables are read-only projections of raw landing-zone data;
--           no transformations are applied at this layer.
-- NOTES   :
--   • Replace {storage_account} with the real ADLS Gen2 account name.
--   • BronzeCredential must be a DATABASE SCOPED CREDENTIAL created
--     beforehand (Managed Identity or SAS token).
--   • FORMAT = DELTA requires Synapse Serverless GA Delta Lake support.
--   • All LOCATION paths use the abfss:// HNS driver.
--   • ingestion_date is the virtual partition column written by ingest
--     pipelines; include it in WHERE clauses for partition elimination.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Section 0 : Database context
-- -----------------------------------------------------------------------------
-- Uncomment once per environment if the DB does not already exist:
-- CREATE DATABASE bronze_db COLLATE Latin1_General_100_BIN2_UTF8;
-- GO

USE bronze_db;
GO

-- -----------------------------------------------------------------------------
-- Section 1 : Credential (placeholder – must be created before running this
--             script).  Uncomment and adjust as needed:
-- -----------------------------------------------------------------------------
-- CREATE DATABASE SCOPED CREDENTIAL BronzeCredential
--     WITH IDENTITY = 'Managed Identity';
-- GO

-- -----------------------------------------------------------------------------
-- Section 2 : External Data Source
-- -----------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.external_data_sources
    WHERE  name = 'BronzeDataSource'
)
BEGIN
    CREATE EXTERNAL DATA SOURCE BronzeDataSource
    WITH (
        LOCATION   = 'abfss://bronze@{storage_account}.dfs.core.windows.net',
        CREDENTIAL = BronzeCredential          -- placeholder credential
    );
END
GO

-- -----------------------------------------------------------------------------
-- Section 3 : External File Formats
-- -----------------------------------------------------------------------------
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
        FORMAT_TYPE      = PARQUET,
        DATA_COMPRESSION = 'org.apache.hadoop.io.compress.SnappyCodec'
    );
END
GO


-- =============================================================================
-- Section 4 : Bronze External Tables
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 4.1  brz_transaction_logs
--      Source  : Core banking / payment switch CDC feed
--      Format  : Delta Lake
--      Partition: ingestion_date
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.brz_transaction_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_transaction_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_transaction_logs
(
    -- Source identifiers
    transaction_id          NVARCHAR(64)        NOT NULL,   -- UUID / bank TXN reference
    correlation_id          NVARCHAR(64)        NULL,       -- End-to-end distributed trace ID
    session_id              NVARCHAR(64)        NULL,

    -- Account / party
    account_id              NVARCHAR(32)        NOT NULL,
    customer_id             NVARCHAR(32)        NULL,
    debit_account_id        NVARCHAR(32)        NULL,
    credit_account_id       NVARCHAR(32)        NULL,       -- Counterparty destination account

    -- Transaction attributes
    transaction_type        NVARCHAR(50)        NOT NULL,   -- TRANSFER, PAYMENT, FX, etc.
    transaction_sub_type    NVARCHAR(50)        NULL,       -- WIRE, ACH, CARD_POS, etc.
    channel                 NVARCHAR(30)        NULL,       -- WEB, MOBILE, ATM, BRANCH, API
    currency_code           CHAR(3)             NOT NULL,   -- ISO 4217
    amount                  DECIMAL(20, 4)      NOT NULL,
    fee_amount              DECIMAL(20, 4)      NULL,
    base_currency_amount    DECIMAL(20, 4)      NULL,       -- FX-normalised amount
    exchange_rate           DECIMAL(18, 8)      NULL,

    -- Status & response codes
    transaction_status      NVARCHAR(20)        NOT NULL,   -- INITIATED, COMPLETED, FAILED, REVERSED
    failure_reason          NVARCHAR(500)       NULL,
    response_code           NVARCHAR(10)        NULL,       -- ISO 8583 / internal response code

    -- Timestamps (UTC)
    initiated_at            DATETIME2(6)        NOT NULL,
    completed_at            DATETIME2(6)        NULL,
    processing_duration_ms  INT                 NULL,

    -- Network / device context
    ip_address              NVARCHAR(45)        NULL,       -- IPv4 or IPv6
    device_id               NVARCHAR(64)        NULL,
    device_fingerprint      NVARCHAR(256)       NULL,
    user_agent              NVARCHAR(500)       NULL,
    geo_country             CHAR(2)             NULL,       -- ISO 3166-1 alpha-2
    geo_city                NVARCHAR(100)       NULL,
    geo_latitude            FLOAT               NULL,
    geo_longitude           FLOAT               NULL,

    -- Service metadata
    service_name            NVARCHAR(100)       NULL,
    service_version         NVARCHAR(30)        NULL,
    environment             NVARCHAR(20)        NULL,       -- PROD, UAT, DEV

    -- AI / ML scoring (populated by upstream real-time scoring service)
    risk_score_raw          FLOAT               NULL,
    risk_label_raw          NVARCHAR(20)        NULL,
    anomaly_flag_raw        NVARCHAR(5)         NULL,       -- TRUE / FALSE / UNKNOWN

    -- CDC / pipeline metadata
    source_system           NVARCHAR(50)        NULL,
    record_version          INT                 NULL,
    is_deleted              BIT                 NULL,       -- Soft-delete flag from CDC
    batch_id                NVARCHAR(64)        NULL,
    raw_payload             NVARCHAR(MAX)       NULL,       -- Original JSON/Avro payload

    -- Partition column (written by ADF / Synapse pipeline)
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE  = BronzeDataSource,
    LOCATION     = '/transaction_logs/',
    FILE_FORMAT  = DeltaFormat
);
GO


-- -----------------------------------------------------------------------------
-- 4.2  brz_auth_logs
--      Source  : IAM / authentication service (Azure AD B2C, custom IdP)
--      Format  : Delta Lake
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.brz_auth_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_auth_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_auth_logs
(
    -- Event identifiers
    auth_event_id           NVARCHAR(64)        NOT NULL,
    correlation_id          NVARCHAR(64)        NULL,
    session_id              NVARCHAR(64)        NULL,

    -- Principal
    user_id                 NVARCHAR(64)        NULL,
    account_id              NVARCHAR(32)        NULL,
    customer_id             NVARCHAR(32)        NULL,
    service_principal_id    NVARCHAR(64)        NULL,       -- For service-to-service auth

    -- Auth event classification
    event_type              NVARCHAR(50)        NOT NULL,   -- LOGIN, LOGOUT, MFA_CHALLENGE, TOKEN_REFRESH
    auth_method             NVARCHAR(30)        NULL,       -- PASSWORD, OTP, BIOMETRIC, CERTIFICATE
    mfa_method              NVARCHAR(30)        NULL,       -- SMS, TOTP, PUSH_NOTIFICATION, FIDO2
    auth_result             NVARCHAR(20)        NOT NULL,   -- SUCCESS, FAILURE, LOCKED, EXPIRED
    failure_reason          NVARCHAR(500)       NULL,
    failure_code            NVARCHAR(20)        NULL,
    attempt_count           INT                 NULL,
    step_up_required        BIT                 NULL,

    -- Channel / device context
    channel                 NVARCHAR(30)        NULL,
    application_name        NVARCHAR(100)       NULL,
    ip_address              NVARCHAR(45)        NULL,
    device_id               NVARCHAR(64)        NULL,
    device_type             NVARCHAR(30)        NULL,       -- MOBILE, DESKTOP, TABLET
    device_fingerprint      NVARCHAR(256)       NULL,
    os_platform             NVARCHAR(50)        NULL,
    browser                 NVARCHAR(100)       NULL,
    user_agent              NVARCHAR(500)       NULL,
    geo_country             CHAR(2)             NULL,
    geo_city                NVARCHAR(100)       NULL,
    geo_latitude            FLOAT               NULL,
    geo_longitude           FLOAT               NULL,
    is_vpn                  BIT                 NULL,
    is_tor_exit_node        BIT                 NULL,

    -- Token details
    token_issued_at         DATETIME2(6)        NULL,
    token_expires_at        DATETIME2(6)        NULL,
    session_started_at      DATETIME2(6)        NULL,
    session_ended_at        DATETIME2(6)        NULL,

    -- Risk signals (raw)
    risk_score_raw          FLOAT               NULL,
    risk_label_raw          NVARCHAR(20)        NULL,
    is_impossible_travel    BIT                 NULL,
    previous_geo_country    CHAR(2)             NULL,

    -- Timestamps
    event_timestamp         DATETIME2(6)        NOT NULL,

    -- CDC / pipeline metadata
    source_system           NVARCHAR(50)        NULL,
    record_version          INT                 NULL,
    is_deleted              BIT                 NULL,
    batch_id                NVARCHAR(64)        NULL,
    raw_payload             NVARCHAR(MAX)       NULL,

    -- Partition column
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE  = BronzeDataSource,
    LOCATION     = '/auth_logs/',
    FILE_FORMAT  = DeltaFormat
);
GO


-- -----------------------------------------------------------------------------
-- 4.3  brz_api_gateway_logs
--      Source  : Azure API Management / Kong / NGINX access logs
--      Format  : Delta Lake
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.brz_api_gateway_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_api_gateway_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_api_gateway_logs
(
    -- Request identifiers
    request_id              NVARCHAR(64)        NOT NULL,
    trace_id                NVARCHAR(128)       NULL,       -- W3C traceparent / Zipkin
    span_id                 NVARCHAR(32)        NULL,
    correlation_id          NVARCHAR(64)        NULL,
    session_id              NVARCHAR(64)        NULL,

    -- API surface
    api_name                NVARCHAR(100)       NULL,
    api_version             NVARCHAR(20)        NULL,
    operation_id            NVARCHAR(100)       NULL,
    http_method             NVARCHAR(10)        NOT NULL,   -- GET, POST, PUT, DELETE, PATCH
    request_path            NVARCHAR(2048)      NOT NULL,   -- Normalised path, no query params
    query_string            NVARCHAR(4000)      NULL,
    content_type            NVARCHAR(100)       NULL,
    request_size_bytes      INT                 NULL,

    -- Consumer identity
    consumer_id             NVARCHAR(64)        NULL,       -- Client app ID / API key hash
    consumer_type           NVARCHAR(50)        NULL,       -- INTERNAL, THIRD_PARTY, MOBILE_APP
    subscription_key_id     NVARCHAR(64)        NULL,
    user_id                 NVARCHAR(64)        NULL,
    customer_id             NVARCHAR(32)        NULL,
    ip_address              NVARCHAR(45)        NULL,
    forwarded_ip            NVARCHAR(45)        NULL,
    user_agent              NVARCHAR(500)       NULL,
    geo_country             CHAR(2)             NULL,

    -- Response
    http_status_code        SMALLINT            NOT NULL,
    response_size_bytes     INT                 NULL,
    backend_latency_ms      INT                 NULL,
    gateway_latency_ms      INT                 NULL,
    total_latency_ms        INT                 NULL,
    cache_hit               BIT                 NULL,
    error_code              NVARCHAR(50)        NULL,
    error_message           NVARCHAR(1000)      NULL,

    -- Security context
    tls_version             NVARCHAR(10)        NULL,
    auth_scheme             NVARCHAR(30)        NULL,       -- Bearer, Basic, API-Key
    jwt_subject             NVARCHAR(128)       NULL,
    rate_limit_remaining    INT                 NULL,
    rate_limit_reset_at     DATETIME2(6)        NULL,

    -- Backend routing
    backend_service         NVARCHAR(100)       NULL,
    backend_pod             NVARCHAR(200)       NULL,
    protocol                NVARCHAR(20)        NULL,       -- HTTP/1.1, HTTP/2, gRPC
    gateway_node_id         NVARCHAR(64)        NULL,
    region                  NVARCHAR(30)        NULL,

    -- Timestamps
    request_timestamp       DATETIME2(6)        NOT NULL,
    response_timestamp      DATETIME2(6)        NULL,

    -- CDC / pipeline metadata
    source_system           NVARCHAR(50)        NULL,
    batch_id                NVARCHAR(64)        NULL,
    raw_payload             NVARCHAR(MAX)       NULL,

    -- Partition column
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE  = BronzeDataSource,
    LOCATION     = '/api_gateway_logs/',
    FILE_FORMAT  = DeltaFormat
);
GO


-- -----------------------------------------------------------------------------
-- 4.4  brz_application_error_logs
--      Source  : Application Insights / Splunk HEC / Log Analytics
--      Format  : Delta Lake
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.brz_application_error_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_application_error_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_application_error_logs
(
    -- Event identifiers
    error_event_id          NVARCHAR(64)        NOT NULL,
    trace_id                NVARCHAR(128)       NULL,
    span_id                 NVARCHAR(32)        NULL,
    correlation_id          NVARCHAR(64)        NULL,

    -- Application context
    application_name        NVARCHAR(100)       NOT NULL,
    application_version     NVARCHAR(30)        NULL,
    service_name            NVARCHAR(100)       NULL,
    service_version         NVARCHAR(30)        NULL,
    component               NVARCHAR(100)       NULL,       -- Module / class within service
    environment             NVARCHAR(20)        NULL,       -- PROD, UAT, DEV
    host_name               NVARCHAR(253)       NULL,
    container_id            NVARCHAR(128)       NULL,
    pod_name                NVARCHAR(128)       NULL,
    namespace               NVARCHAR(128)       NULL,       -- Kubernetes namespace

    -- Error classification
    severity_level          NVARCHAR(10)        NOT NULL,   -- CRITICAL, ERROR, WARN, INFO
    error_type              NVARCHAR(100)       NULL,       -- NullPointerException, TimeoutException
    error_category          NVARCHAR(50)        NULL,       -- INFRASTRUCTURE, BUSINESS_LOGIC, SECURITY
    error_code              NVARCHAR(50)        NULL,
    error_message           NVARCHAR(4000)      NULL,
    exception_class         NVARCHAR(500)       NULL,
    stack_trace             NVARCHAR(MAX)       NULL,
    inner_exception         NVARCHAR(4000)      NULL,

    -- Request / user context
    operation_name          NVARCHAR(200)       NULL,
    user_id                 NVARCHAR(64)        NULL,
    customer_id             NVARCHAR(32)        NULL,
    account_id              NVARCHAR(32)        NULL,
    request_id              NVARCHAR(64)        NULL,
    session_id              NVARCHAR(64)        NULL,
    thread_name             NVARCHAR(200)       NULL,
    method_name             NVARCHAR(200)       NULL,

    -- Impact indicators
    is_user_facing          BIT                 NULL,
    affected_transaction_id NVARCHAR(64)        NULL,
    retry_count             INT                 NULL,
    is_resolved             BIT                 NULL,
    resolved_at             DATETIME2(6)        NULL,

    -- AI / ML hint (pre-computed by upstream pipeline if available)
    raw_root_cause_hint     NVARCHAR(1000)      NULL,

    -- Custom dimensions (JSON blob for extensible properties)
    custom_dimensions       NVARCHAR(MAX)       NULL,

    -- Timestamps
    event_timestamp         DATETIME2(6)        NOT NULL,

    -- CDC / pipeline metadata
    source_system           NVARCHAR(50)        NULL,
    log_stream              NVARCHAR(50)        NULL,
    batch_id                NVARCHAR(64)        NULL,
    raw_payload             NVARCHAR(MAX)       NULL,

    -- Partition column
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE  = BronzeDataSource,
    LOCATION     = '/application_error_logs/',
    FILE_FORMAT  = DeltaFormat
);
GO


-- -----------------------------------------------------------------------------
-- 4.5  brz_audit_logs
--      Source  : Core banking audit trail / HSM audit / data-access logs
--      Format  : Delta Lake
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.brz_audit_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_audit_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_audit_logs
(
    -- Event identifiers
    audit_event_id          NVARCHAR(64)        NOT NULL,
    correlation_id          NVARCHAR(64)        NULL,
    session_id              NVARCHAR(64)        NULL,

    -- Actor (who performed the action)
    actor_user_id           NVARCHAR(64)        NOT NULL,
    actor_type              NVARCHAR(50)        NULL,       -- HUMAN, SERVICE_ACCOUNT, BATCH_JOB
    actor_role              NVARCHAR(100)       NULL,
    actor_department        NVARCHAR(100)       NULL,
    actor_ip_address        NVARCHAR(45)        NULL,
    actor_device_id         NVARCHAR(64)        NULL,
    actor_user_agent        NVARCHAR(500)       NULL,
    impersonator_id         NVARCHAR(128)       NULL,       -- Delegate / sudo actor

    -- Action
    action_type             NVARCHAR(50)        NOT NULL,   -- READ, CREATE, UPDATE, DELETE, EXPORT, APPROVE
    action_category         NVARCHAR(50)        NULL,       -- DATA_ACCESS, ADMIN, CONFIG_CHANGE, AUTH
    action_description      NVARCHAR(500)       NULL,
    action_result           NVARCHAR(20)        NOT NULL,   -- SUCCESS, FAILURE, DENIED, PARTIAL

    -- Resource (what was accessed / modified)
    resource_type           NVARCHAR(100)       NULL,       -- ACCOUNT, TRANSACTION, CUSTOMER_PROFILE
    resource_id             NVARCHAR(128)       NULL,
    resource_owner_id       NVARCHAR(64)        NULL,
    resource_classification NVARCHAR(50)        NULL,       -- PII, PCI, CONFIDENTIAL, PUBLIC

    -- Change capture (for mutation events)
    old_value               NVARCHAR(MAX)       NULL,       -- JSON snapshot before change
    new_value               NVARCHAR(MAX)       NULL,       -- JSON snapshot after change
    change_summary          NVARCHAR(1000)      NULL,
    changed_fields          NVARCHAR(2000)      NULL,       -- Comma-separated field names

    -- Regulatory / compliance tags
    regulatory_flag         NVARCHAR(50)        NULL,       -- GDPR, PCI-DSS, SOX, PSD2, Basel III
    data_classification     NVARCHAR(30)        NULL,       -- PUBLIC, INTERNAL, CONFIDENTIAL, RESTRICTED
    is_pii_accessed         BIT                 NULL,
    is_pci_accessed         BIT                 NULL,

    -- Application context
    application_name        NVARCHAR(100)       NULL,
    service_name            NVARCHAR(100)       NULL,
    service_version         NVARCHAR(30)        NULL,
    environment             NVARCHAR(20)        NULL,

    -- Timestamps
    event_timestamp         DATETIME2(6)        NOT NULL,

    -- CDC / pipeline metadata
    source_system           NVARCHAR(50)        NULL,
    batch_id                NVARCHAR(64)        NULL,
    raw_payload             NVARCHAR(MAX)       NULL,

    -- Partition column
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE  = BronzeDataSource,
    LOCATION     = '/audit_logs/',
    FILE_FORMAT  = DeltaFormat
);
GO


-- -----------------------------------------------------------------------------
-- 4.6  brz_fraud_alert_logs
--      Source  : Fraud detection engine (real-time + batch scoring)
--      Format  : Delta Lake
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.brz_fraud_alert_logs', 'U') IS NOT NULL
    DROP EXTERNAL TABLE dbo.brz_fraud_alert_logs;
GO

CREATE EXTERNAL TABLE dbo.brz_fraud_alert_logs
(
    -- Alert identifiers
    alert_id                NVARCHAR(64)        NOT NULL,
    case_id                 NVARCHAR(64)        NULL,       -- Linked fraud investigation case
    correlation_id          NVARCHAR(64)        NULL,
    rule_id                 NVARCHAR(64)        NULL,
    model_id                NVARCHAR(64)        NULL,       -- ML model that triggered the alert

    -- Linked entities
    transaction_id          NVARCHAR(64)        NULL,
    account_id              NVARCHAR(32)        NULL,
    customer_id             NVARCHAR(32)        NULL,
    auth_event_id           NVARCHAR(64)        NULL,

    -- Alert classification
    alert_type              NVARCHAR(50)        NOT NULL,   -- CARD_NOT_PRESENT, ATO, MULE, AML
    alert_category          NVARCHAR(50)        NULL,       -- FRAUD, AML, SANCTIONS, CYBER
    alert_severity          NVARCHAR(10)        NOT NULL,   -- LOW, MEDIUM, HIGH, CRITICAL
    detection_method        NVARCHAR(50)        NULL,       -- RULE_BASED, ML_MODEL, HYBRID
    alert_status            NVARCHAR(20)        NOT NULL,   -- OPEN, REVIEWING, ESCALATED, CLOSED

    -- Scoring & model outputs
    fraud_score             FLOAT               NULL,       -- 0.0 – 1.0
    anomaly_score           FLOAT               NULL,
    confidence              FLOAT               NULL,
    fraud_model_version     NVARCHAR(30)        NULL,
    triggered_rules         NVARCHAR(MAX)       NULL,       -- JSON array of rule IDs / names
    contributing_features   NVARCHAR(MAX)       NULL,       -- JSON feature-importance map

    -- Investigation & resolution
    analyst_id              NVARCHAR(64)        NULL,
    investigation_notes     NVARCHAR(4000)      NULL,
    resolution              NVARCHAR(50)        NULL,       -- CONFIRMED_FRAUD, FALSE_POSITIVE, INCONCLUSIVE
    action_taken            NVARCHAR(100)       NULL,       -- BLOCK_TXN, FREEZE_ACCOUNT, NOTIFY_CUSTOMER
    action_timestamp        DATETIME2(6)        NULL,
    resolved_at             DATETIME2(6)        NULL,

    -- Financial impact
    at_risk_amount          DECIMAL(20, 4)      NULL,
    currency_code           CHAR(3)             NULL,
    recovered_amount        DECIMAL(20, 4)      NULL,

    -- Timestamps
    alert_raised_at         DATETIME2(6)        NOT NULL,
    alert_updated_at        DATETIME2(6)        NULL,

    -- CDC / pipeline metadata
    source_system           NVARCHAR(50)        NULL,
    batch_id                NVARCHAR(64)        NULL,
    raw_payload             NVARCHAR(MAX)       NULL,

    -- Partition column
    ingestion_date          DATE                NOT NULL
)
WITH (
    DATA_SOURCE  = BronzeDataSource,
    LOCATION     = '/fraud_alert_logs/',
    FILE_FORMAT  = DeltaFormat
);
GO

-- =============================================================================
-- End of 001_bronze_tables.sql
-- =============================================================================
