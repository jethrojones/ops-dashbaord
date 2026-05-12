# Ops Dashboard Build Guide

This repository is a clean, public build guide for a Cloudflare-hosted operations dashboard. It is written so a developer or an LLM coding agent can build the dashboard from scratch without needing any private implementation, customer names, or API keys.

The finished app should be a private automation control center for a small team. It schedules and runs operational workflows, receives third-party webhooks, stores encrypted service credentials, records run history, writes detailed logs, and gives operators a clear place to see what ran, what failed, and what needs attention.

Use the design tokens in [glassline.md](glassline.md) as the starting visual direction. Before building, the agent should ask for design input using the questions in [Design Input](#design-input), then keep the Glassline defaults unless the user changes them.

## What To Build

Build a Cloudflare Workers application with:

- A private dashboard protected by Cloudflare Access.
- A workflow registry where each automation has an id, name, description, runtime, schedule, trigger metadata, required secrets, and enabled state.
- Scheduled workflow dispatch using Cloudflare Cron Triggers and Cloudflare Queues.
- Manual workflow runs from the dashboard.
- Webhook receivers for third-party services, kept outside Cloudflare Access but protected with service-specific signature verification.
- Run history with statuses, timing, error categories, log links, and filter/search.
- R2-backed structured logs for each workflow run.
- D1-backed relational state for workflows, schedules, runs, secrets metadata, audit logs, webhook events, settings, and deploy jobs.
- KV-backed short-lived cache for disposable data only.
- Durable Objects for workflow locks, usage counters, and webhook deduplication.
- A settings area for notification emails, service connections, API credential status, and operational preferences.
- An LLM-assisted workflow editing loop that can export a bounded edit payload, accept a paste-back response, validate file changes, create a GitHub branch/PR, and let CI verify changes before deployment.
- Tests for auth boundaries, scheduler behavior, queue execution, secret redaction, webhook signature checks, and paste-back validation.

Do not hard-code private organization names, personal emails, domains, account ids, database ids, namespace ids, bucket names, or API keys. Use placeholders and clear setup instructions instead.

## Recommended Stack

- Runtime: Cloudflare Workers with TypeScript.
- HTTP framework: Hono.
- Database: Cloudflare D1.
- Object storage: Cloudflare R2.
- Cache: Cloudflare KV.
- Queue: Cloudflare Queues.
- Coordination: Cloudflare Durable Objects.
- Auth: Cloudflare Access JWT validation.
- Email: Resend, Postmark, SendGrid, Mailgun, or another provider behind an adapter.
- Source control automation: GitHub REST API or a GitHub App.
- Tests: Vitest and Miniflare/Wrangler local development.
- Styling: server-rendered HTML with CSS, or React if the team wants a richer client. Keep the first version simple.

## Repository Files

- [README.md](README.md): the full build and setup guide.
- [docs/llm-build-prompt.md](docs/llm-build-prompt.md): a one-shot prompt someone can give to an LLM coding agent.
- [glassline.md](glassline.md): the tweakable starting design system with a YAML token block.
- [examples/wrangler.example.toml](examples/wrangler.example.toml): sanitized Cloudflare configuration.
- [examples/schema.example.sql](examples/schema.example.sql): starter D1 schema.
- [examples/package.example.json](examples/package.example.json): starter Node package scripts and dependency pins.
- [examples/tsconfig.example.json](examples/tsconfig.example.json): starter TypeScript config for Workers.
- [examples/ci.example.yml](examples/ci.example.yml): starter GitHub Actions workflow.
- [scripts/scan-secrets.sh](scripts/scan-secrets.sh): reusable high-confidence secret pattern scan.
- [.env.example](.env.example): local variable names only, with placeholder values.

## Design Input

Before writing frontend code, ask the project owner these questions:

1. Should the dashboard feel more like a dense internal control panel, a polished executive overview, or a hybrid?
2. Which views are used every day: run history, workflow list, failed runs, service health, or settings?
3. What is the primary action on the home screen: run a workflow, investigate failures, check status, or add/edit workflows?
4. What density is preferred: compact tables, spacious rows, or a split view with tables plus detail panels?
5. Are there brand colors, fonts, or accessibility requirements that should override [glassline.md](glassline.md)?
6. Should the UI support light mode only, dark mode only, or both?
7. Which users exist: owner, operator, developer, auditor, or read-only viewer?

If the owner does not answer, use Glassline as written: fog-grey neutrals, one cobalt action color, Geist typography, flat surfaces, no gradients, and one primary action per screen.

## Target User Experience

The home screen should answer five questions within a few seconds:

- Is the system healthy?
- What just ran?
- What failed?
- What is due next?
- Is usage close to a Cloudflare or third-party limit?

Recommended home layout:

- Top utility bar: app name, signed-in user, environment badge, settings link.
- Summary strip: healthy workflows, failed runs in the last 24 hours, queued runs, next scheduled run, usage warning.
- Main table: workflows with enabled state, last status, last run time, next run time, runtime, and quick actions.
- Side or lower panel: recent failures with error category, service, and a link to the run log.
- Footer: Cloudflare resource usage counters and current deployment version.

Avoid marketing-style hero sections. This is an operational tool, so prioritize scanning, comparison, and repeated action.

## Architecture

Use one Worker as the main application. It should export `fetch`, `scheduled`, and `queue` handlers:

- `fetch`: serves HTML pages, JSON APIs, health checks, and webhook endpoints.
- `scheduled`: runs on a Cloudflare cron trigger, finds due workflows, and enqueues work.
- `queue`: consumes workflow run messages, executes the workflow, writes logs, updates D1, sends failure notifications, and releases locks.

Recommended module structure:

```text
src/
  index.ts
  types.ts
  api/
    auth.ts
    workflows.ts
    runs.ts
    secrets.ts
    settings.ts
    deploy.ts
  frontend/
    layout.ts
    dashboard.ts
    workflow-detail.ts
    run-detail.ts
    runs-list.ts
    settings.ts
  lib/
    access-jwt.ts
    crypto.ts
    email.ts
    github.ts
    logging.ts
    rate-limits.ts
    scheduler.ts
    service-connectors.ts
    usage.ts
    validation.ts
  objects/
    WorkflowLock.ts
    UsageCounter.ts
    WebhookDedup.ts
  scripts/
    example-workflow/
      metadata.json
      script.ts
      script.test.ts
      README.md
      fixtures/
  migrations/
    0001_initial.sql
```

Keep service integrations behind adapters so new tools can be added without changing scheduler or queue execution logic.

## Cloudflare Resources

This app depends on several Cloudflare products. Each one has a specific job. Do not substitute one product for another without understanding the tradeoff.

### Workers

Workers run the application, API routes, cron handler, and queue consumer. Use Workers rather than Pages Functions for the first implementation because Workers support the full handler shape needed here, including scheduled events, queue consumers, Durable Objects, and explicit bindings in one deployment unit.

Needed:

- A Worker service name, for example `ops-dashboard`.
- A compatibility date. Cloudflare recommends current dates for new projects; pin it deliberately and bump only after tests pass on the newer runtime behavior.
- `nodejs_compat` only if dependencies need Node-compatible APIs. The example enables it because auth, JWT, GitHub, and email SDKs often import Node built-ins; remove it if the final dependency set is Workers-native.
- Wrangler configured locally and authenticated to the target Cloudflare account.

Common pitfalls:

- Cron triggers use UTC. Convert schedules explicitly.
- Worker CPU time is limited. Long or dependency-heavy jobs should dispatch to GitHub Actions, an external runner, or Cloudflare Workflows rather than run inline.
- Dynamic script imports must be bundleable. Keep workflows inside known directories or use a registry map.
- Do not put secrets in `wrangler.toml` under `[vars]`. Use Worker Secrets.
- Run `npx wrangler types` after changing bindings so the generated Env type matches real Cloudflare configuration.

### D1

D1 stores relational state:

- workflows/scripts
- schedules
- runs
- secrets metadata and encrypted blobs
- webhook event receipts
- audit logs
- deploy jobs
- settings
- usage snapshots if not stored entirely in Durable Objects

Create the database with Wrangler:

```bash
npm install
npx wrangler login
npx wrangler d1 create ops-dashboard
```

Copy the generated database id into `wrangler.toml`. The id is not an API key, but still avoid treating infrastructure ids as design content. Keep examples placeholder-based.

Apply migrations locally first:

```bash
npx wrangler d1 migrations apply ops-dashboard --local
```

Then apply them remotely:

```bash
npx wrangler d1 migrations apply ops-dashboard --remote
```

Why D1:

- It gives the dashboard queryable operational state.
- It supports relational constraints for workflows, schedules, runs, and audit history.
- It works well with Workers and Wrangler local development.

Pitfalls:

- `--local` and `--remote` are different databases. Confirm both are migrated.
- Do not store verbose logs in D1. Store only log object keys and summaries; put full logs in R2.
- Keep migration files append-only after production use. Add a new migration for changes.
- Use ISO timestamp strings consistently.

### R2

R2 stores large structured run logs and debug payloads:

```bash
npx wrangler r2 bucket create ops-dashboard-logs
```

Why R2:

- Run logs can grow larger than is comfortable for D1 rows.
- Operators need complete logs for debugging.
- R2 avoids tying long payloads to relational query performance.

Pitfalls:

- R2 must be enabled in the Cloudflare account before bucket creation.
- Logs must be redacted before writing. Never store plaintext API keys in logs.
- Store JSON logs with a predictable key such as `runs/{run_id}.json`.
- Consider lifecycle policies if logs contain sensitive operational data.

### KV

KV stores disposable, eventually consistent cache data:

```bash
npx wrangler kv namespace create CACHE
```

Why KV:

- It is good for cached service metadata, feature flags, and short-lived computed snapshots.
- It should not be the source of truth for workflow runs or locks.

Pitfalls:

- KV is eventually consistent. Do not use it for locks, counters that must be exact, or deduplication that must be strongly consistent.
- Create separate preview and production namespaces if you use preview environments.
- Cache keys should include a version prefix so schema changes can invalidate old values.

### Durable Objects

Use Durable Objects for strongly consistent per-entity coordination:

- `WorkflowLock`: prevents the same workflow from running twice at the same time.
- `UsageCounter`: tracks per-day resource counters and circuit-breaker thresholds.
- `WebhookDedup`: deduplicates webhook delivery ids.

Why Durable Objects:

- A workflow lock must be consistent.
- Webhook deduplication must survive concurrent deliveries.
- KV is not safe for these jobs.

Pitfalls:

- Durable Object classes need Wrangler migrations.
- Renaming classes after production deploys is painful. Pick stable names.
- Keep object state small and focused.

### Queues

Queues decouple scheduling/webhooks from execution:

```bash
npx wrangler queues create ops-dashboard-dispatch
npx wrangler queues create ops-dashboard-dispatch-dlq
```

Bind the same queue as a producer and consumer in the Worker. The scheduled handler and webhook routes publish messages; the queue handler executes them.

Why Queues:

- HTTP requests and cron handlers stay fast.
- Failed work is captured as a run record instead of disappearing in a request timeout.
- Batching and retry settings are explicit.
- A dead-letter queue preserves poison messages for inspection instead of deleting them permanently.

Pitfalls:

- Decide whether failed workflow execution should retry automatically. For many ops workflows, silent retries can duplicate side effects. A safer default is `max_retries = 0`: one delivery attempt, log the failure, send to the DLQ if the consumer itself fails, and let an operator rerun.
- Include an idempotency key in each message.
- Keep payloads small. Put large payloads in R2 and pass the R2 key.
- Add a DLQ consumer view or admin script so operators can inspect message ids, payload summaries, and failure timestamps.

### Cron Triggers

Use Cloudflare Cron Triggers to invoke the scheduler:

```toml
[triggers]
crons = ["*/1 * * * *"]
```

Why Cron Triggers:

- They wake the Worker without an external cron service.
- The scheduler can inspect D1 and enqueue only workflows that are due.

Pitfalls:

- Cron expressions are UTC.
- Every minute is the practical floor for near-real-time scheduling. Use `*/5 * * * *` or slower if workflows do not need one-minute resolution.
- Cloudflare trigger changes can take several minutes to propagate.
- If you use multiple cron expressions, inspect `controller.cron` to distinguish which fired.
- A schedule with `next_run_at = NULL` should be treated as disabled or not yet initialized.

### Cloudflare Access

Cloudflare Access protects the dashboard. All human dashboard routes and API routes should require a valid Access JWT. Webhook routes and health checks should bypass Access but must have their own protections.

Setup:

1. Go to Cloudflare Zero Trust.
2. Create a self-hosted Access application for the dashboard hostname.
3. Add allowed identity providers and policies.
4. Copy the Access application audience value.
5. Store it as a Worker Secret:

```bash
npx wrangler secret put CF_ACCESS_AUD
```

Implementation requirements:

- Verify Cloudflare Access JWTs server-side.
- Read the token from `Cf-Access-Jwt-Assertion` first. Browser requests may also have `CF_Authorization`, but the header is the better server-side validation source.
- Fetch signing keys from `https://<team-name>.cloudflareaccess.com/cdn-cgi/access/certs`.
- Cache JWKS keys with a TTL and refetch on unknown `kid`; Access signing keys rotate.
- Check issuer, audience, signature, and expiration.
- Extract the user email and subject for audit logs.
- Deny by default when headers are missing.
- Never trust `Cf-Access-Authenticated-User-Email` unless the JWT has already been verified.
- Do not protect `/webhooks/*` with Access; third-party services cannot complete browser login.

Starter Access verification sketch:

```ts
type AccessClaims = {
  aud: string | string[];
  email?: string;
  exp: number;
  iss: string;
  sub: string;
};

export async function requireAccess(request: Request, env: Env): Promise<AccessClaims> {
  const token =
    request.headers.get('Cf-Access-Jwt-Assertion') ??
    parseCookie(request.headers.get('Cookie') ?? '').CF_Authorization;

  if (!token) throw new Response('Unauthorized', { status: 401 });

  const jwksUrl = `https://${env.CF_TEAM_DOMAIN}.cloudflareaccess.com/cdn-cgi/access/certs`;
  const jwks = await getCachedJwks(jwksUrl);
  const claims = await verifyJwtWithJwks<AccessClaims>(token, jwks, {
    issuer: `https://${env.CF_TEAM_DOMAIN}.cloudflareaccess.com`,
    audience: env.CF_ACCESS_AUD,
  });

  if (!claims.sub || !claims.email) throw new Response('Unauthorized', { status: 401 });
  return claims;
}
```

Pitfalls:

- Access policy configuration is not enough by itself if routes are exposed through another domain or preview URL. Validate JWTs in the Worker too.
- Preview deployments may need their own Access application and audience.
- Keep `/healthz` boring and unauthenticated only if it returns no private data.

### Secrets

Use Worker Secrets for deployment-level secrets:

```bash
openssl rand -base64 32
npx wrangler secret put OPS_SECRETS_MASTER_KEY
npx wrangler secret put CF_ACCESS_AUD
npx wrangler secret put GITHUB_APP_PRIVATE_KEY
npx wrangler secret put GITHUB_APP_ID
npx wrangler secret put GITHUB_INSTALLATION_ID
npx wrangler secret put EMAIL_PROVIDER_API_KEY
```

Use the dashboard's encrypted secrets table for third-party service credentials that operators enter or rotate from the UI. Encrypt those values before writing to D1 using `OPS_SECRETS_MASTER_KEY`.

Credential encryption envelope:

- Use AES-GCM through Web Crypto.
- Generate a fresh 96-bit random IV/nonce for every encryption operation.
- Store ciphertext as base64 in `secrets.encrypted_blob`.
- Store IV as base64 in `secrets.encryption_iv`.
- Store an integer `encryption_version` so a future migration can rotate formats.
- Put metadata such as `service`, `status`, `last_checked_at`, and `last_rotated_at` in cleartext columns.
- Do not reuse an IV with the same key.

Rules:

- Never commit `.env`, `.dev.vars`, API keys, OAuth client secrets, private keys, webhook secrets, or service account JSON files.
- Redact secrets in logs by exact value and by common token patterns.
- Show credential status, last rotation time, and scopes in the UI, not credential values.
- Use separate credentials for development, staging, and production.
- Prefer GitHub Apps over broad personal access tokens for repository automation.

### Observability

Enable Worker logs and add structured application logs:

- Every run gets a D1 row.
- Every run gets an R2 JSON log.
- Every external API call logs service, endpoint label, status code, duration, and redacted error body.
- Every operator action writes an audit log row.
- Every webhook receipt stores service, event type, signature validity, routing decision, and run id if routed.

Add a footer or settings page that displays current Cloudflare resource usage and third-party quota warnings.

## Rate Limits And Backoff

Add rate limiting at three levels:

- Webhook ingress: limit by source IP, service, and delivery id. A misconfigured sender should not be able to enqueue thousands of runs.
- Operator actions: throttle manual runs and paste-back deploy attempts per user and workflow. Repeated clicks should collapse into one queued run or return a clear "already queued" response.
- Outbound APIs: use exponential backoff with jitter for 429 and transient 5xx responses. Respect `Retry-After` when providers send it.

Every workflow that writes to an external system should include an idempotency key derived from `run_id`, external object id, and action name.

## Example Cloudflare Setup Order

Run these from the project root after the app is scaffolded:

```bash
npm ci
npx wrangler login

