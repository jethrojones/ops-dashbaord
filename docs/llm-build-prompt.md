# LLM Build Prompt

Use this prompt with an LLM coding agent to build the ops dashboard from scratch.

```text
You are building a private operations dashboard from a clean public specification. Do not copy private source code from any other project. Do not invent or include real API keys. Use placeholders in examples, and use Cloudflare Worker Secrets or encrypted database storage for credentials.

First, ask these design questions:
1. Should the dashboard feel more like a dense internal control panel, a polished executive overview, or a hybrid?
2. Which views are used every day: run history, workflow list, failed runs, service health, or settings?
3. What is the primary action on the home screen: run a workflow, investigate failures, check status, or add/edit workflows?
4. What density is preferred: compact tables, spacious rows, or a split view with tables plus detail panels?
5. Are there brand colors, fonts, or accessibility requirements that should override glassline.md?
6. Should the UI support light mode only, dark mode only, or both?
7. Which users exist: owner, operator, developer, auditor, or read-only viewer?

If I do not answer, use glassline.md as the starting design system.

Build a Cloudflare Workers TypeScript app with Hono. The Worker must export fetch, scheduled, and queue handlers. Use D1 for relational state, R2 for structured run logs, KV for disposable cache, Durable Objects for workflow locks/usage counters/webhook deduplication, Queues for workflow dispatch, Cron Triggers for scheduling, and Cloudflare Access for dashboard authentication.

Create this structure:

src/
  index.ts
  types.ts
  api/auth.ts
  api/workflows.ts
  api/runs.ts
  api/secrets.ts
  api/settings.ts
  api/deploy.ts
  frontend/layout.ts
  frontend/dashboard.ts
  frontend/workflow-detail.ts
  frontend/run-detail.ts
  frontend/runs-list.ts
  frontend/settings.ts
  lib/access-jwt.ts
  lib/crypto.ts
  lib/email.ts
  lib/github.ts
  lib/logging.ts
  lib/rate-limits.ts
  lib/scheduler.ts
  lib/service-connectors.ts
  lib/usage.ts
  lib/validation.ts
  objects/WorkflowLock.ts
  objects/UsageCounter.ts
  objects/WebhookDedup.ts
  scripts/example-workflow/metadata.json
  scripts/example-workflow/script.ts
  scripts/example-workflow/script.test.ts
  scripts/example-workflow/README.md
  migrations/0001_initial.sql

Implement:
- private dashboard routes protected by Cloudflare Access JWT validation
- public /healthz route with no private data
- public /webhooks/:service/:event routes protected by service-specific signature checks
- workflow registry CRUD
- manual workflow runs
- scheduler that enqueues due workflows and skips disabled or locked workflows
- queue consumer that executes workflows, writes D1 run rows, writes R2 logs, categorizes errors, sends failure email, and releases locks
- Settings > Connections for service credential status and encrypted credential entry
- encrypted secrets table using OPS_SECRETS_MASTER_KEY from Worker Secrets
- audit logs for state-changing actions
- usage counters and circuit breaker warnings
- LLM-assisted workflow edit loop with strict paste-back validation, GitHub branch/PR creation, and CI handoff

Use these runtime types:
- worker: short TypeScript workflows run inside the queue consumer
- external: dispatch GitHub Actions or another runner for long, browser, Python, or heavy dependency jobs
- workflow: optional Cloudflare Workflows integration if implemented

Security requirements:
- never log secret values
- redact tokens and known secret values from logs
- keep dashboard auth deny-by-default
- verify Cloudflare Access JWTs from Cf-Access-Jwt-Assertion using the Access JWKS endpoint; do not trust identity headers without JWT verification
- verify webhook raw bodies before parsing when the provider requires it
- use idempotency keys for external writes
- use Durable Objects, not KV, for locks and deduplication
- do not store full run logs in D1
- do not allow LLM paste-back files outside scripts/{workflow_id}/
- reject path traversal, binary files, .env files, private keys, eval-like code, filesystem/child-process access, oversized files, and non-allowed extensions in paste-back
- use prepared D1 statements with bind values; never interpolate operator input into SQL
- encrypt service credentials with AES-GCM using a unique IV per value and store the IV separately from ciphertext

Cloudflare setup:
- if CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, CF_ACCESS_AUD, APP_DOMAIN, email secrets, and GitHub App secrets are already available, follow README.md "One-Shot Non-Interactive Setup" and do not stop for browser login
- if those values are missing, stop and ask for the missing prerequisites instead of inventing them or disabling auth
- create D1 database with npx wrangler d1 create ops-dashboard
- create R2 bucket with npx wrangler r2 bucket create ops-dashboard-logs
- create KV namespace with npx wrangler kv namespace create CACHE
- create Queue with npx wrangler queues create ops-dashboard-dispatch
- create DLQ with npx wrangler queues create ops-dashboard-dispatch-dlq
- configure Durable Object migrations
- configure cron triggers in wrangler.toml
- set Worker Secrets with npx wrangler secret put
- apply D1 migrations locally and remotely
- deploy with npx wrangler deploy

Write tests before claiming completion:
- unauthenticated dashboard requests reject
- /healthz succeeds publicly
- webhooks reject bad signatures
- valid webhooks dedupe and enqueue once
- scheduler enqueues due workflows
- scheduler skips disabled workflows
- scheduler skips locked workflows
- queue consumer records success and writes R2 log
- queue consumer records failure, categorizes error, sends notification, writes R2 log
- secret redaction removes exact values and token patterns
- paste-back validator rejects path traversal and out-of-scope files
- paste-back validator rejects forbidden code patterns and oversized files
- script secret scan passes with bash scripts/scan-secrets.sh .
- D1 migrations apply locally
- typecheck passes

Use README.md as the product and setup specification. Use examples/wrangler.example.toml, examples/schema.example.sql, examples/package.example.json, examples/tsconfig.example.json, and examples/ci.example.yml as sanitized starting points. When resource ids are needed, tell me to run Wrangler commands and paste the generated ids into local config. Do not create fake real-looking keys.
```
