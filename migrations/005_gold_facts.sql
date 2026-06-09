-- =============================================================================
-- FILE    : 005_gold_facts.sql
-- LAYER   : Gold (Conformed & Presentation-Ready)
-- ENGINE  : Azure Synapse Analytics – Dedicated SQL Pool
-- PURPOSE : Gold fact, aggregate, and AI-enriched table DDLs.
--           These tables are the primary targets for BI dashboards,
--           operational reporting, anomaly detection outputs, and
--           ML feature stores.
-- NOTES   :
--   • All event-grain tables use CLUSTERED COLUMNSTORE INDEX (CCI)
--     and are HASH distributed on the most selective key.
--   • Aggregate tables use CLUSTERED COLUMNSTORE INDEX and REPLICATE
--     distribution (small result sets after pre-aggregation).
--   • All event-grain tables are partitioned by event_date (quarterly
--     boundaries) to enable efficient range-scan pruning.
--   • AI scoring columns (is_anomaly, anomaly_score, ai_risk_label, etc.)
--     are populated by a downstream Azure ML / OpenAI batch scoring
--     pipeline that writes back into this layer.
--   • gld_log_embeddings stores vector embeddings as JSON in NVARCHAR(MAX)
--     (native vector storage pending Synapse GA; migrate to VECTOR type
--     when available in Dedicated Pool).
--   • Run this script in the Dedicated Pool database context.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Section 0 : Schema guard
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO


-- =============================================================================
-- Section 1 : gld_fact_transaction_logs
--   Grain    : One row per completed / failed transaction event
--   Dist key : account_sk (co-located with gld_dim_account)
--   Partition: event_date (quarterly)
--   AI cols  : is_anomaly, anomaly_score, ai_risk_label, ai_fraud_indicator
-- =============================================================================
IF OBJECT_ID('gold.gld_fact_transaction_logs', 'U') IS NOT NULL
    DROP TABLE gold.gld_fact_transaction_logs;
GO

