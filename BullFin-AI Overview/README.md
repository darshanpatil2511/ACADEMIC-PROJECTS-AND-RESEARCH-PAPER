# BullFin-AI

> Your portfolio, finally understood.

**🔗 Live demo: [bullfin-ai.com](https://www.bullfin-ai.com)**

BullFin-AI turns a CSV of holdings into a live analytics dashboard: every metric a quant desk runs on, a five-year forecast on every position, and an AI advisor that reads your portfolio before you ask it a question. Built as a full-stack production application — authentication, per-user data isolation, real market data, AI-generated reports, responsive on every device.

> **About this repository**
> This is a showcase / case-study repo. BullFin-AI's source lives in a private repository; this public repo documents the architecture, feature set, and engineering decisions for anyone evaluating the project (recruiters, collaborators, etc.). Try it live at the link above — happy to walk through the code directly on request.

---

## Table of contents

- [What's inside](#whats-inside)
- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Repository layout](#repository-layout)
- [Engineering notes](#engineering-notes)
- [Further reading](#further-reading)
- [License](#license)

---

## What's inside

### Dashboard & portfolios
- CSV upload **or** manual entry of positions (symbol, shares, cost basis, purchase date)
- Multiple portfolios per account — rename and delete inline from the grid
- Selection sticks across Dashboard / Analyze / Forecast / Reports / Advisor, and survives reloads
- Annualized CAGR, volatility, Sharpe, Sortino, Jensen's alpha, Beta vs. the chosen benchmark
- Max drawdown, 1-day 95% Value-at-Risk, HHI-based diversification index
- Sector exposure breakdown, live benchmark overlay
- Plain-English **risk score** (0–100) labeled Conservative → Speculative

### AI advisor
- Context-aware chat — your holdings and computed metrics are loaded into the conversation
- Streaming responses, full session history per account
- Handles "what-if" scenarios ("what happens if I cut tech exposure by 20%?")
- Quantifies tradeoffs and flags risks; stops short of buy/sell recommendations

### Forecast
- Geometric Brownian Motion fit on up to 15 years of real prices, 1,000 simulated futures per stock
- Per-holding card with median forecast line + 10th–90th percentile cone
- Configurable horizon (1 week → 5 years) and training window
- Latest headlines per ticker, fetched live

### Analyze
- 5,000-path Monte Carlo simulation with optional annual contribution
- Efficient Frontier (Modern Portfolio Theory) — max-Sharpe and min-volatility portfolios highlighted
- Adjustable lookback window so you can see how recent vs. long-term data shifts the curve

### Reports
- One-click PDF with KPIs, performance chart, holdings table, sector exposure, risk score, and an AI-written executive summary
- Stored in a private per-user bucket, accessible only through short-lived signed URLs

### Account & settings
- Email/password and Google OAuth sign-in
- Dark / light / system theme
- Configurable default benchmark (SPY, QQQ, VTI, VT, AGG) and compact number formatting
- Avatar upload, display-name edit, password reset
- Full data export (portfolios, holdings, reports metadata, chat sessions) as JSON
- Self-serve account deletion — wipes auth, database, and storage immediately

### Engineering foundations
- Per-user data isolation enforced at the database layer — even an API bug cannot leak another user's portfolios
- Typed end-to-end (TypeScript for web + API, Pydantic for the quant engine)
- Every request body validated with Zod / Pydantic
- `prefers-reduced-motion` and touch-device detection on the landing animations
- Mobile-first layout, responsive from phone to 4K

---

## Architecture

```
┌─────────────────┐      ┌──────────────────┐      ┌────────────────────┐
│  apps/web       │◀────▶│   apps/api       │◀────▶│   apps/ml          │
│  React + Vite   │ HTTP │   Express + TS   │ HTTP │   FastAPI (Python) │
│  TypeScript     │      │   (gateway)      │      │   pandas/numpy     │
└────────┬────────┘      └────────┬─────────┘      └─────────┬──────────┘
         │                        │                          │
         │   Supabase JS          │                          │
         ▼                        ▼                          ▼
    ┌───────────────────────────────────┐            ┌──────────────┐
    │        Supabase                   │            │   Upstash    │
    │  Auth · Postgres · Storage · RLS  │            │    Redis     │
    └───────────────────────────────────┘            └──────────────┘
                                 ▲
                                 │
                        ┌────────┴────────┐
                        │  Google Gemini  │
                        │   (advisor)     │
                        └─────────────────┘
```

A thin Express gateway handles auth and orchestration; the quant-heavy work (metrics, Monte Carlo, GBM forecasting, efficient frontier) lives in a dedicated Python/FastAPI service so the numerical code stays in the ecosystem built for it, while the web and API layers stay in TypeScript end-to-end.

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Web | React 19, Vite 5, TypeScript, Tailwind v4, shadcn/ui, Recharts, Framer Motion | Modern, mature ecosystem, premium UX out of the box |
| API | Node 20, Express 4, TypeScript, Zod, Pino | Thin gateway — auth validation, orchestration, Gemini proxy |
| ML | Python 3.11, FastAPI, pandas, NumPy, SciPy, scikit-learn, yfinance, PyPortfolioOpt | Real quant — auto OpenAPI docs, Pydantic validation |
| Auth + DB | Supabase (Postgres + Auth + Storage + RLS) | Drops the entire DIY JWT/bcrypt surface area; RLS = per-row security guarantees |
| LLM | Google Gemini (`gemini-2.5-flash`) | Strong price/performance at this scale |
| Cache | Redis (Upstash) | yfinance is slow; price data doesn't change intraday |
| Deploy | Vercel (web), Render/Railway (api + ml), Supabase, Upstash | Managed, low-ops hosting for each service |

---

## Repository layout

The private source repo is organized as a monorepo:

```
bullfin-ai/
├── apps/
│   ├── web/          # React + Vite + TS client
│   ├── api/          # Express + TS API gateway
│   └── ml/           # FastAPI Python quant engine
├── packages/
│   └── shared/       # Shared TypeScript types (portfolio, metrics, chat)
├── supabase/
│   ├── config.toml   # Supabase CLI config
│   └── migrations/   # SQL schema + RLS policies
├── data-samples/     # Example Portfolio.csv
├── docs/             # Architecture, API reference, deployment
├── .github/workflows # CI/CD
├── pnpm-workspace.yaml
├── tsconfig.base.json
└── .env.example
```

---

## Engineering notes

A few decisions worth calling out for anyone evaluating the codebase:

- **Security model**: Row-Level Security is enforced at the Postgres layer, not just in application code — so a bug in the API can't accidentally leak one user's portfolio to another.
- **Auth**: Supabase handles email/password and Google OAuth, avoiding a hand-rolled JWT/session implementation.
- **Validation**: Every request body is schema-validated on both the Node gateway (Zod) and the Python quant service (Pydantic) — no unchecked input crosses a service boundary.
- **Separation of concerns**: Quant logic (Monte Carlo, GBM forecasting, efficient frontier optimization) is isolated in its own FastAPI service rather than bolted onto the Node API, keeping the numerical code in Python's ecosystem.
- **Caching**: Redis sits in front of `yfinance` calls since market data doesn't need to be re-fetched on every request within a trading day.

Want a walkthrough of any of these in more depth, or a look at the actual source? Happy to share on request.

---

## Further reading

- Live product: [bullfin-ai.com](https://www.bullfin-ai.com)
- Reach out for a code walkthrough, architecture deep-dive, or access to the private source repository.

---

## License

MIT — applies to the BullFin-AI source, available on request.
