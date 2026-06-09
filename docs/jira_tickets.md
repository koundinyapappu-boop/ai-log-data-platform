# Jira Tickets — Banking AI Log Analytics Platform
**Project Key:** AILAP  
**Project Name:** AI Log Analytics Platform — Azure Synapse  
**Team:** HCLTech Data Engineering  
**Author:** Mangeswara Sri Koundinya  
**Sprint:** Sprint 1 (Jun 02 – Jun 13, 2025)  
**Classification:** Internal | Confidential

---

## Epic

| Field | Value |
|---|---|
| **Ticket** | AILAP-001 |
| **Type** | Epic |
| **Title** | Banking AI Log Analytics Platform on Azure Synapse |
| **Priority** | High |
| **Status** | In Progress |
| **Assignee** | Mangeswara Sri Koundinya |
| **Reporter** | Mangeswara Sri Koundinya |
| **Start Date** | Jun 02, 2025 |
| **Due Date** | Jun 30, 2025 |
| **Story Points** | 89 |

**Description:**  
Build an end-to-end AI-powered log analytics platform for banking operations on Azure Synapse Analytics using the Medallion (Bronze/Silver/Gold) Lakehouse architecture. Platform must support transaction, authentication, fraud, audit, and application error log types with AI anomaly detection, compliance-grade PII masking, and Power BI serving.

---

## Stories & Tasks

---

### AILAP-002 — Project Structure & Architecture Design

| Field | Value |
|---|---|
| **Type** | Story |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 5 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 02, 2025 09:00 |
| **Resolved** | Jun 02, 2025 10:15 |
| **Time Spent** | 1h 15m |

**Prompt:**  
> Scaffold the overall project folder structure and architecture for an AI Log Analytics Platform — include ingestion, pipeline, AI engine, storage, API, dashboard, alerting, and infra layers. No code yet.

**Acceptance Criteria:**
- [ ] Project folder tree defined with all layers separated by concern
- [ ] Tech stack decisions documented per layer
- [ ] Data flow diagram produced (text-based)
- [ ] No code generated at this stage

**Outcome:**  
Delivered 8-layer project blueprint with folder structure covering ingestion/collectors, pipeline/normalizer/enricher, ai_engine/anomaly_detection/classification/summarization/embeddings, storage/hot/cold/vector_store, api, dashboard, alerting, infra. Tech stack: ClickHouse (hot), S3+Parquet (cold), pgvector (vectors), Kafka (queue), FastAPI (API). Data flow diagram included.

---

### AILAP-003 — Azure Synapse Medallion Architecture

| Field | Value |
|---|---|
| **Type** | Story |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 8 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 02, 2025 10:20 |
| **Resolved** | Jun 02, 2025 11:30 |
| **Time Spent** | 1h 10m |

**Prompt:**  
> Scaffold the Azure Synapse Medallion architecture replacing the generic tech stack — define Bronze, Silver, and Gold layers on ADLS Gen2 with full Azure services map and retention policy per layer.

**Acceptance Criteria:**
- [ ] Bronze / Silver / Gold layers defined with format, purpose, and retention
- [ ] Azure services mapped per concern (ingestion, processing, serving, AI, secrets, IaC)
- [ ] Gold layer table catalog defined (summary, hourly agg, anomaly events, embeddings)
- [ ] No hardcoded credentials anywhere in design

**Outcome:**  
Revised architecture to Azure Synapse Medallion pattern. Bronze (raw Parquet/Delta, 90 days) → Silver (Delta Lake 3NF, 1 year) → Gold (Delta Lake star schema, 7 years). Azure services map: Event Hubs, Synapse Pipelines, Spark Pools (MemoryOptimized autoscale 3–10), Dedicated SQL Pool (DW100c), Serverless SQL Pool, ADLS Gen2 (ZRS HNS), Azure OpenAI, Azure AI Search, APIM, Power BI Direct Lake, Azure Monitor, Logic Apps, Key Vault, Bicep IaC.

---

