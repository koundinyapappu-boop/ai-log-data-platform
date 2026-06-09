# AI Working Journal — Banking AI Log Analytics Platform
**Project:** AI Log Analytics Platform on Azure Synapse  
**Author:** Mangeswara Sri Koundinya  
**Platform:** Claude Code (Remote Session)  
**Branch:** claude/affectionate-lovelace-519pwf  
**Date:** Jun 09, 2025

---

## Journal Format
Each entry follows the pattern:
> **Prompt** — what was asked (one line)  
> **Outcome** — what was delivered

---

## Step 1 — Project Structure & Architecture

**Prompt:** "Build a simple AI Log Analytics platform. Create only the project structure and architecture. Do not generate code yet."

**Outcome:** Designed a full 8-layer project blueprint — ingestion, pipeline, AI engine, storage (hot/cold/vector), API, dashboard, alerting, and infra. Produced a complete folder structure with tech stack decisions: ClickHouse for hot queries, S3+Parquet for cold archive, pgvector for embeddings, Kafka for message queue, FastAPI for API layer.

---

## Step 2 — Azure Synapse Medallion Architecture

**Prompt:** "Tech stack would be Azure Synapse for Bronze, Silver and Gold."

**Outcome:** Revised entire architecture to Azure Synapse Analytics with Medallion Lakehouse pattern. Mapped Bronze (raw ADLS Gen2 Parquet) → Silver (Delta Lake, normalized) → Gold (Delta Lake, AI-scored star schema). Produced full Azure services map: Event Hubs, Synapse Pipelines, Spark Pools, Dedicated SQL Pool, ADLS Gen2, Azure OpenAI, Azure AI Search, APIM, Power BI, Azure Monitor, Bicep IaC.

---

## Step 3 — Banking Domain Data Model

**Prompt:** "Since I am developing for banking please create a data model related to banking domain which includes data warehousing principals and don't hallucinate."

**Outcome:** Designed a 26-table banking domain model grounded in Kimball dimensional modelling:
- **Bronze (6 tables):** brz_transaction_logs, brz_auth_logs, brz_api_gateway_logs, brz_application_error_logs, brz_audit_logs, brz_fraud_alert_logs
- **Silver (14 tables):** 8 conformed dimensions (SCD Type 2 on account + customer) + 6 normalized facts
- **Gold (14 tables):** 6 star-schema dimensions + 3 fact tables + 2 pre-aggregates + 3 AI enrichment tables
- Applied CCI, HASH/REPLICATE distribution, quarterly partitions, PII masking at DDL level, audit lineage via raw_log_id + batch_id.

---

## Step 4a — DDL Migration Scripts

**Prompt:** "Please generate DDL scripts, Synapse Spark notebooks, and Pipeline JSONs."

**Outcome (DDL):** Produced 5 versioned migration scripts (2,601 lines of Synapse SQL):
- `001_bronze_tables.sql` — Serverless SQL external tables on ADLS Gen2 (Delta + Parquet formats)
- `002_silver_dimensions.sql` — SCD2 dims with scd_hash, REPLICATE/HASH distribution, CCI
- `003_silver_facts.sql` — Normalized facts with quarterly partitions, dedup hash, HASH distribution
- `004_gold_dimensions.sql` — Flattened current-snapshot dims with silver lineage columns
- `005_gold_facts.sql` — AI-scored facts, hourly/daily aggregates, anomaly registry, log embeddings store

---

## Step 4b — Synapse Spark Notebooks (PySpark)

**Prompt:** "Please generate DDL scripts, Synapse Spark notebooks, and Pipeline JSONs." (same request, notebooks component)

**Outcome:** Produced 5 production-quality PySpark notebooks (nbformat 4.4):
- `brz_ingest_logs.ipynb` — Event Hubs readStream → ADLS Parquet, exactly-once checkpointing, Key Vault secrets via mssparkutils
- `slv_transform_transactions.ipynb` — Incremental Bronze load, 3-gate DQ (null/dedup/amount), ISO standardization, surrogate key broadcast joins, Delta MERGE upsert, DQ metrics to control table
- `slv_transform_auth.ipynb` — JSON payload parsing, IP→country UDF, auth status normalization, 1-hour rolling failure velocity window
- `gld_build_fact_transactions.ipynb` — 5-way star schema join, Z-score anomaly scoring (anomaly_score 0–1), ai_risk_label thresholds, Delta MERGE
- `gld_build_aggregates.ipynb` — gld_agg_txn_hourly (P95 response time via percentile_approx), gld_agg_auth_daily (failure rate, countDistinct IPs), dynamic partition overwrite

---

## Step 4c — Synapse Pipeline JSONs & Bicep IaC

**Prompt:** "Please generate DDL scripts, Synapse Spark notebooks, and Pipeline JSONs." (same request, pipelines component)

