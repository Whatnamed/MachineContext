# Devlog — 2026-09-16 Qoder CN Desktop TokenRhythm models audit and DSH deepseek-flash reasoning capability

## Scope

1. Read-only verification and smoke assessment of two pre-configured TokenRhythm custom models in Qoder CN Desktop: `qwen3.8-flash` and `qwen3.8-max`.
2. Add `compat.thinkingFormat: deepseek` and `reasoningEfforts: { off: null, low: low, high: high, max: max }` to `deepseek-flash` in `~/.dsh/settings.yaml`.
3. Perform end-to-end wire smoke for DSH `deepseek-flash` across all four reasoning levels (`off`, `low`, `high`, `max`).
4. Re-sync and publish MachineContext facts.

---

## 1. Qoder CN Desktop TokenRhythm Models Audit

### Environmental Baseline & CLI Status
- **Qoder CN Desktop Version**: `0.2.5` (`D:\Qoder-CN\Qoder CN\.qoder-versions\0.2.5\Qoder CN.exe`).
- **Standalone CLI**: Not installed (`where.exe qoder`, `where.exe qoderclicn`, and `Get-Command qoder` returned not found; `~/.qoder-cn/entry/qodercn-dispatcher.ps1` confirms standalone CLI is absent).
- **Desktop/CLI Sharing**: Independent / not shared (no separate CLI is installed).

### BYOK Storage & Credential Separation
Qoder stores custom model metadata across two tiers:
1. **Endpoint & Secret Tier** (`%USERPROFILE%\.qoder-cn\settings.json` under `providers`):
   - Key: `qoder-custom-f4ab8f69-b243-42f2-a82f-549138a4fa8a`
   - `baseUrl`: `https://tokenrhythm.studio/v1`
   - `type`: `openai-compatible`
   - `protocol`: `openai-responses`
   - `authType`: `bearer`
   - `apiKey`: present (length 49, secret)
2. **Capability & Context Tier** (`%APPDATA%\com.qodercn.app.stable\main.sqlite` table `byok_model_capability_metadata`):
   - Zero credentials stored in this SQLite table.
   - Separate rows for `qwen3.8-flash` and `qwen3.8-max`.
   - `available_context_windows_json`: `[200000, 400000, 1000000]` (200K / 400K / 1M).
   - `default_context_window`: `400000` (400K).
   - `is_vision`: `1` (enabled).
   - `is_reasoning`: `1` (enabled).
   - `efforts_json`: `["low", "medium", "xhigh"]`.

### Wire Protocol Verification
Inspection of Qoder's worker runtime (`qoder-worker-runtime.obf.mjs`) confirms:
- When `protocol: "openai-responses"` is selected, Qoder explicitly maps the target URL to `${baseUrl}/responses` (`https://tokenrhythm.studio/v1/responses`).
- Requests are structured using OpenAI Responses API format: `input` (not `messages`), `max_output_tokens`, `include: ["reasoning.encrypted_content"]`, and `reasoning: { effort: r, summary: "auto" }`.

### Smoke & Upstream Verification
- `qwen3.8-flash`: Functional. User confirmed successful responses during Qoder interaction; debug logs show successful HTTP 200 responses from `https://tokenrhythm.studio/v1/responses`.
- `qwen3.8-max`: Upstream failure. Every request to `https://tokenrhythm.studio/v1/responses` for `qwen3.8-max` failed with `HTTP 400` returning `providerError: { status_code: 400, code: "MODEL_NOT_AVAILABLE", message: "模型不可用：qwen3.8-max" }`. Qoder catches this error and presents its generic dialog: "系统发生异常 请重试...". This confirms Qoder's configuration is correct, but TokenRhythm's upstream route currently does not serve `qwen3.8-max` on the Responses endpoint. User confirmed leaving `max` alone.

---

## 2. DSH deepseek-flash Reasoning Configuration

### Configuration Changes in `~/.dsh/settings.yaml`
Under `llm-pi-ai.providers.tokenrhythm.models`:
```yaml
        - id: deepseek-flash
          name: DeepSeek V4.1 Flash
          contextWindow: 1000000
          maxTokens: 384000
          input:
            - text
            - image
          compat:
            thinkingFormat: deepseek
          reasoningEfforts:
            off:
            low: low
            high: high
            max: max
```
`agent-default-model` was maintained/restored as `tokenrhythm / glm-5.3-flash`.

### UI & Config Verification
- `dsh --profile web --dump-config`: Valid (exit 0).
- DSH Web UI (`http://127.0.0.1:3080`): Model selector for `DeepSeek V4.1 Flash` shows the Effort submenu with five levels: `Default`, `Off`, `Low`, `High`, `Max`. No schema errors or plugin failures.

### Wire Smoke Results
All four reasoning levels tested against `https://tokenrhythm.studio/v1` (`openai-completions`) using prompt: `简要回答：1+1等于几？`:
1. **Off**:
   - Status: HTTP 200, success.
   - Config: `reasoningEffort: "off"`.
   - Response: `2` (text block only, no reasoning block, outputTokens: 1).
   - Confirms thinking is disabled when `off` is selected.
2. **Low**:
   - Status: HTTP 200, success.
   - Config: `reasoningEffort: "low"`.
   - Response: `2` (outputTokens: 2, cacheReadTokens: 8192).
3. **High**:
   - Status: HTTP 200, success.
   - Config: `reasoningEffort: "high"`.
   - Response: `2` (outputTokens: 28; reasoning content block captured: *"The user asks a simple question in Chinese about what 1+1 equals, so I just need to provide a direct answer."*).
4. **Max**:
   - Status: HTTP 200, success.
   - Config: `reasoningEffort: "max"`.
   - Response: `2` (outputTokens: 2).

All levels are accepted by TokenRhythm without `UNSUPPORTED_REASONING_EFFORT` or parameter rejection.

---

## 3. MachineContext Synchronization
- Synced via `pwsh scripts/sync.ps1 -RepoRoot E:\MachineContext`.
- Canonical file `context/configs/ai/dsh.json` reflects the new `reasoningEfforts` (`high: "high"`, `low: "low"`, `max: "max"` per collector scalar projection).
- `pwsh scripts/validate.ps1` returned 0 errors, 0 warnings.
- All 52 MachineContext tests passed (`tests/run-tests.ps1`).