### AILAP-004 — Banking Domain Data Model

| Field | Value |
|---|---|
| **Type** | Story |
| **Epic Link** | AILAP-001 |
| **Priority** | Critical |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 13 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 02, 2025 11:35 |
| **Resolved** | Jun 02, 2025 13:50 |
| **Time Spent** | 2h 15m |

**Prompt:**  
> Scaffold a banking-domain data model using Kimball dimensional modelling principles — define all dimension and fact tables across Bronze, Silver, and Gold layers for transaction, authentication, fraud, audit, and application error log types. No hallucination.

**Acceptance Criteria:**
- [ ] All tables grounded in real banking operations (no invented entities)
- [ ] SCD Type 2 applied to account and customer dimensions
- [ ] Star schema defined in Gold with at least 3 marts
- [ ] PII masking strategy documented at column level
- [ ] Regulatory retention defined per layer (Basel III / PSD2 / GDPR)
- [ ] Surrogate keys, distribution, and partitioning strategy specified

**Outcome:**  
Delivered 26-table banking domain model. Bronze (6 raw tables): transaction_logs, auth_logs, api_gateway_logs, application_error_logs, audit_logs, fraud_alert_logs. Silver (14): 8 conformed dimensions (SCD2 on dim_account + dim_customer) + 6 normalized facts. Gold (14): 6 star-schema dims + 3 fact tables + 2 pre-aggregates + 3 AI enrichment tables. Compliance: PII masked at DDL (last-4 account, email domain only, postcode prefix). Lineage: raw_log_id + batch_id preserved through all layers.

---

### AILAP-005 — Bronze Layer DDL Scripts

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Parent Story** | AILAP-004 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 5 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 02, 2025 14:00 |
| **Resolved** | Jun 02, 2025 15:10 |
| **Time Spent** | 1h 10m |

**Prompt:**  
> Scaffold Bronze layer DDL using Azure Synapse Serverless SQL external tables pointing to ADLS Gen2 — include all 6 banking log source tables with Delta and Parquet format support, partitioned by ingestion_date, with Managed Identity credential.

**Acceptance Criteria:**
- [ ] External Data Source and File Format objects defined
- [ ] All 6 brz_ tables created as EXTERNAL TABLE
- [ ] Partitioned by ingestion_date
- [ ] Managed Identity used (no SAS keys or storage account keys)
- [ ] Valid Synapse Serverless SQL syntax only

**Outcome:**  
Produced `migrations/001_bronze_tables.sql` (559 lines). CREATE EXTERNAL DATA SOURCE with BronzeCredential (Managed Identity), DeltaFormat + ParquetFormat file formats, 6 external tables (brz_transaction_logs, brz_auth_logs, brz_api_gateway_logs, brz_application_error_logs, brz_audit_logs, brz_fraud_alert_logs) over abfss://bronze@ paths, each with regulatory fields (CDC metadata, FX, MFA, W3C trace IDs, Kubernetes context, PSD2/GDPR scope).

---

### AILAP-006 — Silver Dimension & Fact DDL Scripts

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Parent Story** | AILAP-004 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 8 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 02, 2025 15:15 |
| **Resolved** | Jun 02, 2025 16:45 |
| **Time Spent** | 1h 30m |

**Prompt:**  
> Scaffold Silver layer DDL for Synapse Dedicated SQL Pool — create all 8 conformed dimension tables (SCD2 where applicable) and 6 normalized fact tables with Clustered Columnstore Index, appropriate HASH or REPLICATE distribution, and quarterly RANGE RIGHT partitions on fact tables.

**Acceptance Criteria:**
- [ ] All dims use IDENTITY surrogate keys
- [ ] SCD2 columns (effective_from, effective_to, is_current, scd_hash) on dim_account and dim_customer
- [ ] Small dims use REPLICATE, large dims/facts use HASH on most selective FK
- [ ] Facts partitioned quarterly by event_date
- [ ] All tables in silver schema
- [ ] Valid Synapse Dedicated SQL Pool syntax only

