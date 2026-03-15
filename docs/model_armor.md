# Model Armor Integration

## Overview

[Model Armor](https://cloud.google.com/security/products/model-armor) is Google Cloud's managed AI safety layer that screens user prompts and model responses for harmful content. It runs as an external API — our agent sends text to it and gets back **match/no-match** verdicts.

## Architecture

```
User Message
    │
    ▼
┌──────────────────────────┐
│   before_model_callback  │  (agent.py)
│                          │
│  1. Medical pattern check│  ← domain-specific regex
│  2. Model Armor scan     │  ← API call to Model Armor
│                          │
│  Blocked? → return early │
│  Passed?  → continue     │
└──────────────────────────┘
    │
    ▼
   LLM generates response
    │
    ▼
┌──────────────────────────┐
│   after_model_callback   │  (agent.py)
│                          │
│  Model Armor scan output │  ← API call to Model Armor
│                          │
│  Blocked? → replace resp │
│  Passed?  → return as-is │
└──────────────────────────┘
    │
    ▼
  User sees response
```

## Filters Enabled

Configured in the template `skincare-advisor-safety`:

| Filter | Threshold | What it catches |
|--------|-----------|-----------------|
| **RAI — Hate Speech** | MEDIUM_AND_ABOVE | Racial slurs, discriminatory content |
| **RAI — Harassment** | MEDIUM_AND_ABOVE | Bullying, personal attacks |
| **RAI — Dangerous** | MEDIUM_AND_ABOVE | Self-harm, violence instructions |
| **RAI — Sexually Explicit** | MEDIUM_AND_ABOVE | Adult content |
| **Prompt Injection / Jailbreak** | LOW_AND_ABOVE | "Ignore your instructions", DAN prompts |
| **Malicious URIs** | ENABLED | Phishing links, malware URLs |
| **CSAM** | Always-on | Child safety (cannot be disabled) |

## Key Files

| File | Purpose |
|------|---------|
| `app/skincare_advisor/model_armor.py` | SDK wrapper — `ModelArmorService` class, `sanitize_prompt()` and `sanitize_response()` |
| `app/skincare_advisor/agent.py` | Guardrail callbacks: `_safety_guardrail` (input) and `_output_safety_guardrail` (output) |
| `scripts/create_model_armor_template.py` | One-time script to create the template in GCP |
| `app/skincare_advisor/.agent_engine_config.json` | Passes `MODEL_ARMOR_TEMPLATE_ID` and `MODEL_ARMOR_LOCATION` to the Agent Engine container |

## Environment Variables

| Variable | Value | Where |
|----------|-------|-------|
| `MODEL_ARMOR_TEMPLATE_ID` | `skincare-advisor-safety` | `.env` + `.agent_engine_config.json` |
| `MODEL_ARMOR_LOCATION` | `us-central1` | `.agent_engine_config.json` |

> **Important**: The `.agent_engine_config.json` is what actually passes env vars to the deployed container. The `.env` file is only for local development.

## IAM Permissions

The Agent Engine compute service account needs `roles/modelarmor.user`:

```bash
gcloud projects add-iam-policy-binding boreal-graph-465506-f2 \
  --member="serviceAccount:1089521368524-compute@developer.gserviceaccount.com" \
  --role="roles/modelarmor.user"
```

## Fail-Open Design

Model Armor is designed to **fail open** — if the API is unavailable, misconfigured, or errors out, requests pass through with a warning log. This prevents Model Armor outages from blocking all users.

```python
# model_armor.py — fail-open pattern
except Exception as e:
    logger.error(f"Model Armor sanitize_prompt failed: {e}")
    return SanitizationResult(error=str(e))  # is_blocked=False
```

## Creating / Updating the Template

```bash
# Create (first time only)
python scripts/create_model_armor_template.py

# Update filters → edit create_model_armor_template.py, then delete + recreate:
gcloud model-armor templates delete skincare-advisor-safety \
  --location=us-central1 --project=boreal-graph-465506-f2
python scripts/create_model_armor_template.py
```

## Gotchas

1. **Relative imports only** — In the deployed container, use `from .model_armor import model_armor`, not `from skincare_advisor.model_armor`. The ADK CLI restructures the package.
2. **IAM propagation** — After granting `roles/modelarmor.user`, wait ~5 min for it to take effect.
3. **Regional endpoint** — Model Armor uses `modelarmor.{region}.rep.googleapis.com`, not the default API endpoint.
