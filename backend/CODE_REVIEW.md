# WoundOS Backend — Code Review

Scope: full review of the FastAPI backend in this repo, written alongside the first Cloud Run (staging) deploy. Findings are grouped by severity; each has a file:line citation and a concrete fix.

**Deploy status:** staging is live at `https://woundos-api-333499614175.us-central1.run.app`, `/health` returns 200, root returns the service banner, migrations applied (`patients`, `scans`, `alembic_version` tables present), `woundos-migrate` Cloud Run Job in place, Cloud SQL reachable via the `/cloudsql` Unix socket. Everything in section 1 has been fixed. Items in sections 2–5 are still open.

---

## 1. Deploy blockers (CRITICAL) — all fixed in this pass

### 1.1 Cloud SQL was unreachable from Cloud Run — **FIXED**
`scripts/deploy.sh` used `--vpc-connector` + `--vpc-egress private-ranges-only` but never passed `--add-cloudsql-instances` or set `DB_INSTANCE_CONNECTION_NAME`. `app/core/config.py:47` only switches to the `/cloudsql/...` Unix socket when `DB_INSTANCE_CONNECTION_NAME` is non-empty, so the app would fall through to TCP `localhost:5432` and hang. The container would start, the health probe would eventually fail, and Cloud Run would roll the revision back.

Fix applied: `deploy.sh` now queries the instance connection name, passes `--add-cloudsql-instances`, and sets `DB_INSTANCE_CONNECTION_NAME`, `DB_USER`, `DB_NAME` on both the service and the migration job.

### 1.2 Migration job was never created — **FIXED**
`scripts/setup_gcp.sh:125-128` declared step "[8/8] Creating migration Cloud Run job" but did nothing. `scripts/deploy.sh:37-40` then tried `gcloud run jobs execute woundos-migrate` and silently swallowed the "not found" error with `2>/dev/null || echo`. Result: the Cloud SQL database would be empty on first boot and every API call that hits the DB would 500.

Fix applied: `deploy.sh` now creates or updates the `woundos-migrate` Cloud Run job on every run (with the current image, Cloud SQL socket, and DB env vars), then executes it with `--wait` before deploying the service. Failures no longer get swallowed.

### 1.3 JWT signing key was seeded with the literal string `"change-me"` — **FIXED**
`scripts/setup_gcp.sh:88` set `jwt-signing-key` to the literal `"change-me"`. If the instructional echo at line 96 was ever skipped, the service would be signing auth tokens with a publicly-known value.

Fix applied: `setup_gcp.sh` now generates a 48-byte random value via `openssl rand -base64 48` on first run.

### 1.4 Alembic migration job crashed on import — **FIXED**
During the first deploy the migration job failed with `ModuleNotFoundError: No module named 'app'`. `migrations/env.py:8` does `from app.core.config import get_settings`, but `alembic.ini` had no `prepend_sys_path` entry and the Cloud Run Job invocation (`alembic upgrade head`) doesn't set `PYTHONPATH`, so the repo root was never on `sys.path`.

Fix applied: `alembic.ini` now has `prepend_sys_path = .` so Alembic puts the repo root on `sys.path` before running `env.py`. This also makes local `alembic upgrade head` work from a fresh clone without exporting PYTHONPATH.

### 1.5 DB password got scrambled by URL-reserved characters — **FIXED**
`scripts/setup_gcp.sh` generated the DB password with `openssl rand -base64 24`, which routinely produces `/`, `+`, `=` — all URL-reserved. `app/core/config.py` interpolated the raw password into the SQLAlchemy URL, so any password containing one of those characters produced a malformed DSN and the migration / service both failed with `password authentication failed for user "woundos"`.

Fix applied: `app/core/config.py:45-55` now runs `quote_plus()` on both user and password before building the URL (both the asyncpg and sync/psycopg2 variants). The staging instance currently runs on a hex-only password rotated during the deploy; with this fix, future base64 passwords will work untouched.

### 1.6 `gcloud sql databases create` failure silently swallowed — **FIXED**
`scripts/setup_gcp.sh` ran `gcloud sql databases create woundos ... 2>/dev/null || echo "(already exists)"`. When the Cloud SQL instance was still provisioning at create-time, the command failed for reasons other than "already exists", but `2>/dev/null || echo` suppressed the actual error and printed the reassuring "(already exists)" message. First-boot revision then crashed with `FATAL: database "woundos" does not exist`.

