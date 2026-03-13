# Deploy AI Outreach Engine to Render

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

4. **Add environment variables** for both `ai-outreach-web` and `ai-outreach-jobs`:
   - In each service → Environment → Add variable

   | Key | Required | Notes |
   |-----|----------|-------|
   | `DATABASE_URL` | ✓ | Auto-set from Blueprint |
   | `RAILS_MASTER_KEY` | ✓ | Set at Blueprint creation |
   | `OPENAI_API_KEY` | ✓ | OpenAI API key |
   | `FIRECRAWL_API_KEY` | ✓ | Firecrawl API key |
   | `ROCKETREACH_API_KEY` | ✓ | RocketReach API key |
   | `GMAIL_CLIENT_ID` | Optional | Gmail OAuth |
   | `GMAIL_CLIENT_SECRET` | Optional | Gmail OAuth |
   | `GMAIL_REFRESH_TOKEN` | Optional | Gmail OAuth |
   | `GMAIL_FROM_EMAIL` | Optional | Sender email for drafts |

5. **Deploy** — Render will create:
   - PostgreSQL database (`ai-outreach-db`)
   - Web service (`ai-outreach-web`)
   - Background worker (`ai-outreach-jobs`)

6. **Seed partners** (first deploy only):
   - Web service → Shell → `bin/rails partners_dna:seed`

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
- **Jobs not running**: Verify `ai-outreach-jobs` service is running and has same env vars as web
