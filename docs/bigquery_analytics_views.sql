-- =============================================================================
-- AI Skincare Advisor — BigQuery Agent Analytics SQL Views
-- =============================================================================
-- These saved queries provide operational visibility into the agent system.
-- Table: boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor
-- =============================================================================


-- 1. Token Usage Analysis (avg tokens per conversation)
-- Shows how many tokens each conversation uses on average.
CREATE OR REPLACE VIEW `boreal-graph-465506-f2.adk_agent_logs.v_token_usage` AS
SELECT
    DATE(timestamp) AS day,
    session_id,
    COUNT(*) AS total_events,
    SUM(CAST(JSON_VALUE(content, '$.usage.total') AS INT64)) AS total_tokens,
    AVG(CAST(JSON_VALUE(content, '$.usage.total') AS INT64)) AS avg_tokens_per_call
FROM `boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor`
WHERE event_type = 'LLM_RESPONSE'
GROUP BY day, session_id
ORDER BY day DESC;


-- 2. Latency P50 / P99 for LLM and Tool Calls
-- Identifies slow LLM calls and tool executions for optimization.
CREATE OR REPLACE VIEW `boreal-graph-465506-f2.adk_agent_logs.v_latency_percentiles` AS
SELECT
    event_type,
    APPROX_QUANTILES(CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64), 100)[OFFSET(50)] AS p50_ms,
    APPROX_QUANTILES(CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64), 100)[OFFSET(90)] AS p90_ms,
    APPROX_QUANTILES(CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64), 100)[OFFSET(99)] AS p99_ms,
    AVG(CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64)) AS avg_ms,
    COUNT(*) AS total_calls
FROM `boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor`
WHERE event_type IN ('LLM_RESPONSE', 'TOOL_COMPLETED')
  AND JSON_VALUE(latency_ms, '$.total_ms') IS NOT NULL
GROUP BY event_type;


-- 3. Error Rate Over Time
-- Tracks daily error rate for LLM and tool calls.
CREATE OR REPLACE VIEW `boreal-graph-465506-f2.adk_agent_logs.v_error_rate` AS
SELECT
    DATE(timestamp) AS day,
    event_type,
    COUNTIF(status = 'ERROR') AS error_count,
    COUNT(*) AS total_count,
    ROUND(COUNTIF(status = 'ERROR') / COUNT(*) * 100, 2) AS error_rate_pct
FROM `boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor`
WHERE event_type IN ('LLM_RESPONSE', 'LLM_ERROR', 'TOOL_COMPLETED', 'TOOL_ERROR')
GROUP BY day, event_type
ORDER BY day DESC;


-- 4. Sub-Agent (Tool Provenance) Breakdown
-- Shows which sub-agents are called most frequently and their avg latency.
CREATE OR REPLACE VIEW `boreal-graph-465506-f2.adk_agent_logs.v_sub_agent_usage` AS
SELECT
    JSON_VALUE(content, '$.tool') AS tool_name,
    JSON_VALUE(content, '$.tool_origin') AS tool_origin,
    COUNT(*) AS call_count,
    AVG(CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64)) AS avg_latency_ms,
    APPROX_QUANTILES(CAST(JSON_VALUE(latency_ms, '$.total_ms') AS INT64), 100)[OFFSET(99)] AS p99_latency_ms
FROM `boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor`
WHERE event_type = 'TOOL_COMPLETED'
GROUP BY tool_name, tool_origin
ORDER BY call_count DESC;


-- 5. Session Duration Analysis
-- Shows avg session duration and number of turns per session.
CREATE OR REPLACE VIEW `boreal-graph-465506-f2.adk_agent_logs.v_session_duration` AS
SELECT
    session_id,
    user_id,
    MIN(timestamp) AS session_start,
    MAX(timestamp) AS session_end,
    TIMESTAMP_DIFF(MAX(timestamp), MIN(timestamp), SECOND) AS duration_seconds,
    COUNT(DISTINCT invocation_id) AS num_turns,
    COUNT(*) AS total_events
FROM `boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor`
GROUP BY session_id, user_id
HAVING COUNT(*) > 1
ORDER BY session_start DESC;


-- 6. Daily Active Users and Sessions Summary
-- High-level dashboard metric.
CREATE OR REPLACE VIEW `boreal-graph-465506-f2.adk_agent_logs.v_daily_summary` AS
SELECT
    DATE(timestamp) AS day,
    COUNT(DISTINCT user_id) AS unique_users,
    COUNT(DISTINCT session_id) AS total_sessions,
    COUNT(*) AS total_events,
    SUM(CAST(JSON_VALUE(content, '$.usage.total') AS INT64)) AS total_tokens_used,
    COUNTIF(event_type IN ('LLM_ERROR', 'TOOL_ERROR')) AS total_errors
FROM `boreal-graph-465506-f2.adk_agent_logs.agent_events_ai_skincare_advisor`
GROUP BY day
ORDER BY day DESC;