CREATE TABLE gold.gld_fact_transaction_logs
(
    -- Surrogate primary key
    txn_fact_sk                 BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key (from source)
    transaction_id              NVARCHAR(64)    NOT NULL,
    correlation_id              NVARCHAR(64)    NULL,

    -- Dimension surrogate keys (FK references – not enforced)
    account_sk                  BIGINT          NOT NULL,   -- gld_dim_account
    customer_sk                 BIGINT          NULL,       -- gld_dim_customer
    channel_sk                  INT             NULL,       -- gld_dim_channel
    transaction_type_sk         INT             NULL,       -- gld_dim_transaction_type
    service_sk                  INT             NULL,       -- gld_dim_service
    event_date_sk               INT             NOT NULL,   -- gld_dim_date

    -- Degenerate dimensions (natural keys kept for drill-through)
    account_id                  NVARCHAR(32)    NOT NULL,
    customer_id                 NVARCHAR(32)    NULL,
    transaction_type_code       NVARCHAR(50)    NOT NULL,
    channel_code                NVARCHAR(30)    NULL,

    -- Transaction measures
    currency_code               CHAR(3)         NOT NULL,
    amount                      DECIMAL(20, 4)  NOT NULL,
    fee_amount                  DECIMAL(20, 4)  NULL,
    base_currency_amount        DECIMAL(20, 4)  NULL,       -- FX-normalised (e.g. USD)
    exchange_rate               DECIMAL(18, 8)  NULL,

    -- Status flags (BIT for efficient predicate evaluation)
    transaction_status          NVARCHAR(20)    NOT NULL,
    is_completed                BIT             NOT NULL    DEFAULT 0,
    is_failed                   BIT             NOT NULL    DEFAULT 0,
    is_reversed                 BIT             NOT NULL    DEFAULT 0,
    failure_reason              NVARCHAR(500)   NULL,
    response_code               NVARCHAR(10)    NULL,

    -- Performance measure
    processing_duration_ms      INT             NULL,

    -- Geographic context
    geo_country                 CHAR(2)         NULL,
    geo_city                    NVARCHAR(100)   NULL,

    -- -------------------------------------------------------------------------
    -- AI / ML Scoring columns
    -- Populated by Azure ML batch scoring pipeline (writes to Gold layer).
    -- -------------------------------------------------------------------------
    is_anomaly                  BIT             NULL,       -- 1 = anomaly detected by ML model
    anomaly_score               FLOAT           NULL,       -- Continuous anomaly score 0.0–1.0
    ai_risk_label               NVARCHAR(20)    NULL,       -- LOW / MEDIUM / HIGH / CRITICAL
    ai_fraud_indicator          BIT             NULL,       -- Fraud model binary output
    ai_fraud_score              FLOAT           NULL,       -- Fraud model probability 0.0–1.0
    ai_model_id                 NVARCHAR(64)    NULL,       -- Model version that produced scores
    ai_scored_at                DATETIME2(0)    NULL,       -- Timestamp of scoring run

    -- Timestamps (UTC)
    initiated_at                DATETIME2(6)    NOT NULL,
    completed_at                DATETIME2(6)    NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    silver_txn_log_sk           BIGINT          NULL,       -- Lineage back to Silver
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
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
-- Section 2 : gld_fact_auth_events
--   Grain    : One row per authentication / authorisation event
--   Dist key : account_sk
--   Partition: event_date
--   AI cols  : is_anomaly, anomaly_score, ai_account_takeover_score
-- =============================================================================
IF OBJECT_ID('gold.gld_fact_auth_events', 'U') IS NOT NULL
    DROP TABLE gold.gld_fact_auth_events;
GO

CREATE TABLE gold.gld_fact_auth_events
(
    -- Surrogate primary key
    auth_fact_sk                BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    auth_event_id               NVARCHAR(64)    NOT NULL,
    correlation_id              NVARCHAR(64)    NULL,
    session_id                  NVARCHAR(64)    NULL,

    -- Dimension surrogate keys
    account_sk                  BIGINT          NULL,       -- gld_dim_account
    customer_sk                 BIGINT          NULL,       -- gld_dim_customer
    channel_sk                  INT             NULL,       -- gld_dim_channel
    event_date_sk               INT             NOT NULL,   -- gld_dim_date

    -- Degenerate dimensions
    user_id                     NVARCHAR(64)    NULL,
    account_id                  NVARCHAR(32)    NULL,
    customer_id                 NVARCHAR(32)    NULL,
    event_type_code             NVARCHAR(50)    NOT NULL,
    channel_code                NVARCHAR(30)    NULL,

    -- Auth attributes
    auth_method                 NVARCHAR(30)    NULL,
    mfa_method                  NVARCHAR(30)    NULL,
    auth_result                 NVARCHAR(20)    NOT NULL,
    is_success                  BIT             NOT NULL    DEFAULT 0,
    is_mfa_used                 BIT             NOT NULL    DEFAULT 0,
    is_step_up                  BIT             NOT NULL    DEFAULT 0,
    attempt_count               INT             NULL,
    failure_code                NVARCHAR(20)    NULL,

    -- Device / network context
    ip_address                  NVARCHAR(45)    NULL,
    device_id                   NVARCHAR(64)    NULL,
    device_type                 NVARCHAR(30)    NULL,
    geo_country                 CHAR(2)         NULL,
    geo_city                    NVARCHAR(100)   NULL,
    is_vpn                      BIT             NULL,
    is_tor_exit_node            BIT             NULL,

    -- Session measures
    session_duration_seconds    INT             NULL,       -- Derived from started/ended timestamps

    -- -------------------------------------------------------------------------
    -- AI / ML Scoring columns
    -- -------------------------------------------------------------------------
    is_anomaly                  BIT             NULL,       -- Behavioural anomaly flag
    anomaly_score               FLOAT           NULL,       -- 0.0–1.0
    ai_account_takeover_score   FLOAT           NULL,       -- Probability of ATO 0.0–1.0
    ai_impossible_travel_flag   BIT             NULL,       -- Model-enhanced travel check
    ai_risk_label               NVARCHAR(20)    NULL,
    ai_model_id                 NVARCHAR(64)    NULL,
    ai_scored_at                DATETIME2(0)    NULL,

    -- Timestamps (UTC)
    event_timestamp             DATETIME2(6)    NOT NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    silver_auth_log_sk          BIGINT          NULL,
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
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
-- Section 3 : gld_fact_application_errors
--   Grain    : One row per application error event
--   Dist key : service_sk (co-locate with service dim for error trend reports)
--   Partition: event_date
--   AI cols  : ai_root_cause_hint, ai_error_cluster_id, ai_resolution_hint
-- =============================================================================
IF OBJECT_ID('gold.gld_fact_application_errors', 'U') IS NOT NULL
    DROP TABLE gold.gld_fact_application_errors;
GO

CREATE TABLE gold.gld_fact_application_errors
(
    -- Surrogate primary key
    error_fact_sk               BIGINT          NOT NULL    IDENTITY(1,1),

    -- Natural key
    error_event_id              NVARCHAR(64)    NOT NULL,
    trace_id                    NVARCHAR(128)   NULL,
    correlation_id              NVARCHAR(64)    NULL,

    -- Dimension surrogate keys
    service_sk                  INT             NULL,       -- gld_dim_service
    event_date_sk               INT             NOT NULL,   -- gld_dim_date

    -- Degenerate dimensions
    service_name                NVARCHAR(100)   NULL,
    application_name            NVARCHAR(100)   NOT NULL,
    error_type_code             NVARCHAR(100)   NULL,
    error_category              NVARCHAR(50)    NULL,
    severity_level              NVARCHAR(10)    NOT NULL,
    environment                 NVARCHAR(20)    NULL,
    component                   NVARCHAR(100)   NULL,
    operation_name              NVARCHAR(200)   NULL,
    host_name                   NVARCHAR(253)   NULL,
    pod_name                    NVARCHAR(128)   NULL,

    -- User / request context
    user_id                     NVARCHAR(64)    NULL,
    customer_id                 NVARCHAR(32)    NULL,
    account_id                  NVARCHAR(32)    NULL,
    request_id                  NVARCHAR(64)    NULL,
    affected_transaction_id     NVARCHAR(64)    NULL,

    -- Impact measures
    is_user_facing              BIT             NULL,
    is_critical                 BIT             NOT NULL    DEFAULT 0,
    retry_count                 INT             NULL,
    is_resolved                 BIT             NULL,
    mean_time_to_resolve_mins   INT             NULL,

    -- Error codes
    error_code                  NVARCHAR(50)    NULL,
    error_message               NVARCHAR(4000)  NULL,

    -- -------------------------------------------------------------------------
    -- AI / ML Scoring columns
    -- -------------------------------------------------------------------------
    ai_root_cause_hint          NVARCHAR(1000)  NULL,       -- LLM-generated root cause summary
    ai_error_cluster_id         NVARCHAR(64)    NULL,       -- Cluster ID from embedding-based grouping
    ai_resolution_hint          NVARCHAR(1000)  NULL,       -- Suggested remediation action
    ai_severity_prediction      NVARCHAR(10)    NULL,       -- Model-predicted escalated severity
    ai_model_id                 NVARCHAR(64)    NULL,
    ai_scored_at                DATETIME2(0)    NULL,

    -- Timestamps (UTC)
    error_timestamp             DATETIME2(6)    NOT NULL,
    resolved_at                 DATETIME2(6)    NULL,
    event_date                  DATE            NOT NULL,   -- Partition column

    -- Pipeline audit
    silver_error_log_sk         BIGINT          NULL,
    ingestion_date              DATE            NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(service_sk),
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
-- Section 4 : gld_agg_txn_hourly
--   Pre-aggregated transaction metrics per account / channel / txn-type
--   at hourly granularity.
--   Grain    : account_sk + channel_sk + transaction_type_sk + event_hour
--   Dist key : account_sk  (dominant join key in downstream queries)
--   No partition – small table; full scan acceptable for dashboards.
-- =============================================================================
IF OBJECT_ID('gold.gld_agg_txn_hourly', 'U') IS NOT NULL
    DROP TABLE gold.gld_agg_txn_hourly;
GO

CREATE TABLE gold.gld_agg_txn_hourly
(
    -- Composite grain key
    account_sk                  BIGINT          NOT NULL,
    channel_sk                  INT             NOT NULL,
    transaction_type_sk         INT             NOT NULL,
    event_date_sk               INT             NOT NULL,
    event_hour                  TINYINT         NOT NULL,   -- 0–23 UTC hour

    -- Natural keys (retained for readability / drill-through)
    account_id                  NVARCHAR(32)    NOT NULL,
    channel_code                NVARCHAR(30)    NULL,
    transaction_type_code       NVARCHAR(50)    NULL,
    currency_code               CHAR(3)         NOT NULL,

    -- Volume measures
    txn_count                   INT             NOT NULL    DEFAULT 0,
    txn_count_completed         INT             NOT NULL    DEFAULT 0,
    txn_count_failed            INT             NOT NULL    DEFAULT 0,
    txn_count_reversed          INT             NOT NULL    DEFAULT 0,

    -- Value measures (base currency)
    total_amount                DECIMAL(20, 4)  NOT NULL    DEFAULT 0,
    total_base_currency_amount  DECIMAL(20, 4)  NULL,
    avg_amount                  DECIMAL(20, 4)  NULL,
    min_amount                  DECIMAL(20, 4)  NULL,
    max_amount                  DECIMAL(20, 4)  NULL,
    total_fee_amount            DECIMAL(20, 4)  NULL,

    -- Performance measures
    avg_processing_duration_ms  FLOAT           NULL,
    max_processing_duration_ms  INT             NULL,

    -- AI / anomaly summary
    anomaly_count               INT             NULL,       -- Transactions flagged is_anomaly = 1
    avg_anomaly_score           FLOAT           NULL,
    max_anomaly_score           FLOAT           NULL,
    high_risk_count             INT             NULL,       -- ai_risk_label IN ('HIGH','CRITICAL')

    -- Failure rate (derived measure)
    failure_rate_pct            DECIMAL(7, 4)   NULL,       -- (failed / total) * 100

    -- Audit
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(account_sk)
);
GO


-- =============================================================================
-- Section 5 : gld_agg_auth_daily
--   Pre-aggregated authentication event metrics per user / channel / method
--   at daily granularity.
--   Grain    : customer_sk + channel_sk + event_type_code + auth_result + event_date
--   Dist key : customer_sk
-- =============================================================================
IF OBJECT_ID('gold.gld_agg_auth_daily', 'U') IS NOT NULL
    DROP TABLE gold.gld_agg_auth_daily;
GO

CREATE TABLE gold.gld_agg_auth_daily
(
    -- Composite grain key
    customer_sk                 BIGINT          NOT NULL,
    channel_sk                  INT             NOT NULL,
    event_date_sk               INT             NOT NULL,
    event_type_code             NVARCHAR(50)    NOT NULL,
    auth_result                 NVARCHAR(20)    NOT NULL,

    -- Natural keys
    customer_id                 NVARCHAR(32)    NOT NULL,
    channel_code                NVARCHAR(30)    NULL,

    -- Event counts
    event_count                 INT             NOT NULL    DEFAULT 0,
    success_count               INT             NOT NULL    DEFAULT 0,
    failure_count               INT             NOT NULL    DEFAULT 0,
    lockout_count               INT             NOT NULL    DEFAULT 0,
    mfa_used_count              INT             NOT NULL    DEFAULT 0,

    -- Risk / anomaly
    anomaly_count               INT             NULL,
    avg_anomaly_score           FLOAT           NULL,
    max_anomaly_score           FLOAT           NULL,
    ato_score_max               FLOAT           NULL,       -- Max account-takeover score in period
    impossible_travel_count     INT             NULL,
    vpn_event_count             INT             NULL,

    -- Failure rate
    failure_rate_pct            DECIMAL(7, 4)   NULL,

    -- Event date
    event_date                  DATE            NOT NULL,

    -- Audit
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(customer_sk)
);
GO


-- =============================================================================
-- Section 6 : gld_anomaly_events
--   Cross-domain anomaly event store.  Populated by the anomaly detection
--   pipeline which reads from all Gold fact tables and writes a unified
--   anomaly record here for real-time alerting and investigation.
--   Grain    : One row per detected anomaly event (one-to-one or
--              one-to-many from source fact rows)
--   Dist key : account_sk
--   Partition: event_date
-- =============================================================================
IF OBJECT_ID('gold.gld_anomaly_events', 'U') IS NOT NULL
    DROP TABLE gold.gld_anomaly_events;
GO

CREATE TABLE gold.gld_anomaly_events
(
    -- Surrogate key
    anomaly_event_sk            BIGINT          NOT NULL    IDENTITY(1,1),

    -- Source linkage
    source_domain               NVARCHAR(30)    NOT NULL,   -- TRANSACTION, AUTH, API, ERROR, FRAUD
    source_fact_sk              BIGINT          NOT NULL,   -- FK to the source Gold fact table row
    source_event_id             NVARCHAR(64)    NOT NULL,   -- Natural key from source

    -- Dimension SKs
    account_sk                  BIGINT          NULL,       -- gld_dim_account
    customer_sk                 BIGINT          NULL,       -- gld_dim_customer
    service_sk                  INT             NULL,       -- gld_dim_service
    event_date_sk               INT             NOT NULL,   -- gld_dim_date

    -- Degenerate dimension attributes
    account_id                  NVARCHAR(32)    NULL,
    customer_id                 NVARCHAR(32)    NULL,

    -- Anomaly classification
    anomaly_type                NVARCHAR(100)   NOT NULL,   -- VELOCITY_SPIKE, UNUSUAL_GEOGRAPHY, etc.
    anomaly_category            NVARCHAR(50)    NULL,       -- FRAUD, OPERATIONAL, SECURITY, PERFORMANCE
    severity                    NVARCHAR(10)    NOT NULL,   -- LOW, MEDIUM, HIGH, CRITICAL

    -- Scoring
    anomaly_score               FLOAT           NOT NULL,   -- 0.0–1.0
    confidence                  FLOAT           NULL,
    contributing_signals        NVARCHAR(2000)  NULL,       -- JSON array of signal names
    feature_values              NVARCHAR(MAX)   NULL,       -- JSON of key feature values at detection time

    -- Detection model
    detection_model_id          NVARCHAR(64)    NULL,
    detection_model_version     NVARCHAR(30)    NULL,

    -- Alert / case linkage
    alert_id                    NVARCHAR(64)    NULL,       -- Links to gld_fact_transaction_logs or fraud alerts
    case_id                     NVARCHAR(64)    NULL,
    is_escalated                BIT             NOT NULL    DEFAULT 0,
    escalated_to                NVARCHAR(100)   NULL,       -- Team / queue name
    escalated_at                DATETIME2(6)    NULL,

    -- Resolution
    is_resolved                 BIT             NOT NULL    DEFAULT 0,
    resolution_label            NVARCHAR(50)    NULL,       -- TRUE_POSITIVE, FALSE_POSITIVE, INCONCLUSIVE
    resolved_at                 DATETIME2(6)    NULL,
    resolved_by                 NVARCHAR(128)   NULL,

    -- Timestamps (UTC)
    detected_at                 DATETIME2(6)    NOT NULL,
    event_date                  DATE            NOT NULL,   -- Partition column (= DATE(detected_at))

    -- Pipeline audit
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
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
-- Section 7 : gld_log_classifications
--   Stores AI-generated classification labels for log records across all
--   domains.  Enables cross-domain search, theme clustering, and intent
--   detection over log data.
--   Grain    : One row per log record classification event
--   Dist key : source_event_id (HASH for even spread)
-- =============================================================================
IF OBJECT_ID('gold.gld_log_classifications', 'U') IS NOT NULL
    DROP TABLE gold.gld_log_classifications;
GO

CREATE TABLE gold.gld_log_classifications
(
    -- Surrogate key
    classification_sk           BIGINT          NOT NULL    IDENTITY(1,1),

    -- Source linkage
    source_domain               NVARCHAR(30)    NOT NULL,   -- TRANSACTION, AUTH, API, ERROR, AUDIT, FRAUD
    source_event_id             NVARCHAR(64)    NOT NULL,   -- Natural key from source domain
    source_fact_sk              BIGINT          NULL,       -- Gold fact surrogate key (if applicable)

    -- Classification outputs
    primary_label               NVARCHAR(100)   NOT NULL,   -- Primary AI-assigned label
    secondary_label             NVARCHAR(100)   NULL,
    tertiary_label              NVARCHAR(100)   NULL,
    label_confidence            FLOAT           NULL,       -- 0.0–1.0
    all_labels                  NVARCHAR(2000)  NULL,       -- JSON array of { label, score } objects

    -- Intent / theme
    intent_category             NVARCHAR(100)   NULL,       -- e.g. PAYMENT_INITIATION, ACCOUNT_ACCESS
    intent_sub_category         NVARCHAR(100)   NULL,
    topic_cluster_id            NVARCHAR(64)    NULL,       -- Cluster ID from topic modelling

    -- Sentiment (for customer-facing logs and notes)
    sentiment_label             NVARCHAR(20)    NULL,       -- POSITIVE, NEUTRAL, NEGATIVE
    sentiment_score             FLOAT           NULL,       -- -1.0 to +1.0

    -- Risk flags
    is_pii_detected             BIT             NULL,
    is_sensitive_content        BIT             NULL,
    data_sensitivity_score      FLOAT           NULL,

    -- Classification model metadata
    model_id                    NVARCHAR(64)    NULL,
    model_version               NVARCHAR(30)    NULL,
    prompt_template_id          NVARCHAR(64)    NULL,
    classified_at               DATETIME2(0)    NOT NULL,

    -- Audit
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(source_event_id)
);
GO


-- =============================================================================
-- Section 8 : gld_log_embeddings
--   Stores vector embeddings generated by an embedding model (e.g.
--   text-embedding-ada-002 / text-embedding-3-small) for log records.
--   Used for semantic search, nearest-neighbour anomaly detection, and
--   RAG (Retrieval-Augmented Generation) retrieval over log data.
--
--   NOTE: Synapse Dedicated Pool does not yet support a native VECTOR
--   data type.  Embeddings are stored as a JSON array in NVARCHAR(MAX).
--   When the VECTOR type reaches GA in Dedicated Pool, migrate this column
--   to VECTOR(1536) or VECTOR(3072) as appropriate.
--
--   Grain    : One row per log record embedding
--   Dist key : source_event_id
-- =============================================================================
IF OBJECT_ID('gold.gld_log_embeddings', 'U') IS NOT NULL
    DROP TABLE gold.gld_log_embeddings;
GO

CREATE TABLE gold.gld_log_embeddings
(
    -- Surrogate key
    embedding_sk                BIGINT          NOT NULL    IDENTITY(1,1),

    -- Source linkage
    source_domain               NVARCHAR(30)    NOT NULL,   -- TRANSACTION, AUTH, API, ERROR, AUDIT, FRAUD
    source_event_id             NVARCHAR(64)    NOT NULL,   -- Natural key from source domain
    source_fact_sk              BIGINT          NULL,       -- Gold fact surrogate key

    -- Embedding model metadata
    embedding_model_id          NVARCHAR(100)   NOT NULL,   -- e.g. text-embedding-ada-002
    embedding_model_version     NVARCHAR(30)    NULL,
    embedding_dimensions        INT             NOT NULL,   -- e.g. 1536, 3072

    -- Input text that was embedded (truncated; full text in Bronze)
    input_text_preview          NVARCHAR(500)   NULL,       -- First 500 chars of embedded text
    input_text_tokens           INT             NULL,       -- Token count of input

    -- Vector embedding stored as JSON float array
    -- Format: "[0.0123, -0.4567, 0.8910, ...]"
    -- Migrate to native VECTOR type when available in Synapse Dedicated Pool
    embedding_vector            NVARCHAR(MAX)   NOT NULL,

    -- Semantic search helpers
    embedding_norm              FLOAT           NULL,       -- L2 norm of the vector
    topic_cluster_id            NVARCHAR(64)    NULL,       -- Cluster assigned by KMeans / HDBSCAN
    topic_cluster_label         NVARCHAR(100)   NULL,
    nearest_anomaly_distance    FLOAT           NULL,       -- Distance to nearest known anomaly centroid

    -- Validity window
    valid_from                  DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE(),
    valid_to                    DATETIME2(0)    NULL,       -- NULL = currently valid
    is_current                  BIT             NOT NULL    DEFAULT 1,

    -- Audit
    embedded_at                 DATETIME2(0)    NOT NULL,
    pipeline_run_id             NVARCHAR(64)    NULL,
    gold_loaded_at              DATETIME2(0)    NOT NULL    DEFAULT GETUTCDATE()
)
WITH (
    CLUSTERED COLUMNSTORE INDEX,
    DISTRIBUTION = HASH(source_event_id)
);
GO

-- =============================================================================
-- End of 005_gold_facts.sql
-- =============================================================================
