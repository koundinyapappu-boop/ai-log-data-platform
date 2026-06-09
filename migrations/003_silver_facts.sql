-- =============================================================================
-- FILE    : 003_silver_facts.sql
-- LAYER   : Silver (Cleansed & Conformed)
-- ENGINE  : Azure Synapse Analytics – Dedicated SQL Pool
-- PURPOSE : Fact / normalised table DDLs for the Silver layer.
--           These tables store cleansed, deduplicated event records joined
--           to Silver dimension surrogate keys.  They are the primary source
--           for Gold layer aggregations and ML feature engineering.
-- NOTES   :
--   • All tables use CLUSTERED COLUMNSTORE INDEX (CCI).
--   • DISTRIBUTION = HASH on the most selective FK or natural business key
--     to minimise data movement in analytical joins.
--   • Partition by event_date (DATE) for partition elimination on time-range
--     queries; match partition granularity to your retention SLA.
--   • Surrogate key FKs reference silver dimension tables but are NOT
--     enforced as foreign-key constraints (Dedicated Pool limitation);
--     referential integrity is maintained by the pipeline.
--   • Run this script in the Dedicated Pool database context.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Section 0 : Schema guard
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO


-- =============================================================================
-- Section 1 : slv_transaction_logs
--   Grain    : One row per transaction event (initiated or status-change)
--   Dist key : account_sk  (high cardinality, co-located with account dim)
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('silver.slv_transaction_logs', 'U') IS NOT NULL
    DROP TABLE silver.slv_transaction_logs;
GO

CREATE TABLE silver.slv_transaction_logs
(
    -- Surrogate primary key
    txn_log_sk                  BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural / source key
    transaction_id              NVARCHAR(64)    NOT NULL,
    correlation_id              NVARCHAR(64)    NULL,
    session_id                  NVARCHAR(64)    NULL,

    -- Dimension surrogate keys (FK references – not enforced)
    account_sk                  BIGINT          NOT NULL,   -- slv_dim_account
    customer_sk                 BIGINT          NULL,       -- slv_dim_customer
    channel_sk                  INT             NULL,       -- slv_dim_channel
    transaction_type_sk         INT             NULL,       -- slv_dim_transaction_type
    service_sk                  INT             NULL,       -- slv_dim_service
    event_date_sk               INT             NOT NULL,   -- slv_dim_date (YYYYMMDD)

    -- Natural keys (preserved for lineage and Bronze join-back)
    account_id                  NVARCHAR(32)    NOT NULL,
    customer_id                 NVARCHAR(32)    NULL,
    debit_account_id            NVARCHAR(32)    NULL,
    credit_account_id           NVARCHAR(32)    NULL,
    transaction_type_code       NVARCHAR(50)    NOT NULL,
    channel_code                NVARCHAR(30)    NULL,

    -- Transaction financials
    currency_code               CHAR(3)         NOT NULL,
    amount                      DECIMAL(20, 4)  NOT NULL,
    fee_amount                  DECIMAL(20, 4)  NULL,
    base_currency_amount        DECIMAL(20, 4)  NULL,
    exchange_rate               DECIMAL(18, 8)  NULL,

    -- Status
    transaction_status          NVARCHAR(20)    NOT NULL,
    failure_reason              NVARCHAR(500)   NULL,
    response_code               NVARCHAR(10)    NULL,
    is_failed                   BIT             NOT NULL    DEFAULT 0,
    is_reversed                 BIT             NOT NULL    DEFAULT 0,

    -- Performance
    processing_duration_ms      INT             NULL,

    -- Network / device context
    ip_address                  NVARCHAR(45)    NULL,
    device_id                   NVARCHAR(64)    NULL,
    geo_country                 CHAR(2)         NULL,
    geo_city                    NVARCHAR(100)   NULL,

    -- AI / ML scoring (standardised from Bronze raw values)
    risk_score                  FLOAT           NULL,       -- 0.0 – 1.0
    risk_label                  NVARCHAR(20)    NULL,       -- LOW, MEDIUM, HIGH, CRITICAL
    anomaly_flag                BIT             NULL,

    -- Timestamps (UTC)
    initiated_at                DATETIME2(6)    NOT NULL,
    completed_at                DATETIME2(6)    NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    source_system               NVARCHAR(50)    NULL,
    silver_loaded_at            DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    is_current                  BIT             NOT NULL    DEFAULT 1,
    record_hash                 BINARY(32)      NULL        -- SHA2_256 dedup hash
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(account_sk),
    PARTITION    (
        event_date RANGE RIGHT FOR VALUES (
            '2023-01-01','2023-04-01','2023-07-01','2023-10-01',
            '2024-01-01','2024-04-01','2024-07-01','2024-10-01',
            '2025-01-01','2025-04-01','2025-07-01','2025-10-01',
            '2026-01-01','2026-04-01','2026-07-01','2026-10-01'
        )
    )
);
GO


