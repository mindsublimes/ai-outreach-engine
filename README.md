# AI Outreach Engine

A **standalone hobby project** for the AI outreach engine — siloed outside the main platform.

## Purpose

Proof of concept and functional integrity for AI-powered outreach. Once validated, this can be integrated into the admin dashboard. No front-end or admin panel integration for now — keeping it simple and independent.

## Setup

```bash
cd /home/dev/ai-outreach-engine
bundle install
bin/rails db:prepare
bin/rails partners_dna:seed   # Seed gold-standard partners
bin/dev   # Starts web server + Solid Queue workers (port 3001)
```

Or run separately:
```bash
bin/rails server -p 3001   # Terminal 1
bin/jobs start            # Terminal 2 (processes background jobs)
```

## Environment

Copy `.env.example` to `.env` and add your API keys:

- `OPENAI_API_KEY` — Required for research and email generation
- `FIRECRAWL_API_KEY` — Required for web scraping
- `ROCKETREACH_API_KEY` — Required for enrichment (email lookup)

## Usage

1. **Web UI**: Visit http://localhost:3001/prospects — add a URL to queue research
2. **Rake**: `rake partners_dna:research URL=https://www.mowmore.com` — run research synchronously
3. **Queue**: `rake partners_dna:queue URL=https://example.com` — queue full pipeline (research → enrichment → generation)

## Pipeline

1. **Research** — Firecrawl scrape → OpenAI extraction → SignatureDetector → LookAlikeScorer
2. **Enrichment** — RocketReach lookup for contact email
3. **Generation** — OpenAI email draft (subject + body)
4. **Gmail** — Create draft (optional, requires OAuth)

## Tech Stack

- Ruby 3.4.7, Rails 8.0.4
- SQLite3 (development), PostgreSQL (production)
- Solid Queue (background jobs)

## Deploy to Render

See [DEPLOYMENT.md](DEPLOYMENT.md) for step-by-step instructions. Client can test at your Render URL.

## Project Location

Lives at `/home/dev/ai-outreach-engine` — completely separate from the main `gp_v2_team` project.