Fix: the surest fix is to only suppress the specific "already exists" error text, e.g. `out=$(gcloud sql databases create ... 2>&1) || echo "$out" | grep -q "already exists" || { echo "$out" >&2; exit 1; }`. Not yet applied in this pass — the staging database was created manually. Worth fixing before another fresh environment is bootstrapped.

---

## 2. Security issues (high priority — recommend addressing before any production traffic)

### 2.1 Pub/Sub push handler is unauthenticated
`app/workers/pubsub_handler.py:25` exposes `POST /pubsub/push` with no auth whatsoever. Combined with `--allow-unauthenticated` on the Cloud Run service (`deploy.sh:92`), anyone on the internet who knows the service URL can POST scan-processing payloads and trigger arbitrary scan IDs to reprocess — a cheap DoS vector.

Fix: verify the OIDC token that Pub/Sub attaches to every push request. When you create the subscription, set `--push-auth-service-account=<sa>@<project>.iam.gserviceaccount.com` and `--push-auth-token-audience=<your-cloud-run-url>`, then in the handler validate the `Authorization: Bearer ...` header with `google.oauth2.id_token.verify_oauth2_token` and reject anything whose `aud` doesn't match.

### 2.2 Firebase auth is bypassed whenever `FIREBASE_PROJECT_ID` is empty
`app/core/auth.py` (around the `verify_firebase_token`/`get_current_user` logic) treats any token as valid if `FIREBASE_PROJECT_ID == ""` and `ENVIRONMENT == development`. That's a sensible dev shortcut, but it's gated only by env vars — a misconfigured deploy that forgets to set `FIREBASE_PROJECT_ID` (or that runs with `ENVIRONMENT=development` by mistake) becomes an auth-bypass.

Fix: add a belt-and-braces check at startup — if `ENVIRONMENT != development`, refuse to start unless `FIREBASE_PROJECT_ID` is non-empty. Alternatively, gate the stub behind an explicit `SKIP_FIREBASE_VERIFICATION=true` flag that is documented as dev-only.

