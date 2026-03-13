# Deploy AI Outreach Engine

## Option A: Railway (simplest — no credit card for trial)

**2 services total:** 1 app (web + jobs in one) + 1 Postgres. No separate worker.

### Steps

1. Go to [railway.app/new](https://railway.app/new) and sign in with GitHub (no card needed for trial).

2. **New Project** → **Deploy from GitHub repo** → select `mindsublimes/ai-outreach-engine`.

3. **Add PostgreSQL:** In the project, click **+ New** → **Database** → **PostgreSQL**.

4. **Set variables** on the app service (Variables tab):
   - `DATABASE_URL` → Click **Add Reference** → `Postgres` → `DATABASE_URL`
   - `RAILS_MASTER_KEY` → paste from `config/master.key`
   - `RAILS_ENV` → `production`
   - `SOLID_QUEUE_IN_PUMA` → `1` (runs jobs inside web process)
   - `OPENAI_API_KEY`, `FIRECRAWL_API_KEY`, `ROCKETREACH_API_KEY` (your keys)
   - Optional: `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN`, `GMAIL_FROM_EMAIL`

5. **Generate domain:** App service → **Settings** → **Networking** → **Generate Domain**.

6. **Seed partners** (first deploy): App service → **…** → **Run Command** → `bin/rails partners_dna:seed`.

### URLs

- App: `https://<your-app>.up.railway.app`
- Pipeline: `/pipeline` | Reviews: `/reviews` | Bulk Import: `/bulk_import`

---

## Option B: Render

## Prerequisites

- [Render](https://render.com) account
- GitHub/GitLab/Bitbucket repo with this code
- `config/master.key` (Rails credentials)

## Quick Deploy (Blueprint)

1. **Push** your code to GitHub/GitLab/Bitbucket.

2. **Connect** the repo to Render:
   - [Render Dashboard](https://dashboard.render.com/) → New → Blueprint
   - Select your repository

3. **Set `RAILS_MASTER_KEY`** when prompted:
   - Paste the contents of `config/master.key`

4. **Add environment variables** for `ai-outreach-web`:
   - Web service → Environment → Add variable

   | Key | Required | Notes |
   |-----|----------|-------|
   | `DATABASE_URL` | ✓ | Auto-set from Blueprint |
   | `RAILS_MASTER_KEY` | ✓ | Set at Blueprint creation |
   | `SOLID_QUEUE_IN_PUMA` | ✓ | Set to `1` (runs jobs in web process) |
   | `OPENAI_API_KEY` | ✓ | OpenAI API key |
   | `FIRECRAWL_API_KEY` | ✓ | Firecrawl API key |
   | `ROCKETREACH_API_KEY` | ✓ | RocketReach API key |
   | `GMAIL_CLIENT_ID` | Optional | Gmail OAuth |
   | `GMAIL_CLIENT_SECRET` | Optional | Gmail OAuth |
   | `GMAIL_REFRESH_TOKEN` | Optional | Gmail OAuth |
   | `GMAIL_FROM_EMAIL` | Optional | Sender email for drafts |

5. **Deploy** — Render will create:
   - PostgreSQL database (`ai-outreach-db`)
   - Web service (`ai-outreach-web`) — runs both web + background jobs (Solid Queue in Puma)

6. **Seed partners** (first deploy only): Use DBeaver or psql with the SQL from the project docs, or Shell → `bin/rails partners_dna:seed`

## URLs

- **Web**: `https://ai-outreach-web.onrender.com` (or your custom domain)
- **Pipeline**: `/pipeline`
- **Reviews**: `/reviews`
- **Bulk Import**: `/bulk_import`

## Client Testing

Share the web URL with your client. They can:

1. Go to **Bulk Import** → paste prospect URLs (max 50) → Start Research
2. Go to **Pipeline** → view status, retry failed
3. Go to **Reviews** → edit drafts, approve, push to Gmail

## Troubleshooting

- **Build fails**: Check `bin/render-build.sh` is executable (`chmod +x bin/render-build.sh`)
- **DB errors**: Ensure `DATABASE_URL` is set (from Blueprint database link)
- **Jobs not running**: Ensure `SOLID_QUEUE_IN_PUMA=1` is set on the web service
- **Gmail "Token expired or revoked"**: Run `bundle exec rake gmail:refresh_token` for instructions to get a new refresh token. Update `GMAIL_REFRESH_TOKEN` in Render and redeploy.