**Outcome:**  
Produced `migrations/002_silver_dimensions.sql` (467 lines) — 8 dims: slv_dim_date (full fiscal calendar, bank holiday flags), slv_dim_account (SCD2, scd_hash SHA2_256, AML category), slv_dim_customer (SCD2, masked PII, KYC/CDD, segmentation), slv_dim_channel, slv_dim_transaction_type, slv_dim_service, slv_dim_error_type, slv_dim_auth_event_type. Produced `migrations/003_silver_facts.sql` (565 lines) — 6 facts: slv_transaction_logs, slv_auth_logs, slv_api_request_logs, slv_application_error_logs, slv_audit_logs, slv_fraud_alert_logs, all HASH-distributed with quarterly partitions.

---

### AILAP-007 — Gold Layer DDL Scripts

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Parent Story** | AILAP-004 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 8 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 02, 2025 16:50 |
| **Resolved** | Jun 02, 2025 18:30 |
| **Time Spent** | 1h 40m |

**Prompt:**  
> Scaffold Gold layer DDL for Synapse Dedicated SQL Pool — create 6 conformed dimension tables (current-snapshot, no SCD2), 3 star-schema fact tables with AI scoring columns, 2 pre-aggregate tables, and 3 AI enrichment tables including anomaly registry, log classifications, and embeddings store.

**Acceptance Criteria:**
- [ ] Gold dims are flattened current-snapshot with silver_sk lineage columns
- [ ] Fact tables include is_anomaly, anomaly_score (FLOAT), ai_risk_label columns
- [ ] Aggregate tables include P95 response time and failure rate metrics
- [ ] Embeddings stored as NVARCHAR(MAX) JSON array with inline migration note for native VECTOR type
- [ ] All tables in gold schema
- [ ] Valid Synapse Dedicated SQL Pool syntax only

**Outcome:**  
Produced `migrations/004_gold_dimensions.sql` (367 lines) — 6 current-snapshot dims with silver_sk lineage. Produced `migrations/005_gold_facts.sql` (643 lines) — gld_fact_transaction_logs + gld_fact_auth_events + gld_fact_application_errors (all with AI scoring columns: is_anomaly, anomaly_score, ai_risk_label, ai_fraud_score, ai_model_id, ai_scored_at), gld_agg_txn_hourly + gld_agg_auth_daily, gld_anomaly_events (unified anomaly registry with escalation/resolution), gld_log_classifications (primary/secondary/tertiary labels + confidence), gld_log_embeddings (1536-dim JSON with L2 norm, topic cluster, nearest-anomaly distance).

---

### AILAP-008 — Bronze Ingestion Spark Notebook

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 5 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 03, 2025 09:00 |
| **Resolved** | Jun 03, 2025 10:20 |
| **Time Spent** | 1h 20m |

**Prompt:**  
> Scaffold a Synapse Spark PySpark notebook for Bronze layer ingestion — stream from Azure Event Hubs to ADLS Gen2 Parquet with exactly-once semantics, Key Vault secret retrieval, batch_id enrichment, and per-source checkpointing.

**Acceptance Criteria:**
- [ ] Connection strings retrieved from Key Vault via mssparkutils — never hardcoded
- [ ] Three independent streams (transaction, auth, api_gateway)
- [ ] Each stream writes Parquet partitioned by ingestion_date and source_system
- [ ] Dedicated checkpoint path per stream for exactly-once delivery
- [ ] batch_id and ingestion_timestamp added to every record
- [ ] Valid PySpark + mssparkutils APIs only

**Outcome:**  
Produced `lakehouse/bronze/notebooks/brz_ingest_logs.ipynb` (23 cells). Event Hubs readStream with per-source consumer groups and maxEventsPerTrigger throttle. enrich_stream() helper adds batch_id, ingestion_timestamp, source_system, ingestion_date. Three writeStream sinks to ADLS Gen2 Parquet with dedicated checkpoint paths. Graceful query.stop() monitoring loop.