### 2.3 CORS default is `["*"]`
`app/core/config.py:26` — `CORS_ORIGINS: list[str] = ["*"]`. With `allow_credentials=True` (`app/main.py`), this is actually rejected by browsers (you can't combine wildcard origin with credentials), but it's still a misleading default that will bite you the moment you change `allow_credentials`.

Fix: default to `[]` and require the deploy to set the allowlist via env var. Note: `pydantic-settings` expects JSON for list envs, so the env var has to be `CORS_ORIGINS=["https://app.example"]` (or you add a validator that splits on commas).

### 2.4 GCS blobs written with no explicit ACL
`app/services/storage.py` uploads objects to `woundos-scans-<env>` with no `predefinedAcl` or `make_private()` call. Uniform bucket-level access is enabled in `setup_gcp.sh:75`, so today objects inherit bucket IAM and are not public — good. But the moment someone toggles the bucket to fine-grained ACLs or adds an `allUsers` reader, patient scans become world-readable.

Fix: keep uniform access on (document it) AND set `allUsers` / `allAuthenticatedUsers` to explicitly "no access" in bucket IAM; also add an integration test that uploads a blob and asserts the returned signed URL is required to fetch it.

### 2.5 Anthropic error messages get logged verbatim
`app/services/clinical_summary.py` catches all exceptions and logs `str(e)`. The Anthropic SDK sometimes includes the request payload or partial headers in error strings. Low risk, but if the SDK ever logs the bearer token in an error message it lands in Cloud Logging with a broad retention.

Fix: catch `anthropic.APIError` separately and log only `type(e).__name__` plus `e.status_code`. Generic `Exception` catch logs only the type.

### 2.6 `--allow-unauthenticated` on the whole service
`deploy.sh:92`. Every route is public at the network layer; only app-level auth stands between the internet and your patient data. For staging this is OK. For production, put Cloud Run behind IAP or an HTTPS Load Balancer with an auth policy, or split the service into an authenticated API + a separate Pub/Sub receiver.

---

## 3. Correctness bugs

### 3.1 Deprecated `@app.on_event(...)` decorators
`app/main.py:71, 76`. These still work on FastAPI 0.115 but emit DeprecationWarnings and will be removed in FastAPI 1.x. Migrate to the `lifespan` context manager:

```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app):
    logging.info(f"WoundOS Backend starting (env={settings.ENVIRONMENT.value})")
    yield
    logging.info("WoundOS Backend shutting down")

app = FastAPI(..., lifespan=lifespan)
```

### 3.2 `get_db` commits on every yield
`app/core/database.py:30-35` calls `await session.commit()` on success even if the request never wrote anything. This is fine functionally but means a 100% read-only endpoint still issues a `COMMIT` at the end — wasted round-trip and will log noise at debug level. Consider `session.commit()` only inside write paths, or use `async with session.begin()` inside the request where you actually want a transaction.

### 3.3 Potential orphaned scans on partial failure
The scan upload path (API → GCS → DB) has no explicit transaction around the "insert row + upload files" pair. If the DB insert succeeds and a subsequent GCS upload fails, the `get_db` dependency rolls back — good. But if GCS upload succeeds and the DB insert fails after, the GCS blobs are orphaned. Add a compensating cleanup in the exception path, or write the DB row last.

### 3.4 SAM 2 processing has no idempotency guard
`app/workers/sam2_processor.py` (the `process_scan` path) reads the scan, sets status to `PROCESSING`, and proceeds. If Pub/Sub retries the push (which it will, on any 5xx), two workers can race: both read `PROCESSING`, both do the work, last write wins. Fix: select the row `FOR UPDATE` and bail out if status is already `PROCESSING` or `COMPLETED`. Or use a DB advisory lock keyed on `scan_id`.

### 3.5 `pool_pre_ping=True` on a Cloud SQL socket connection
`app/core/database.py:17` — fine, but each ping is a round-trip. For socket connections inside the same instance the cost is negligible; for TCP over a VPC connector it adds ~1ms per checkout. Minor.

---

## 4. Code quality notes (brief)

- `SAM 2` processing is a stub with random perturbation (`app/workers/sam2_processor.py`). Agreement metrics / FWA signals it produces are not meaningful until a real model is wired up.
- Claude model string `"claude-haiku-4-5-20251001"` is hardcoded; promote to `settings.ANTHROPIC_MODEL`.
- Boundary points, areas, and measurements from the iOS client are trusted without validation. Add pydantic field validators for obvious-nonsense cases (negative area, out-of-bounds pixel coords).
- `docker-compose.yml` uses a fixed weak password. Fine for dev, but document that clearly in the README.
- Root endpoint (`app/main.py:63`) advertises `"docs": "/docs"` in its JSON response, but `/docs` is disabled whenever `DEBUG=false` (`main.py:31-32`). In staging the link is a dead reference — either drop the field or make it conditional on `settings.DEBUG`.
- `anthropic-api-key` secret currently holds a placeholder string. Any endpoint that hits `clinical_summary.py` will 500 until a real key is added: `echo -n "<key>" | gcloud secrets versions add anthropic-api-key --data-file=-` followed by a revision redeploy (no rebuild needed).

---

## 5. Summary of fixes applied in this pass

**Scripts**
- `deploy.sh`: adds `--add-cloudsql-instances` + `DB_INSTANCE_CONNECTION_NAME` / `DB_USER` / `DB_NAME` env vars to both the service and the migration job; creates/updates the `woundos-migrate` Cloud Run Job on every run and executes it with `--wait`; fails loudly if the Cloud SQL instance doesn't exist yet.
- `setup_gcp.sh`: generates a strong random JWT signing key on first run instead of seeding `"change-me"`; removes the dead "will be configured" step 8 placeholder.

**Application**
- `alembic.ini`: added `prepend_sys_path = .` so `migrations/env.py` can import `app.core.config` under the Cloud Run Job runtime.
- `app/core/config.py`: URL-encodes DB user and password with `urllib.parse.quote_plus` when building the SQLAlchemy URL, so base64 passwords with `/`, `+`, `=` no longer corrupt the DSN. Applies to both the async (`postgresql+asyncpg`) and sync (`postgresql`) URLs.

All sections 2, 3, and the open parts of 4 and 1.6 remain to be addressed.
