# Dead Code & Outdated Documentation Audit

## Executive Summary

This audit evaluates the JustUS codebase for obsolete dependencies, stale documentation references, unused configuration items, deprecated utilities, and dead code declarations.

All findings are backed by empirical code search and file analysis across the Node.js backend, Flutter frontend, and Supabase schema layers.

---

## Findings Matrix Summary

| Category | Item | Location | Current Status | Risk / Impact |
| :--- | :--- | :--- | :--- | :--- |
| **Outdated Docs** | Ollama / Llama 3.2 AI Engine References | [`README.md:23`](file:///f:/JustUS/README.md#L23), [`README.md:57`](file:///f:/JustUS/README.md#L57), [`README.md:67`](file:///f:/JustUS/README.md#L67) | **STALE** (Architecture migrated to OpenRouter AI Gateway in `aiConfig.js`) | Medium (Misleads setup prerequisites) |

---

## Detailed Investigation

### 1. Ollama / Llama 3.2 AI Engine Documentation References

* **File**: [`README.md`](file:///f:/JustUS/README.md)
* **Stale Lines**:
  - Line 23: `Every 24 hours, a new question is generated using the integrated Llama 3.2 AI engine.`
  - Line 57: `- **AI Engine**: Ollama (Running Llama 3.2:3b locally or on-server).`
  - Line 67: `- Ollama (for AI features)`
* **Actual Code Implementation**:
  - [`Backend/config/aiConfig.js`](file:///f:/JustUS/Backend/config/aiConfig.js#L27-L36) uses **OpenRouter API Gateway**:
    ```javascript
    const MODELS = [
      "openrouter/free",
      "openai/gpt-oss-120b:free",
      "nvidia/nemotron-3-super:free"
    ];
    const url = "https://openrouter.ai/api/v1/chat/completions";
    ```
* **Classification**: **STALE DOCUMENTATION**.
* **Remediation**: Update `README.md` to reflect the active OpenRouter AI Gateway integration (`https://openrouter.ai`) and remove Ollama as an installation prerequisite.

---

## Recommended Cleanup Action Plan

1. **`README.md`**:
   - Replace Ollama/Llama 3.2 references with OpenRouter AI Gateway documentation.