---

### AILAP-009 — Silver Transaction Transform Notebook

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 8 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 03, 2025 10:25 |
| **Resolved** | Jun 03, 2025 12:15 |
| **Time Spent** | 1h 50m |

**Prompt:**  
> Scaffold a Synapse Spark PySpark notebook for Silver transaction transform — incremental Bronze load with watermark, 3-gate data quality pipeline (null/dedup/amount), ISO standardisation, surrogate key broadcast joins, Delta MERGE upsert, and DQ metrics logging to control table.

**Acceptance Criteria:**
- [ ] Incremental load using ingestion_date watermark parameter
- [ ] DQ gate 1: null check on mandatory fields
- [ ] DQ gate 2: row_number() dedup on raw_log_id
- [ ] DQ gate 3: amount > 0 validation
- [ ] Batch abort if reject fraction exceeds threshold
- [ ] Surrogate key lookup via broadcast join from Silver dims
- [ ] Delta MERGE (upsert) on raw_log_id — idempotent reruns
- [ ] DQ metrics row written to slv_ctrl_dq_metrics

**Outcome:**  
Produced `lakehouse/silver/notebooks/slv_transform_transactions.ipynb` (19 cells). Incremental filter on ingestion_date, create_map for status/currency ISO standardisation, F.broadcast() on 3 Silver dims, DeltaTable.forPath().merge().whenMatchedUpdateAll().whenNotMatchedInsertAll() upsert. DQ metrics (null_count, duplicate_count, rejected_count) written to control table.

---

### AILAP-010 — Silver Auth Transform Notebook

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 5 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 03, 2025 12:20 |
| **Resolved** | Jun 03, 2025 13:30 |
| **Time Spent** | 1h 10m |

**Prompt:**  
> Scaffold a Synapse Spark PySpark notebook for Silver auth log transform — parse JSON raw_payload with explicit schema, derive country_code from IP, standardise auth event types, compute per-user failure velocity using a 1-hour rolling window, and upsert to Silver Delta table.

**Acceptance Criteria:**
- [ ] from_json with explicit schema for raw_payload parsing
- [ ] ip_to_country_code UDF with documented stub for production replacement
- [ ] Auth result standardisation via create_map
- [ ] 1-hour rolling window: Window.partitionBy("user_id").rangeBetween(-3600, 0)
- [ ] is_high_velocity flag when failure count >= configurable threshold
- [ ] Delta MERGE upsert to slv_auth_logs

**Outcome:**  
Produced `lakehouse/silver/notebooks/slv_transform_auth.ipynb` (21 cells). from_json with StructType schema, ip_to_country_code UDF (documented for MaxMind/Azure Maps replacement), create_map auth standardisation, rangeBetween(-3600, 0) failure velocity window, is_high_velocity flag, Delta MERGE upsert.

---

### AILAP-011 — Gold Fact Build & Anomaly Scoring Notebook

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 8 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 03, 2025 13:35 |
| **Resolved** | Jun 03, 2025 15:20 |
| **Time Spent** | 1h 45m |

**Prompt:**  
> Scaffold a Synapse Spark PySpark notebook for Gold fact table build — 5-way broadcast join for star schema construction, Z-score anomaly scoring on amount and response_time_ms producing a normalised anomaly_score [0-1] and ai_risk_label, deterministic SHA-256 surrogate key, and Delta MERGE upsert.

**Acceptance Criteria:**
- [ ] 5-way broadcast join: account, channel, txn_type, service, date dims
- [ ] Z-score: global mean + stddev_pop per batch window
- [ ] anomaly_score = min(max_z, 5) / 5 → range [0.0, 1.0]
- [ ] ai_risk_label: NORMAL / SUSPICIOUS (|Z|≥2.0) / HIGH_RISK (|Z|≥3.5), configurable
- [ ] SHA-256 deterministic txn_log_sk (idempotent across reruns)
- [ ] Delta MERGE on txn_log_sk