-- =============================================================================
-- Section 2 : slv_auth_logs
--   Grain    : One row per authentication / authorisation event
--   Dist key : account_sk
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('silver.slv_auth_logs', 'U') IS NOT NULL
    DROP TABLE silver.slv_auth_logs;
GO

CREATE TABLE silver.slv_auth_logs
(
    -- Surrogate primary key
    auth_log_sk                 BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    auth_event_id               NVARCHAR(64)    NOT NULL,
    correlation_id              NVARCHAR(64)    NULL,
    session_id                  NVARCHAR(64)    NULL,

    -- Dimension SKs
    account_sk                  BIGINT          NULL,       -- slv_dim_account (nullable – service auth)
    customer_sk                 BIGINT          NULL,       -- slv_dim_customer
    channel_sk                  INT             NULL,       -- slv_dim_channel
    auth_event_type_sk          INT             NULL,       -- slv_dim_auth_event_type
    event_date_sk               INT             NOT NULL,   -- slv_dim_date

    -- Natural keys (preserved)
    user_id                     NVARCHAR(64)    NULL,
    account_id                  NVARCHAR(32)    NULL,
    customer_id                 NVARCHAR(32)    NULL,
    service_principal_id        NVARCHAR(64)    NULL,
    event_type_code             NVARCHAR(50)    NOT NULL,
    channel_code                NVARCHAR(30)    NULL,

    -- Auth attributes
    auth_method                 NVARCHAR(30)    NULL,
    mfa_method                  NVARCHAR(30)    NULL,
    auth_result                 NVARCHAR(20)    NOT NULL,   -- SUCCESS, FAILURE, LOCKED, EXPIRED
    failure_reason              NVARCHAR(500)   NULL,
    failure_code                NVARCHAR(20)    NULL,
    attempt_count               INT             NULL,
    is_success                  BIT             NOT NULL    DEFAULT 0,
    is_mfa_used                 BIT             NOT NULL    DEFAULT 0,

    -- Client context
    ip_address                  NVARCHAR(45)    NULL,
    device_id                   NVARCHAR(64)    NULL,
    device_type                 NVARCHAR(30)    NULL,
    geo_country                 CHAR(2)         NULL,
    geo_city                    NVARCHAR(100)   NULL,
    is_vpn                      BIT             NULL,
    is_tor_exit_node            BIT             NULL,
    is_impossible_travel        BIT             NULL,
    previous_geo_country        CHAR(2)         NULL,

    -- Token / session details
    token_issued_at             DATETIME2(6)    NULL,
    token_expires_at            DATETIME2(6)    NULL,
    session_started_at          DATETIME2(6)    NULL,
    session_ended_at            DATETIME2(6)    NULL,

    -- Risk signals
    risk_score                  FLOAT           NULL,
    risk_label                  NVARCHAR(20)    NULL,

    -- Timestamps (UTC)
    event_timestamp             DATETIME2(6)    NOT NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    source_system               NVARCHAR(50)    NULL,
    silver_loaded_at            DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    record_hash                 BINARY(32)      NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(account_sk),
    PARTITION    (
        event_date RANGE RIGHT FOR VALUES (
            '2023-01-01','2023-04-01','2023-07-01','2023-10-01',
            '2024-01-01','2024-04-01','2024-07-01','2024-10-01',
            '2025-01-01','2025-04-01','2025-07-01','2025-10-01',
            '2026-01-01','2026-04-01','2026-07-01','2026-10-01'
        )
    )
);
GO


