# Research: Dual-Mode Sessions

## Decision: Use stream-json CLI protocol directly via typed-process

### Rationale

The claude CLI natively supports structured I/O via `--output-format stream-json --input-format stream-json`. The daemon can spawn the claude process with `typed-process`, write JSON to stdin, and read NDJSON from stdout — no SDK dependency needed.

### Claude CLI Flags

**Structured mode invocation:**
```
claude -p \
  --output-format stream-json \
  --input-format stream-json \
  --verbose \
  --dangerously-skip-permissions \
  --resume <session-id>
```

- `-p` / `--print`: non-interactive mode (required for stdin/stdout I/O)
- `--verbose`: required when using `--output-format stream-json`
- `--dangerously-skip-permissions`: bypasses all permission prompts
- `--resume <session-id>`: resumes conversation history from a previous session

### Stream-JSON Protocol

**Output (stdout)** — newline-delimited JSON, one object per line:

| `type` | When | Key fields |
|--------|------|------------|
| `system` (subtype `init`) | First line | `session_id`, `tools[]`, `model` |
| `assistant` | Complete turn | `message.content[]`, `session_id` |
| `result` | End of run | `result`, `is_error`, `duration_ms`, `total_cost_usd` |

**Input (stdin)** — newline-delimited JSON:

```json
{"type":"user","session_id":"","message":{"role":"user","content":"prompt text"},"parent_tool_use_id":null}
```

### Session ID Management

The `system/init` event returns a `session_id` UUID. This must be captured on first run and passed to `--resume` on subsequent runs (mode switches). The session ID is distinct from the daemon's `SessionId` — it's the claude conversation ID.

### Permission Bypass

`--dangerously-skip-permissions` is sufficient. No need for `--permission-prompt-tool` or control_response messages on stdin. This eliminates the entire permission callback complexity.

### Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| claude-agent-sdk (Python) | Full SDK | Python dependency, overkill |
| MCP protocol | Standard | Wrong level of abstraction |
| **CLI stream-json** | Native, no deps, typed-process | Must parse NDJSON ourselves |

### Response Streaming to HTTP Clients

**Decision: Server-Sent Events (SSE)**

SSE is a natural fit: unidirectional server→client stream over HTTP. The daemon reads NDJSON lines from the claude process stdout and forwards each as an SSE event. Clients connect with `EventSource` or `curl`.

Alternative (WebSocket) is more complex and bidirectional capability isn't needed for prompt responses.