**Outcome:**  
Produced `lakehouse/gold/notebooks/gld_build_fact_transactions.ipynb` (17 cells). 5-way F.broadcast() join, global stddev_pop computation, max_z = max(|Z_amount|, |Z_rt|), normalised anomaly_score, configurable threshold parameters, SHA-256 surrogate key, Delta MERGE.

---

### AILAP-012 — Gold Aggregates Notebook

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Parent Story** | AILAP-011 |
| **Priority** | Medium |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 3 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 03, 2025 15:25 |
| **Resolved** | Jun 03, 2025 16:15 |
| **Time Spent** | 50m |

**Prompt:**  
> Scaffold a Synapse Spark PySpark notebook to build Gold pre-aggregate tables — gld_agg_txn_hourly with P95 response time and gld_agg_auth_daily with failure rate and unique IP count, using dynamic partition overwrite for idempotent reruns.

**Acceptance Criteria:**
- [ ] gld_agg_txn_hourly: group by date, hour, channel, txn_type, service — 7 metrics incl. P95
- [ ] gld_agg_auth_daily: group by date, customer, channel — failure rate, countDistinct IPs and devices
- [ ] Dynamic partition overwrite (spark.sql.sources.partitionOverwriteMode = dynamic)
- [ ] .option("replaceWhere") scoped to batch window only

**Outcome:**  
Produced `lakehouse/gold/notebooks/gld_build_aggregates.ipynb` (17 cells). percentile_approx(..., 0.95) for P95, countDistinct for unique IPs/devices, dynamic partition overwrite, replaceWhere scoped to process_date window.

---

### AILAP-013 — Synapse Pipeline JSONs & Master Orchestrator

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 8 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 04, 2025 09:00 |
| **Resolved** | Jun 04, 2025 11:10 |
| **Time Spent** | 2h 10m |

**Prompt:**  
> Scaffold Azure Synapse Pipeline JSON definitions for Bronze ingestion (15-min schedule, watermark, error handler), Silver transform (parallel notebooks, zero-row validation), Gold build (sequential fact then aggregates, webhook notify), and a master orchestrator with Until polling loops and stage timeouts.

**Acceptance Criteria:**
- [ ] pl_bronze_ingest: ScheduleTrigger every 15 min, Lookup watermark, ExecuteNotebook, stored proc update, error handler pipeline
- [ ] pl_silver_transform: parallel ExecuteNotebook (transactions + auth), Script zero-row DQ validation
- [ ] pl_gold_build: sequential notebooks, Script view refresh, WebActivity notify on success + failure
- [ ] pl_master_orchestrator: Bronze→Silver→Gold sequence, Until loops, 1h/3h/4h timeouts
- [ ] Valid Synapse Pipeline JSON activity types only (no hallucinated types)

**Outcome:**  
Produced 4 pipeline JSON files: pl_bronze_ingest.json (380 lines) — 15-min trigger, watermark Lookup, IfCondition error guard, sp_update_watermark; pl_silver_transform.json (280 lines) — parallel notebooks, fan-in Script validation, SetVariable row counts; pl_gold_build.json (301 lines) — sequential notebooks, view refresh proc, WebActivity success/failure; pl_master_orchestrator.json (526 lines) — Bronze→Silver→Gold with Until loops, set_batch_id, per-stage status variables, combined success notification.

---

### AILAP-014 — Azure Bicep IaC

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Parent Story** | AILAP-013 |
| **Priority** | High |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 5 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 04, 2025 11:15 |
| **Resolved** | Jun 04, 2025 12:20 |
| **Time Spent** | 1h 05m |

**Prompt:**  
> Scaffold Azure Bicep IaC for the full platform environment — Synapse Workspace, ADLS Gen2 (ZRS, HNS, 4 containers), Event Hubs (Standard, auto-inflate, Avro capture), Key Vault (RBAC, purge-protected), Spark Pool (autoscale 3–10), Dedicated SQL Pool (DW100c), Azure OpenAI, and MSI role assignments. No hardcoded secrets.