-- =============================================================================
-- Section 3 : slv_api_request_logs
--   Grain    : One row per HTTP request through the API gateway
--   Dist key : request_id (high cardinality, few repeated values)
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('silver.slv_api_request_logs', 'U') IS NOT NULL
    DROP TABLE silver.slv_api_request_logs;
GO

CREATE TABLE silver.slv_api_request_logs
(
    -- Surrogate primary key
    api_log_sk                  BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    request_id                  NVARCHAR(64)    NOT NULL,
    trace_id                    NVARCHAR(128)   NULL,
    span_id                     NVARCHAR(32)    NULL,
    correlation_id              NVARCHAR(64)    NULL,

    -- Dimension SKs
    service_sk                  INT             NULL,       -- slv_dim_service (backend service)
    channel_sk                  INT             NULL,       -- slv_dim_channel
    event_date_sk               INT             NOT NULL,   -- slv_dim_date

    -- Natural keys (preserved)
    api_name                    NVARCHAR(100)   NULL,
    api_version                 NVARCHAR(20)    NULL,
    operation_id                NVARCHAR(100)   NULL,
    http_method                 NVARCHAR(10)    NOT NULL,
    request_path                NVARCHAR(2048)  NOT NULL,
    consumer_id                 NVARCHAR(64)    NULL,
    user_id                     NVARCHAR(64)    NULL,
    customer_id                 NVARCHAR(32)    NULL,

    -- HTTP response attributes
    http_status_code            SMALLINT        NOT NULL,
    http_status_class           NVARCHAR(5)     NULL,       -- 2xx, 4xx, 5xx
    is_error                    BIT             NOT NULL    DEFAULT 0,
    is_client_error             BIT             NOT NULL    DEFAULT 0,   -- 4xx
    is_server_error             BIT             NOT NULL    DEFAULT 0,   -- 5xx
    error_code                  NVARCHAR(50)    NULL,
    error_message               NVARCHAR(1000)  NULL,

    -- Performance metrics
    total_latency_ms            INT             NULL,
    gateway_latency_ms          INT             NULL,
    backend_latency_ms          INT             NULL,
    request_size_bytes          INT             NULL,
    response_size_bytes         INT             NULL,
    cache_hit                   BIT             NULL,

    -- Client context
    ip_address                  NVARCHAR(45)    NULL,
    geo_country                 CHAR(2)         NULL,
    tls_version                 NVARCHAR(10)    NULL,
    auth_scheme                 NVARCHAR(30)    NULL,

    -- Infrastructure
    gateway_node_id             NVARCHAR(64)    NULL,
    region                      NVARCHAR(30)    NULL,

    -- Timestamps (UTC)
    request_timestamp           DATETIME2(6)    NOT NULL,
    response_timestamp          DATETIME2(6)    NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    source_system               NVARCHAR(50)    NULL,
    silver_loaded_at            DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    record_hash                 BINARY(32)      NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(request_id),
    PARTITION    (
        event_date RANGE RIGHT FOR VALUES (
            '2023-01-01','2023-04-01','2023-07-01','2023-10-01',
            '2024-01-01','2024-04-01','2024-07-01','2024-10-01',
            '2025-01-01','2025-04-01','2025-07-01','2025-10-01',
            '2026-01-01','2026-04-01','2026-07-01','2026-10-01'
        )
    )
);
GO


-- =============================================================================
-- Section 4 : slv_application_error_logs
--   Grain    : One row per application exception / error event
--   Dist key : error_event_id (random-ish for even spread across nodes)
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('silver.slv_application_error_logs', 'U') IS NOT NULL
    DROP TABLE silver.slv_application_error_logs;
GO

