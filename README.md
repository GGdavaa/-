# cognitum-one/cogs

[![CI](https://github.com/cognitum-one/cogs/actions/workflows/ci.yml/badge.svg)](https://github.com/cognitum-one/cogs/actions/workflows/ci.yml)
[![Deploy](https://github.com/cognitum-one/cogs/actions/workflows/deploy.yml/badge.svg)](https://github.com/cognitum-one/cogs/actions/workflows/deploy.yml)
[![Railway](https://img.shields.io/badge/Deploy-Railway-blueviolet?logo=railway)](https://railway.app)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Rust cog ecosystem — 105 + self-contained apps for Cognitum Seed.

Part of the [Cognitum platform](https://github.com/cognitum-one/cognitum).  
Migrated from [ruvnet/optimizer](https://github.com/ruvnet/optimizer).

---

## Table of contents

- [Architecture](#architecture)
- [Quick start — local](#quick-start--local)
- [Deploy to Railway](#deploy-to-railway)
- [Environment variables](#environment-variables)
- [GitHub Actions CI/CD](#github-actions-cicd)
- [Directory layout](#directory-layout)
- [Adding a new cog](#adding-a-new-cog)
- [Build & test reference](#build--test-reference)

---

## Architecture

Each cog is a small, single-purpose binary (edge AI, sensor fusion, swarm coordination, …) living under `src/cogs/<name>/`. The root crate provides the shared HTTP API, auth, storage, and SDK. See [`docs/adrs/`](docs/adrs/) for per-decision records (ADR-001 — cog-as-plugin, ADR-002 onwards — per-cog).

```
cognitum-api  (root binary)
    │
    ├── src/api/        REST API + middleware
    ├── src/auth/       JWT / API-key auth
    ├── src/storage/    PostgreSQL + Redis
    ├── src/ruvector/   Vector search
    └── src/cogs/       105+ individual cog binaries
            └── <name>/
                    ├── Cargo.toml
                    ├── cog.toml
                    └── src/main.rs
```

---

## Quick start — local

**Prerequisites:** Rust ≥ 1.75, Docker, Docker Compose.

```bash
# 1. Clone
git clone https://github.com/cognitum-one/cogs.git
cd cogs

# 2. Copy env template
cp .env.example .env
# Edit .env — at minimum set JWT_SECRET

# 3. Start Postgres + Redis + API
docker compose up

# — OR — run outside Docker:
cargo run --release --bin cognitum-api

# 4. Health check
curl http://localhost:8080/health
```

---

## Deploy to Railway

### One-click (recommended)

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/new?template=https://github.com/cognitum-one/cogs)

### Manual

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login & link project
railway login
railway link

# Add services from the Railway dashboard:
#   + Postgres plugin  → sets DATABASE_URL automatically
#   + Redis plugin     → sets REDIS_URL automatically

# Set remaining secrets
railway variables set JWT_SECRET="$(openssl rand -hex 32)"

# Deploy
railway up
```

### Required secrets (Railway dashboard → Variables)

| Variable | Source |
|---|---|
| `DATABASE_URL` | Auto-set by Postgres plugin |
| `REDIS_URL` | Auto-set by Redis plugin |
| `JWT_SECRET` | Generate: `openssl rand -hex 32` |

All other variables have sensible defaults (see [`railway.toml`](railway.toml) and [`.env.example`](.env.example)).

---

## Environment variables

See [`.env.example`](.env.example) for the full annotated list.

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8080` | HTTP port (Railway sets this automatically) |
| `HOST` | `0.0.0.0` | Bind address |
| `DATABASE_URL` | — | PostgreSQL connection string |
| `REDIS_URL` | — | Redis connection string |
| `JWT_SECRET` | — | **Required.** 32+ char secret |
| `RATE_LIMIT_REQUESTS_PER_MINUTE` | `100` | Per-IP rate limit |
| `ENABLE_CORS` | `true` | Enable CORS headers |
| `RUST_LOG` | `info,cognitum=debug` | Log verbosity |

---

## GitHub Actions CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | push / PR | Lint, format, per-cog check, manifest validation, Docker smoke build |
| [`deploy.yml`](.github/workflows/deploy.yml) | push to `main` | Build & push image to GHCR, trigger Railway redeploy |
| [`release.yml`](.github/workflows/release.yml) | push `v*.*.*` tag | Build versioned image, create GitHub Release |

### Setup

1. **GHCR** — automatic via `GITHUB_TOKEN` (no setup needed).
2. **Railway auto-deploy** — link your Railway project to GHCR in the Railway dashboard, or set `RAILWAY_TOKEN` in *Settings → Secrets* for CLI-triggered redeploys.
3. **Branch protection** — add `CI OK` as a required status check on `main`.

---

## Directory layout

| Path | Contents |
|---|---|
| `src/cogs/` | 105+ self-contained cog binaries |
| `src/api/` | HTTP API routes, handlers, middleware |
| `src/auth/` | JWT + API-key authentication |
| `src/storage/` | PostgreSQL + Redis adapters |
| `src/ruvector/` | Vector search integration |
| `src/bin/cognitum-api.rs` | API server entry point |
| `cognitum-sim/` | Hardware simulator workspace (14 crates) |
| `crates/` | Shared utility crates (agentvm, fxnn, thermal-brain, …) |
| `docs/adrs/` | Architecture Decision Records |
| `tests/` | Unit, integration, acceptance, stress tests |
| `benches/` | Criterion benchmarks |
| `examples/` | Demo programs |
| `ui-templates/` | Health monitor, neural trader, mesh manager UIs |

---

## Adding a new cog

```bash
COG=my-new-cog

mkdir -p src/cogs/$COG/src

# Cargo.toml
cat > src/cogs/$COG/Cargo.toml << TOML
[package]
name    = "cog-$COG"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "cog-$COG"
path = "src/main.rs"
TOML

# cog.toml
cat > src/cogs/$COG/cog.toml << TOML
id          = "$COG"
version     = "0.1.0"
description = "TODO"
TOML

# Stub binary
echo 'fn main() { println!("cog-$COG"); }' > src/cogs/$COG/src/main.rs
```

Then open a PR — the `adr-required` CI job will remind you to add an ADR.

---

## Build & test reference

```bash
# Check & build
cargo check
cargo build --release

# Tests
cargo test
cargo test --test unit_tests
cargo test --test integration_tests
cargo test --test acceptance_tests

# Benchmarks
cargo bench --bench ruvector_bench
cargo bench --bench page_index_bench

# Per-cog
cd src/cogs/<name>
cargo check --release --all-targets
cargo test --release --all-targets

# WASM
cd cognitum-sim && cargo build -p cognitum-wasm-sim

# Docker (local)
docker build -t cognitum-api .
docker run -p 8080:8080 --env-file .env cognitum-api
```

---

## Related repos

- [cognitum-one/cognitum](https://github.com/cognitum-one/cognitum) — meta-repo / platform overview
- [ruvnet/RuView](https://github.com/ruvnet/RuView) — WiFi-CSI integration (used by 2026-04 cog wave)