**Acceptance Criteria:**
- [ ] All resources parameterised by environment, location, and prefix
- [ ] ADLS: ZRS, HNS enabled, shared-key auth disabled, public access off, 4 containers
- [ ] Synapse: MSI, managed VNet, data exfiltration protection
- [ ] Key Vault: RBAC auth, 90-day soft delete, purge protection
- [ ] Role assignments: Storage Blob Data Contributor + Key Vault Secrets User to Synapse MSI
- [ ] No hardcoded passwords or connection strings anywhere

**Outcome:**  
Produced `infra/bicep/main.bicep` (449 lines). Parameterised by environment/location/prefix/tenantId. ADLS Gen2 (Standard_ZRS, HNS, versioning, 30-day soft delete, 4 containers). Synapse (MSI, managedVirtualNetwork, preventDataExfiltration). Spark Pool (Spark 3.4, MemoryOptimized Small, autoscale 3–10, autoPause 15 min). Dedicated SQL Pool (DW100c param-driven). Key Vault (RBAC, 90-day soft delete, purge protection). Event Hubs (Standard, auto-inflate 10 TUs, Avro capture to bronze container). Azure OpenAI (kind OpenAI, SKU S0). Role assignments via guid() scoped to storage and vault.

---

### AILAP-015 — ER Diagram & Data Model Documentation

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | Medium |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 5 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 05, 2025 09:00 |
| **Resolved** | Jun 05, 2025 10:45 |
| **Time Spent** | 1h 45m |

**Prompt:**  
> Scaffold a full data model ER documentation file — produce Mermaid ER diagrams for Bronze, Silver, and Gold layers derived from the actual DDL files, a complete FK relationship matrix, ASCII star schema diagrams per Gold mart, SCD2 mechanics with worked example, data lineage map, and distribution and partitioning reference table.

**Acceptance Criteria:**
- [ ] Mermaid diagrams accurate to DDL columns (no invented columns)
- [ ] FK matrix covers every foreign key with cardinality notation
- [ ] SCD2 section includes worked example with effective_from/to/is_current
- [ ] Lineage map traces every Gold table to source system
- [ ] Distribution & partitioning table covers all 26 tables

**Outcome:**  
Produced `docs/data_model_er.md` (1,755 lines). 3 Mermaid erDiagram blocks, full FK relationship matrix (Silver FKs, Gold FK-to-dimension, polymorphic AI table cross-domain links), 3 ASCII star schema diagrams, SCD2 mechanics with risk-rating change worked example and point-in-time join pattern, Gold→Silver→Bronze→source lineage table, 26-table distribution/partition reference, naming convention glossary.

---

### AILAP-016 — HCLTech PowerPoint Presentation

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | Medium |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 3 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 06, 2025 09:00 |
| **Resolved** | Jun 06, 2025 10:10 |
| **Time Spent** | 1h 10m |

**Prompt:**  
> Scaffold an 8-slide HCLTech-branded PowerPoint deck for this project using the uploaded Chubb template — cover slide, agenda, Architecture, GIT Details, Data Model, AI Working Journal, Testing Strategy, and end card. Use original template backgrounds exactly without changing colors.

**Acceptance Criteria:**
- [ ] 8 slides matching template layout (cover, agenda, 5 content, end card)
- [ ] Original template images used as pixel-perfect slide backgrounds
- [ ] Project content overlaid as text boxes on top
- [ ] HCLTech brand colours and footer preserved
- [ ] Valid .pptx format openable in PowerPoint / Google Slides

**Outcome:**  
Produced `docs/AI_Log_Analytics_Platform_HCLTech.pptx`. Extracted 8 template images from uploaded .docx, used as full-slide backgrounds via python-pptx. Overlaid project content: cover (title, author, date), agenda (5 items with highlight rows), content slides (Architecture/GIT/Data Model/AI Journal/Testing with bullet hierarchy), HCLTech end card unchanged.

---