**Outcome:** Produced 4 pipeline JSON files + 1 Bicep IaC:
- `pl_bronze_ingest.json` — 15-min schedule trigger, watermark lookup from control table, ExecuteNotebook, stored proc watermark update, error handler pipeline
- `pl_silver_transform.json` — Parallel notebook execution (transactions + auth), fan-in zero-row DQ validation via Script activity
- `pl_gold_build.json` — Sequential fact → aggregates → view refresh, Logic App webhook on success/failure
- `pl_master_orchestrator.json` — Bronze → Silver → Gold sequence with Until polling loops, per-stage timeouts (1h/3h/4h), combined status notification
- `infra/bicep/main.bicep` — Full Azure environment: Synapse Workspace, ADLS Gen2 (ZRS, HNS), Event Hubs, Key Vault, OpenAI, Spark Pool (autoscale 3–10), Dedicated SQL Pool (DW100c), MSI role assignments

---

## Step 5 — ER Diagram & Data Model Documentation

**Prompt:** "I want a data model for this DW — ER diagram and relations etc."

**Outcome:** Produced `docs/data_model_er.md` (1,755 lines) containing:
- Medallion layer overview table (Bronze/Silver/Gold entity inventory)
- 3 Mermaid ER diagrams — Bronze (no FKs), Silver (full FK cardinality), Gold (star schema + polymorphic AI table links)
- Complete FK relationship matrix — every FK: source table, source column, target table, cardinality, note
- 3 ASCII star schema diagrams: Transaction, Auth/Security, Application Health marts
- SCD2 mechanics with worked example (customer risk rating change mid-year, point-in-time join pattern)
- Data lineage map: Gold → Silver → Bronze → source system for every table
- Distribution & partitioning strategy table for all 26 tables (REPLICATE vs HASH rationale)
- Naming convention reference: brz_/slv_/gld_, _sk, _at, ai_, is_, _ms suffixes

---

## Step 6 — Conversational Project Summary

**Prompt:** "For this entire work give me a mutual conversational kind of AI journal in a text file."

**Outcome:** Produced `docs/project_conversation_summary.txt` (324 lines) — a plain-English debrief of every architectural decision, written in a conversational tone. Covers: why Bronze is append-only, why Z-score over black-box models, why watermark pattern prevents duplicates, why SCD2 is needed for mid-year customer changes, why quarterly partitions align with regulatory reporting, what comes next (Azure ML, Power BI Direct Lake, Azure AI Search, alerting).

---

## Step 7 — HCLTech PowerPoint Presentation (First Version)

**Prompt:** "Please create a PPT from this template with respect to our project."

**Outcome:** Generated `docs/AI_Log_Analytics_Platform_HCLTech.pptx` — 8-slide deck matching the HCLTech Chubb template structure: dark navy cover, agenda with numbered rows, 5 content slides (Architecture, GIT, Data Model, AI Journal, Testing), HCLTech end card. Used python-pptx with HCLTech brand colours (HCLT blue #006BFF, purple, green classification tag).

---

## Step 8 — HCLTech PPT With Original Template Backgrounds

**Prompt:** "I want same kind of PPT — HCL first page and agenda etc. Don't change background colors."

**Outcome:** Rebuilt the deck using the original template slide images extracted from the uploaded .docx as pixel-perfect slide backgrounds. Cover (dark navy + geometric band), agenda (woman photo, light purple highlight rows), content slides (white with footer baked in), end card (blue/purple gradient) — all identical to original template. Project content overlaid as text boxes on top of the unchanged backgrounds.

---

## Step 9 — AI Working Journal (This Document)

**Prompt:** "Now please create an AI journal for this project like I asked you in one line for each kind of task and I wanted it like Prompt: 'Create dimension tables like customer, region, lob, status, and date from curated layer.' and outcome for all this project for each step."

**Outcome:** Produced this document — `docs/ai_working_journal.md` — capturing every prompt in one line with its corresponding outcome across all 9 steps of the project lifecycle.

---

## Summary Table

| Step | Prompt (one line) | Deliverable | Lines / Files |
|------|-------------------|-------------|---------------|
| 1 | Create project structure and architecture, no code yet | Folder blueprint + tech stack decisions | — |
| 2 | Tech stack = Azure Synapse Bronze/Silver/Gold | Revised Medallion architecture with full Azure services map | — |
| 3 | Banking data model with DW principals, no hallucination | 26-table banking domain model (Kimball star schema, SCD2, PII masking) | — |
| 4a | Generate DDL scripts | 5 migration SQL scripts | 2,601 lines |
| 4b | Generate Synapse Spark notebooks | 5 PySpark notebooks (nbformat 4.4) | ~1,200 lines |
| 4c | Generate Pipeline JSONs + IaC | 4 Pipeline JSONs + Bicep IaC | ~1,800 lines |
| 5 | Data model ER diagram and relations | ER diagrams (Mermaid), FK matrix, star schema, SCD2 docs | 1,755 lines |
| 6 | Conversational AI journal in text file | Plain-English project debrief | 324 lines |
| 7 | Create PPT from HCLTech template | 8-slide PPTX (python-pptx, brand colours) | 1 file |
| 8 | Same PPT but don't change background colors | 8-slide PPTX using original template images as backgrounds | 1 file |
| 9 | AI working journal with prompt + outcome per step | This document | — |

---

*Classification: Internal | Copyright © 2025 HCLTech | Confidential*