npx wrangler d1 create ops-dashboard
# Paste the returned database_id into wrangler.toml.

npx wrangler r2 bucket create ops-dashboard-logs

npx wrangler kv namespace create CACHE
# Paste the returned id into wrangler.toml.

npx wrangler queues create ops-dashboard-dispatch

openssl rand -base64 32
npx wrangler secret put OPS_SECRETS_MASTER_KEY
npx wrangler secret put CF_ACCESS_AUD
npx wrangler secret put EMAIL_PROVIDER_API_KEY

npx wrangler d1 migrations apply ops-dashboard --local
npx wrangler d1 migrations apply ops-dashboard --remote

npm test
npm run typecheck
npx wrangler deploy
```

After deploy:

1. Configure the dashboard hostname and Cloudflare Access policy.
2. Confirm `/healthz` returns `OK`.
3. Confirm dashboard routes reject requests without Access headers.
4. Sign in through Cloudflare Access.
5. Add notification recipients.
6. Add service credentials in Settings.
7. Trigger a manual test workflow.
8. Confirm D1 run row, R2 log object, and audit log entry were written.
9. Trigger the local scheduled route during development with Wrangler before trusting production cron.

## Official Cloudflare References

Cloudflare changes product limits, command options, and configuration details over time. Before a final production deploy, verify the current docs:

- Workers configuration: <https://developers.cloudflare.com/workers/wrangler/configuration/>
- Worker Secrets: <https://developers.cloudflare.com/workers/configuration/secrets/>
- D1 Wrangler commands: <https://developers.cloudflare.com/d1/wrangler-commands/>
- D1 migrations: <https://developers.cloudflare.com/d1/reference/migrations/>
- KV namespaces: <https://developers.cloudflare.com/kv/concepts/kv-namespaces/>
- Queues configuration: <https://developers.cloudflare.com/queues/configuration/configure-queues/>
- Queue dead-letter queues: <https://developers.cloudflare.com/queues/configuration/dead-letter-queues/>
- Cron Triggers: <https://developers.cloudflare.com/workers/configuration/cron-triggers/>
- Scheduled handlers: <https://developers.cloudflare.com/workers/runtime-apis/handlers/scheduled/>
- Cloudflare Access: <https://developers.cloudflare.com/cloudflare-one/applications/>

## Data Model

Use [examples/schema.example.sql](examples/schema.example.sql) as the starter schema.

Important tables:

- `scripts`: registered workflows.
- `schedules`: cron metadata and next run time per workflow.
- `runs`: one row per execution attempt.
- `secrets`: encrypted credential blobs keyed by service.
- `webhook_events`: webhook receipts and routing decisions.
- `audit_log`: operator and system actions.
- `deploy_jobs`: LLM-assisted code edit jobs and PR status.
- `settings`: application-level settings.

Keep workflow metadata as JSON only for fields that are naturally flexible, such as `required_secrets`, `triggers`, and `params_schema`. Keep operational fields such as enabled state and runtime as typed columns.

Always use prepared statements for operator-controlled filters and search:

```ts
const rows = await env.DB.prepare(
  'SELECT * FROM runs WHERE script_id = ? AND status = ? ORDER BY started_at DESC LIMIT 50'
).bind(scriptId, status).all();
```

Never interpolate user input into SQL strings, including `ORDER BY`, date filters, and search terms. Map sort/filter options through an allow-list before building a query.

## Workflow Runtime Model

Support three runtime types:

- `worker`: runs directly in the queue consumer. Best for short TypeScript workflows with limited dependencies.
- `external`: dispatches GitHub Actions or another runner. Best for Python, Playwright, browser automation, long-running jobs, heavy SDKs, or tasks that need a full Linux environment.
- `workflow`: optional Cloudflare Workflows integration for multi-step durable jobs if the team wants it.

Each workflow directory should contain:

```text
scripts/{workflow_id}/
  metadata.json
  script.ts
  script.test.ts
  README.md
  fixtures/
    sample.json