### AILAP-017 — AI Working Journal

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | Low |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 2 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 09, 2025 09:00 |
| **Resolved** | Jun 09, 2025 09:45 |
| **Time Spent** | 45m |

**Prompt:**  
> Scaffold an AI working journal markdown file capturing every prompt and outcome across the full project lifecycle — one prompt line per step with corresponding deliverables, file names, and line counts.

**Acceptance Criteria:**
- [ ] Every step captured with prompt (one line) and outcome
- [ ] File names and line counts included in outcomes
- [ ] Summary table at end
- [ ] Saved as .md file committed to the repo

**Outcome:**  
Produced `docs/ai_working_journal.md` (150 lines). 9 steps documented with single-line prompts and detailed outcomes. Summary table with deliverable + line count per step.

---

### AILAP-018 — Jira Ticket Documentation (This File)

| Field | Value |
|---|---|
| **Type** | Task |
| **Epic Link** | AILAP-001 |
| **Priority** | Low |
| **Status** | Done |
| **Assignee** | Mangeswara Sri Koundinya |
| **Story Points** | 2 |
| **Sprint** | Sprint 1 |
| **Created** | Jun 09, 2025 10:00 |
| **Resolved** | Jun 09, 2025 10:30 |
| **Time Spent** | 30m |

**Prompt:**  
> Scaffold a Jira ticket markdown document for this project — include one Epic, all Stories and Tasks with realistic timestamps, story points, time spent, scaffold-style prompts per ticket, acceptance criteria, and outcomes. No hallucination.

**Acceptance Criteria:**
- [ ] All tickets grounded in actual work done — no invented tasks
- [ ] Prompts start with "Scaffold" (consistent AI prompt style)
- [ ] Realistic timestamps, story points, and time spent per ticket
- [ ] Acceptance criteria match what was actually validated
- [ ] Outcomes describe actual deliverables with file names and line counts

**Outcome:**  
Produced this file — `docs/jira_tickets.md` — 1 Epic (AILAP-001) + 17 Stories/Tasks (AILAP-002 through AILAP-018), each with Jira-style metadata, scaffold-style prompt, acceptance criteria checklist, and actual outcome.

---

## Sprint Velocity Summary

| Ticket | Title | Points | Time Spent | Status |
|---|---|---|---|---|
| AILAP-002 | Project Structure & Architecture | 5 | 1h 15m | Done |
| AILAP-003 | Azure Synapse Medallion Architecture | 8 | 1h 10m | Done |
| AILAP-004 | Banking Domain Data Model | 13 | 2h 15m | Done |
| AILAP-005 | Bronze Layer DDL | 5 | 1h 10m | Done |
| AILAP-006 | Silver Dimension & Fact DDL | 8 | 1h 30m | Done |
| AILAP-007 | Gold Layer DDL | 8 | 1h 40m | Done |
| AILAP-008 | Bronze Ingestion Spark Notebook | 5 | 1h 20m | Done |
| AILAP-009 | Silver Transaction Transform Notebook | 8 | 1h 50m | Done |
| AILAP-010 | Silver Auth Transform Notebook | 5 | 1h 10m | Done |
| AILAP-011 | Gold Fact Build & Anomaly Scoring | 8 | 1h 45m | Done |
| AILAP-012 | Gold Aggregates Notebook | 3 | 50m | Done |
| AILAP-013 | Synapse Pipeline JSONs & Orchestrator | 8 | 2h 10m | Done |
| AILAP-014 | Azure Bicep IaC | 5 | 1h 05m | Done |
| AILAP-015 | ER Diagram & Documentation | 5 | 1h 45m | Done |
| AILAP-016 | HCLTech PowerPoint | 3 | 1h 10m | Done |
| AILAP-017 | AI Working Journal | 2 | 45m | Done |
| AILAP-018 | Jira Ticket Documentation | 2 | 30m | Done |
| **Total** | | **101 pts** | **~24h** | **17/17 Done** |

---

*Classification: Internal | Copyright © 2025 HCLTech | Confidential*