CREATE TABLE silver.slv_application_error_logs
(
    -- Surrogate primary key
    error_log_sk                BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    error_event_id              NVARCHAR(64)    NOT NULL,
    trace_id                    NVARCHAR(128)   NULL,
    span_id                     NVARCHAR(32)    NULL,
    correlation_id              NVARCHAR(64)    NULL,

    -- Dimension SKs
    service_sk                  INT             NULL,       -- slv_dim_service
    error_type_sk               INT             NULL,       -- slv_dim_error_type
    event_date_sk               INT             NOT NULL,   -- slv_dim_date

    -- Natural keys (preserved)
    service_name                NVARCHAR(100)   NULL,
    application_name            NVARCHAR(100)   NOT NULL,
    error_type_code             NVARCHAR(100)   NULL,
    error_category              NVARCHAR(50)    NULL,

    -- Error details
    severity_level              NVARCHAR(10)    NOT NULL,
    error_code                  NVARCHAR(50)    NULL,
    error_message               NVARCHAR(4000)  NULL,
    exception_class             NVARCHAR(500)   NULL,
    component                   NVARCHAR(100)   NULL,
    operation_name              NVARCHAR(200)   NULL,
    host_name                   NVARCHAR(253)   NULL,
    pod_name                    NVARCHAR(128)   NULL,
    environment                 NVARCHAR(20)    NULL,

    -- Request / user context
    user_id                     NVARCHAR(64)    NULL,
    customer_id                 NVARCHAR(32)    NULL,
    account_id                  NVARCHAR(32)    NULL,
    request_id                  NVARCHAR(64)    NULL,
    session_id                  NVARCHAR(64)    NULL,
    affected_transaction_id     NVARCHAR(64)    NULL,

    -- Impact flags
    is_user_facing              BIT             NULL,
    is_critical                 BIT             NOT NULL    DEFAULT 0,
    retry_count                 INT             NULL,
    is_resolved                 BIT             NULL,
    resolved_at                 DATETIME2(6)    NULL,
    mean_time_to_resolve_mins   INT             NULL,

    -- AI / ML classification (populated in Silver by batch inference pipeline)
    ai_root_cause_hint          NVARCHAR(1000)  NULL,
    ai_error_cluster_id         NVARCHAR(64)    NULL,

    -- Timestamps (UTC)
    error_timestamp             DATETIME2(6)    NOT NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    source_system               NVARCHAR(50)    NULL,
    silver_loaded_at            DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    record_hash                 BINARY(32)      NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(error_event_id),
    PARTITION    (
        event_date RANGE RIGHT FOR VALUES (
            '2023-01-01','2023-04-01','2023-07-01','2023-10-01',
            '2024-01-01','2024-04-01','2024-07-01','2024-10-01',
            '2025-01-01','2025-04-01','2025-07-01','2025-10-01',
            '2026-01-01','2026-04-01','2026-07-01','2026-10-01'
        )
    )
);
GO


-- =============================================================================
-- Section 5 : slv_audit_logs
--   Grain    : One row per compliance / data-access audit event
--   Dist key : audit_event_id (high cardinality, co-locates well)
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('silver.slv_audit_logs', 'U') IS NOT NULL
    DROP TABLE silver.slv_audit_logs;
GO

CREATE TABLE silver.slv_audit_logs
(
    -- Surrogate primary key
    audit_log_sk                BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    audit_event_id              NVARCHAR(64)    NOT NULL,
    correlation_id              NVARCHAR(64)    NULL,
    session_id                  NVARCHAR(64)    NULL,

    -- Dimension SKs
    service_sk                  INT             NULL,       -- slv_dim_service
    event_date_sk               INT             NOT NULL,   -- slv_dim_date

    -- Actor attributes
    actor_user_id               NVARCHAR(64)    NOT NULL,
    actor_type                  NVARCHAR(50)    NULL,
    actor_role                  NVARCHAR(100)   NULL,
    actor_department            NVARCHAR(100)   NULL,
    actor_ip_address            NVARCHAR(45)    NULL,
    impersonator_id             NVARCHAR(128)   NULL,

    -- Action attributes
    action_type                 NVARCHAR(50)    NOT NULL,
    action_category             NVARCHAR(50)    NULL,
    action_result               NVARCHAR(20)    NOT NULL,
    is_success                  BIT             NOT NULL    DEFAULT 0,
    is_pii_accessed             BIT             NULL,
    is_pci_accessed             BIT             NULL,

    -- Resource attributes
    resource_type               NVARCHAR(100)   NULL,
    resource_id                 NVARCHAR(128)   NULL,
    resource_owner_id           NVARCHAR(64)    NULL,
    resource_classification     NVARCHAR(50)    NULL,

    -- Regulatory tagging
    regulatory_flag             NVARCHAR(50)    NULL,
    data_classification         NVARCHAR(30)    NULL,
    regulatory_scope            NVARCHAR(200)   NULL,

    -- Change summary (heavy columns stored in Bronze; only metadata here)
    changed_fields              NVARCHAR(2000)  NULL,
    change_summary              NVARCHAR(1000)  NULL,

    -- Application context
    application_name            NVARCHAR(100)   NULL,
    service_name                NVARCHAR(100)   NULL,
    environment                 NVARCHAR(20)    NULL,

    -- Timestamps (UTC)
    event_timestamp             DATETIME2(6)    NOT NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    source_system               NVARCHAR(50)    NULL,
    silver_loaded_at            DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    record_hash                 BINARY(32)      NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(audit_event_id),
    PARTITION    (
        event_date RANGE RIGHT FOR VALUES (
            '2023-01-01','2023-04-01','2023-07-01','2023-10-01',
            '2024-01-01','2024-04-01','2024-07-01','2024-10-01',
            '2025-01-01','2025-04-01','2025-07-01','2025-10-01',
            '2026-01-01','2026-04-01','2026-07-01','2026-10-01'
        )
    )
);
GO