```

Example `metadata.json`:

```json
{
  "id": "sync-crm-contacts",
  "name": "Sync CRM Contacts",
  "description": "Pulls changed contacts from the CRM and updates internal reporting tables.",
  "runtime": "worker",
  "default_schedule": "*/30 * * * *",
  "business_hours_only": false,
  "required_secrets": ["crm"],
  "triggers": [
    { "type": "cron", "enabled": true },
    { "type": "manual", "enabled": true }
  ],
  "params_schema": [
    {
      "key": "dry_run",
      "label": "Dry run",
      "type": "boolean",
      "default": true,
      "description": "Preview changes without writing to the external service."
    }
  ]
}
```

Workflow execution contract:

```ts
export interface WorkflowContext {
  scriptId: string;
  runId: string;
  secrets: Record<string, string>;
  log: (type: 'info' | 'api_call' | 'api_response' | 'error' | 'success', message: string, detail?: unknown) => void;
  db: D1Database;
  env: Env;
}

export async function run(ctx: WorkflowContext, payload?: unknown): Promise<void> {
  ctx.log('info', 'Workflow started');
}
```

Execution steps:

1. Insert a `runs` row with `status = 'running'`.
2. Acquire a Durable Object lock for the workflow id.
3. Load workflow metadata from D1.
4. Load and decrypt required secrets.
5. Execute the workflow.
6. Write structured logs to R2.
7. Update `runs` with status, duration, error category, and log key.
8. Release the lock.
9. Send a notification on failure or configured success conditions.

## Webhooks

Every webhook endpoint must have:

- A dedicated route: `/webhooks/{service}/{event}`.
- Signature or shared-secret verification.
- Deduplication using a delivery id, event id, or hash of the body.
- A route-to-workflow decision.
- A D1 `webhook_events` receipt.
- A Queue message for any actual work.

Do not trust webhook payloads. Validate shape and store the raw payload in R2 if it is needed for debugging.

Common verification patterns:

- HMAC signature header using the raw request body.
- Bearer token in `Authorization`.
- Shared secret header.
- Public-key signature verification.
- Provider-specific timestamp plus signature.

If a provider does not sign webhooks, generate a long random webhook URL token and treat it as a secret. Example route shape:

```text
/webhooks/generic/{service}/{event}/{unguessable_token}
```

Store the token as a Worker Secret or encrypted service secret, not in source code.

## API Keys And Service Connections

The dashboard should provide a Settings > Connections area where operators can add credentials. The UI should ask for the minimum fields needed by each service and explain required scopes. It should test credentials with a harmless read-only request before marking a connection healthy.

Never include real keys in docs, source, tests, fixtures, logs, screenshots, or issue reports.

### GitHub

Preferred: GitHub App.

1. Go to GitHub Developer settings.
2. Create a GitHub App for the organization or account.
3. Grant only the permissions needed, usually repository contents, pull requests, metadata, and workflows if dispatching Actions.
4. Install the app on the target repository.
5. Generate a private key.
6. Store app id, installation id, and private key as Worker Secrets.

Fallback: fine-grained personal access token.

1. Create a fine-grained token scoped to the target repo.
2. Grant only required repository permissions.
3. Set an expiration.
4. Store it as a Worker Secret.

Pitfalls:

- Classic PATs are often broader than necessary.
- GitHub App private keys are multiline PEM values; base64-encode them if your secret entry flow has trouble with newlines.
- Actions dispatch requires workflow permissions and the workflow file must already exist on the default branch.

### Google APIs

Use OAuth for acting on behalf of a human. Use a service account for server-to-server access where the resource can be shared with the service account.

Service account setup:

1. Create or select a Google Cloud project.
2. Enable the needed APIs, such as Drive, Sheets, Gmail, Calendar, or Admin SDK.
3. Create a service account.
4. Grant the service account access to the specific Drive folders, Sheets, or resources it needs.
5. Create a JSON key only if Workload Identity Federation is not practical.
6. Store the JSON as an encrypted service secret, not in Git.

OAuth setup:

1. Configure an OAuth consent screen.
2. Create OAuth client credentials.
3. Add redirect URI routes for the dashboard.
4. Request minimal scopes.
5. Store refresh tokens encrypted.

Pitfalls:

- Enabling an API in Google Cloud is separate from sharing a Drive folder.
- Domain-wide delegation requires Google Workspace admin approval.
- Gmail scopes can trigger app verification requirements.

### Microsoft Graph

1. Register an application in Microsoft Entra ID.
2. Add API permissions for the needed Graph resources.
3. Decide delegated permissions versus application permissions.
4. Create a client secret or certificate.
5. Grant admin consent when required.
6. Store tenant id, client id, and secret/certificate as secrets.

Pitfalls:

- Application permissions are powerful; keep scopes narrow.
- Some endpoints require admin consent even when code is correct.

### Slack

1. Create a Slack app.
2. Add bot token scopes.
3. Install it to the workspace.
4. Copy the bot token and signing secret.
5. Store both as secrets.
6. Verify slash commands and events using Slack's signing secret.

Pitfalls:

- Bot tokens and user tokens have different capabilities.
- Event subscriptions need a public URL and verification challenge handling.

### HubSpot

1. Create a private app in HubSpot.
2. Select only required CRM, automation, or object scopes.
3. Copy the private app access token.
4. Store the token encrypted.
5. Configure webhook subscriptions if needed and store any webhook secret.

Pitfalls:

- Scope changes may require token regeneration.
- Some CRM object access depends on account tier.

### Stripe

1. Use restricted API keys when possible.
2. Create separate test and live keys.
3. Configure webhook endpoints for the dashboard URL.
4. Store the API key and webhook signing secret separately.
5. Verify webhooks using the raw request body.

Pitfalls:

- Never mix test and live keys.
- Webhook verification fails if middleware consumes or modifies the raw body before signature verification.

### Shopify

1. Create a custom app in the Shopify admin.
2. Grant Admin API scopes.
3. Install the app.
4. Store access token and shop domain.
5. Verify webhooks with HMAC.

Pitfalls:

- Scopes are tied to installation.
- API versions are dated; update deliberately.

### Airtable

1. Create a personal access token.
2. Scope it to specific bases and permissions.
3. Store base ids and table ids as non-secret configuration.
4. Store the token as an encrypted secret.

Pitfalls:

- Base ids are not secrets, but avoid hard-coding private business names in public examples.
- Rate limits are easy to hit with row-by-row updates; batch where possible.

### Notion

1. Create an internal integration.
2. Copy the integration secret.
3. Share the target pages/databases with the integration.
4. Store database ids as config and the secret encrypted.

Pitfalls:

- Creating an integration is not enough; each page/database must be shared.
- Property names can change. Prefer property ids where possible.

### Email Providers

Resend, Postmark, SendGrid, Mailgun, and Amazon SES all work. Hide provider differences behind an email adapter:

```ts
interface EmailProvider {
  send(message: {
    to: string[];
    from: string;
    replyTo?: string;
    subject: string;
    text: string;
    html?: string;
    tags?: Record<string, string>;
    idempotencyKey?: string;
  }): Promise<void>;
}
```

For v1, delivery can be fire-and-forget after the provider accepts the message. If bounced email, complaint handling, or inbound replies matter, add provider-specific webhook receivers and store delivery events in D1 with the provider name, provider message id, event type, and timestamp.

Setup pattern:

1. Verify the sending domain.
2. Add required DNS records.
3. Create an API key with sending permission.
4. Store it as a Worker Secret.
5. Send a test notification to an allowed recipient.

Pitfalls:

- DNS verification can take time.
- Some providers sandbox new accounts.
- Do not allow arbitrary recipients unless that is intentional.

### CRM And Sales Tools

For Salesforce, Pipedrive, Close, Apollo, Instantly, Outreach, Salesloft, and similar services:

1. Find the developer or API settings area.
2. Prefer OAuth or a scoped private app over a global user API key.
3. Document exact scopes.
4. Store account/base/workspace ids as configuration.
5. Store tokens encrypted.
6. Build a health check that makes a harmless read request.

Pitfalls:

- Some tools rotate or hide tokens after creation.
- Some tools rate-limit aggressively.
- Some APIs return partial success responses; log item-level failures.

### Document Signing And Forms

For DocuSign, Dropbox Sign, PandaDoc, DocuSeal, Typeform, Jotform, Fillout, and similar services:

1. Create an API app or token.
2. Configure webhook endpoint URLs.
3. Store webhook signing secrets.
4. Verify all webhook events.
5. Build idempotency around submission ids or envelope ids.

Pitfalls:

- Webhook retries can arrive out of order.
- Test mode and production mode often use separate credentials.

### AI Providers

For OpenAI, Anthropic, Google AI, Groq, Mistral, Cohere, and similar services:

1. Create a project-level API key.
2. Set spend limits where available.
3. Restrict keys by project or environment when supported.
4. Store keys as Worker Secrets or encrypted service secrets.
5. Log model name, token counts, latency, and cost estimates, but never prompts containing private secrets unless explicitly needed and redacted.

Pitfalls:

- Some provider SDKs rely on Node APIs that may not run in Workers. Use `fetch` or verify Worker compatibility.
- Add retry with backoff for 429s.
- Keep prompt logs opt-in.

### Unknown Or Niche Services

When integrating a service that is not well-known:

1. Search for official API docs, developer settings, webhooks, OAuth, API tokens, and rate limits.
2. Identify the authentication method.
3. Identify the least-privilege scope or account role.
4. Find webhook signing docs.
5. Find pagination, retry, and rate-limit behavior.
6. Create a connector file named after the service.
7. Add a health check.
8. Add fixtures with sanitized responses.
9. Add tests for auth failure, rate limit, pagination, and malformed responses.
10. Document how to rotate credentials.

If docs are weak, treat the integration as unstable:

- Add extra logging.
- Keep writes behind dry-run mode first.
- Require manual approval before destructive actions.
- Build idempotency into every write.

## Services Without Official APIs

Some tools do not offer official APIs. Prefer safer alternatives before automation:

1. CSV export/import.
2. Email forwarding to a parser.
3. IMAP mailbox polling.
4. SFTP drop folders.
5. Zapier, Make, Pipedream, or n8n as a bridge.
6. Webhooks from an adjacent service.
7. Browser automation as a last resort.

### Email Parsing

Use a dedicated mailbox, not a person's primary inbox.

- Create a mailbox such as `ops-automation@example.com`.
- Route relevant notifications there.
- Poll with Gmail API, Microsoft Graph, or IMAP.
- Parse only known senders and known subject/body formats.
- Store message ids for deduplication.
- Preserve raw messages in R2 only when needed, and redact sensitive content.

### CSV Or File Drops

- Define an expected schema.
- Validate headers before import.
- Store original files in R2.
- Write import results to D1.
- Make imports idempotent using file hash plus row ids.

### Browser Automation

Use browser automation only when permitted by the service terms and when no better integration exists.

Recommended runtime:

- GitHub Actions, a small external worker, or another runner with Playwright installed.
- Do not run heavy browser automation inside the main Worker.
- Dispatch from the dashboard and report status back through a callback endpoint.

Safety rules:

- Use a dedicated automation account.
- Enable MFA-compatible automation only if the provider supports it.
- Store session state securely and rotate it.
- Add rate limits and human review before destructive actions.
- Screenshot failures to a private artifact store, not a public issue.
- Expect UI selectors to break and write clear failure messages.

## LLM-Assisted Edit Loop

The dashboard can include a controlled way to let an LLM edit workflow code.

Recommended flow:

1. Operator opens a workflow and clicks "Prepare edit".
2. App creates an edit payload containing:
   - workflow id
   - current metadata
   - current source files
   - recent redacted run logs
   - failing test output if available
   - allowed file paths
   - exact response envelope format
3. Operator gives that payload to an LLM coding agent.
4. LLM returns a structured patch or full-file response in a sentinel envelope.
5. Operator pastes the response back into the dashboard.
6. App validates:
   - sentinel markers exist
   - JSON parses
   - workflow id matches
   - files stay under `scripts/{workflow_id}/`
   - no `.env`, private keys, or binary files
   - no dangerous runtime patterns such as `eval`
   - tests are included or updated when behavior changes
7. App creates a GitHub branch and PR.
8. CI runs tests.
9. Human or automation merges only after checks pass.

Never allow pasted LLM output to deploy directly to production without containment checks and CI.

Concrete paste-back limits:

- Max single file size: 200 KB.
- Max total payload size: 1 MB.
- Allowed extensions: `.ts`, `.json`, `.md`, `.sql`, and `.txt`.
- Allowed root: `scripts/{workflow_id}/` only, unless an administrator explicitly starts a global edit job.
- Reject absolute paths, `..`, symlinks, NUL bytes, and files with binary extensions.
- Reject `.env`, `.dev.vars`, `.pem`, `.key`, `.p12`, `.pfx`, `.sqlite`, `.db`, screenshots, archives, and generated logs.
- Reject these code patterns in workflow edits unless a human administrator overrides them after review: `eval(`, `new Function(`, `child_process`, `node:child_process`, `require('fs')`, `require("fs")`, `node:fs`, non-literal dynamic imports, and writes outside the workflow directory.
- Reject new dependencies in workflow paste-back by default. Dependency changes should go through a normal PR.
- Run the secret scanner and workflow tests before creating or updating the PR.

## Security Requirements

Implement these from day one:

- Deny-by-default auth on dashboard routes.
- Separate unauthenticated webhook routes with signature verification.
- Encrypt service credentials before writing to D1.
- Use Worker Secrets for master keys and deployment-level credentials.
- Redact secrets from all logs.
- Keep audit logs for settings changes, secret rotations, workflow edits, manual runs, reruns, and deploy actions.
- Add CSRF protection for state-changing form posts if using cookie/browser sessions.
- Set secure headers: `Content-Security-Policy`, `X-Frame-Options` or `frame-ancestors`, `Referrer-Policy`, and `X-Content-Type-Options`.
- Validate all JSON payloads.
- Use idempotency keys for writes to external systems.
- Avoid storing raw personal data unless required.

Starter security headers for server-rendered HTML:

```http
Content-Security-Policy: default-src 'self'; base-uri 'self'; frame-ancestors 'none'; object-src 'none'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; form-action 'self'; upgrade-insecure-requests
Referrer-Policy: no-referrer
X-Content-Type-Options: nosniff
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

Avoid `unsafe-eval`. Use nonces or external bundled scripts if inline JavaScript grows beyond tiny progressive-enhancement handlers.

## Testing Checklist

Minimum tests:

- Unauthenticated dashboard request is rejected.
- `/healthz` is public and returns no private data.
- Webhook route rejects missing or bad signature.
- Valid webhook inserts receipt and enqueues exactly one message.
- Duplicate webhook delivery is ignored.
- Scheduler enqueues due workflows.
- Scheduler skips disabled workflows.
- Scheduler skips workflows already locked.
- Queue consumer writes success run status and R2 log.
- Queue consumer writes failed run status, error category, and notification.
- Secret values are redacted from logs.
- Credential health checks do not leak tokens in error messages.
- Paste-back validator rejects path traversal.
- Paste-back validator rejects files outside the selected workflow.
- D1 migrations apply locally.
- TypeScript typecheck passes.

Recommended commands:

```bash
npm run typecheck
npm test
npx wrangler d1 migrations apply ops-dashboard --local
npx wrangler dev --test-scheduled
```

## CI/CD

Use GitHub Actions:

- install dependencies with `npm ci`
- run typecheck
- run tests
- run secret scan with `bash scripts/scan-secrets.sh .`
- optionally run Wrangler deploy on main

Use [examples/ci.example.yml](examples/ci.example.yml) as the starting workflow. Copy it to `.github/workflows/ci.yml` in the generated app.

Deployment options:

- Manual deploy: `npx wrangler deploy`
- GitHub Actions deploy using a Cloudflare API token stored in GitHub Actions secrets
- Cloudflare dashboard deploy integration if the repo is connected

GitHub Actions secrets commonly needed:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Do not store third-party service credentials in GitHub Actions unless CI actually needs them. The production Worker should receive runtime secrets through Cloudflare.

## Secret Scanning Before Public Release

Before making the repo public:

```bash
bash scripts/scan-secrets.sh .
PRIVATE_PATTERNS='(private-org-name|private-domain|private-email|private-client-name)' bash scripts/scan-secrets.sh .
git status --short
```

The script works with `rg` when available and falls back to `grep`. For stronger coverage, add a dedicated scanner such as Gitleaks or TruffleHog in CI, but keep this script as the fast local baseline.

Also inspect:

- `.env`
- `.dev.vars`
- `wrangler.toml`
- test fixtures
- screenshots
- generated logs
- copied source comments
- package names

The public repo should contain placeholders only.

## Build Pitfalls To Avoid

- Do not copy private source configuration into the public repo.
- Do not include Cloudflare account ids, database ids, KV ids, bucket names from private projects, real domains, or real emails.
- Do not rely on KV for workflow locks.
- Do not store full logs in D1.
- Do not let webhooks bypass verification.
- Do not assume cron runs in local time.
- Do not run long browser automation inside a Worker.
- Do not let LLM paste-back write outside a workflow directory.
- Do not commit generated `.wrangler` state.
- Do not use production API keys for local development.
- Do not show secret values after save.
- Do not send failure notifications with raw unredacted payloads.
- Do not allow automatic reruns for non-idempotent workflows unless the workflow explicitly supports them.

## One-Shot Build Instruction

Give an LLM coding agent this repository and say:

```text
Build the ops dashboard described in README.md. Use glassline.md as the default design system. Ask the design input questions first unless I tell you to use the defaults. Scaffold a Cloudflare Workers TypeScript app using Hono, D1, R2, KV, Durable Objects, Queues, Cloudflare Access auth, and Vitest. Use examples/wrangler.example.toml and examples/schema.example.sql as the starting point, but generate real resource ids only through Wrangler commands and never hard-code API keys. Implement tests for the required checklist before claiming completion.
```

For a longer prompt with acceptance criteria, use [docs/llm-build-prompt.md](docs/llm-build-prompt.md).

## Public Repo Safety Statement

This repository intentionally contains no real API keys, no private service credentials, no private domain configuration, and no organization-specific implementation details. All identifiers are placeholders meant to be replaced by the person building their own dashboard.
