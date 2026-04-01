**Frontend integration guidance**

# Backend contract first

- Treat `AI-bot/server/services/app_runtime.py` as the protocol source of truth.
- Production HTTP requests must use `/api/app/v1/...`.
- Production realtime updates must use `/ws/app/v1/events`.
- Parse the server envelope shape `{ ok, data, error, request_id, ts }` before any page-level logic.
- Keep JSON field names aligned with backend `snake_case` in transport, then map to frontend-friendly names locally.

# Authentication and connection

- Use `Authorization: Bearer <token>` for HTTP when a token is present.
- Send the same token through `X-App-Token` for backend compatibility.
- Pass the token to WebSocket through `?token=<token>`.
- Persist `host`, `port`, `token`, `current_session_id`, and `latest_event_id` locally so reconnect can resume.
- Connect flow must be `GET /api/health` -> `GET /api/app/v1/bootstrap` -> WebSocket attach.

# Chat rules

- User messages go through `POST /api/app/v1/sessions/{session_id}/messages`.
- Do not fetch assistant replies from OpenAI, Anthropic, Gemini, or any frontend model SDK.
- Render the returned `accepted_message` as pending immediately.
- Promote assistant UI state only from event stream messages:
  - `session.message.created`
  - `session.message.progress`
  - `session.message.completed`
  - `session.message.failed`

# Home and control rules

- Dashboard data must come from `bootstrap.runtime`, `GET /api/app/v1/runtime/state`, and WebSocket events.
- Only expose device actions that the backend currently implements.
- If a legacy frontend action has no backend route, replace it with a clear placeholder instead of a fake request.
- Keep todo and calendar summaries visible when the backend reports them as enabled.

# Settings, tasks, and events

- Settings must be backend-managed. The frontend cannot persist provider SDK clients or use model secrets directly.
- "Test AI Connection" must call the backend endpoint, not a direct vendor API.
- For unfinished backend endpoints, normalize `404`, `501`, and `NOT_IMPLEMENTED` into a single "backend not ready" UI state.
- Preserve navigation entry points even when an endpoint is not ready, but disable unsafe actions and explain why.

# Demo mode

- Demo mode must stay available for UI exploration.
- Demo mode must be completely isolated from production protocol code.
- Demo data can mimic backend shapes, but it must not leak into real API calls or event handlers.

# UI expectations

- Keep layouts mobile-friendly and avoid fake data labels that imply a real backend call happened.
- Prefer explicit status messaging over silent failure.
- When event stream resume is rejected, refetch bootstrap and rebuild page state from the backend.