-- =============================================================================
-- Section 6 : slv_fraud_alert_logs
--   Grain    : One row per fraud alert event (NEW / status transition)
--   Dist key : account_sk  (enables efficient join to account dim and facts)
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('silver.slv_fraud_alert_logs', 'U') IS NOT NULL
    DROP TABLE silver.slv_fraud_alert_logs;
GO

CREATE TABLE silver.slv_fraud_alert_logs
(
    -- Surrogate primary key
    fraud_alert_log_sk          BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    alert_id                    NVARCHAR(64)    NOT NULL,
    case_id                     NVARCHAR(64)    NULL,
    correlation_id              NVARCHAR(64)    NULL,

    -- Dimension SKs
    account_sk                  BIGINT          NULL,       -- slv_dim_account
    customer_sk                 BIGINT          NULL,       -- slv_dim_customer
    event_date_sk               INT             NOT NULL,   -- slv_dim_date

    -- Natural keys (preserved)
    account_id                  NVARCHAR(32)    NULL,
    customer_id                 NVARCHAR(32)    NULL,
    transaction_id              NVARCHAR(64)    NULL,
    auth_event_id               NVARCHAR(64)    NULL,
    rule_id                     NVARCHAR(64)    NULL,
    model_id                    NVARCHAR(64)    NULL,

    -- Alert classification
    alert_type                  NVARCHAR(50)    NOT NULL,
    alert_category              NVARCHAR(50)    NULL,
    alert_severity              NVARCHAR(10)    NOT NULL,
    detection_method            NVARCHAR(50)    NULL,
    alert_status                NVARCHAR(20)    NOT NULL,

    -- Scores & model outputs
    fraud_score                 FLOAT           NULL,
    anomaly_score               FLOAT           NULL,
    confidence                  FLOAT           NULL,
    fraud_model_version         NVARCHAR(30)    NULL,

    -- Investigation result
    resolution                  NVARCHAR(50)    NULL,
    action_taken                NVARCHAR(100)   NULL,
    reviewed_by                 NVARCHAR(128)   NULL,
    is_confirmed_fraud          BIT             NULL,
    is_false_positive           BIT             NULL,

    -- Financial impact
    at_risk_amount              DECIMAL(20, 4)  NULL,
    currency_code               CHAR(3)         NULL,
    recovered_amount            DECIMAL(20, 4)  NULL,

    -- Timestamps (UTC)
    alert_raised_at             DATETIME2(6)    NOT NULL,
    alert_resolved_at           DATETIME2(6)    NULL,
    action_timestamp            DATETIME2(6)    NULL,
    event_date                  DATE            NOT NULL,   -- Partition column (= DATE(alert_raised_at))

    -- Pipeline audit
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    source_system               NVARCHAR(50)    NULL,
    silver_loaded_at            DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    record_hash                 BINARY(32)      NULL
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(account_sk),
    PARTITION    (
        event_date RANGE RIGHT FOR VALUES (
            '2023-01-01','2023-04-01','2023-07-01','2023-10-01',
            '2024-01-01','2024-04-01','2024-07-01','2024-10-01',
            '2025-01-01','2025-04-01','2025-07-01','2025-10-01',
            '2026-01-01','2026-04-01','2026-07-01','2026-10-01'
        )
    )
);
GO

-- =============================================================================
-- End of 003_silver_facts.sql
-- =============================================================================
