# ──────────────────────────────────────────────────────────────────
# Cognitum API — multi-stage Dockerfile
# Optimised for Railway (x86-64 / linux/amd64).
# ──────────────────────────────────────────────────────────────────

# ── Stage 1: builder ──────────────────────────────────────────────
FROM rust:1.85-slim AS builder

# System deps needed for sqlx (native-tls / openssl) and linking
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        pkg-config \
        libssl-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy manifests first — layer-cache cargo fetch
COPY Cargo.toml Cargo.lock ./

# Copy sub-workspace manifests so Cargo can resolve the workspace
COPY cognitum-sim/Cargo.toml         cognitum-sim/Cargo.toml
COPY cognitum-sim/crates/            cognitum-sim/crates/

# Stub out lib.rs and bin so `cargo fetch` / dependency build succeeds
# without copying the whole source tree yet.
RUN mkdir -p src && echo "pub fn _stub() {}" > src/lib.rs && \
    mkdir -p src/bin && \
    echo 'fn main(){}' > src/bin/cognitum-api.rs

# Fetch & pre-build dependencies (cached unless Cargo.toml changes)
RUN cargo fetch
RUN cargo build --release --bin cognitum-api 2>/dev/null || true

# Now copy real sources and rebuild (only app code recompiles)
COPY src/        src/
COPY crates/     crates/
COPY shared/     shared/

# Touch to force re-link
RUN touch src/lib.rs src/bin/cognitum-api.rs

RUN cargo build --release --bin cognitum-api

# ── Stage 2: runtime ──────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Non-root user for security
RUN useradd -ms /bin/bash cognitum
USER cognitum
WORKDIR /home/cognitum

COPY --from=builder /app/target/release/cognitum-api ./cognitum-api

# Railway injects PORT at runtime; we default to 8080 locally.
ENV HOST=0.0.0.0
ENV PORT=8080
ENV RUST_LOG=info,cognitum=debug

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

ENTRYPOINT ["./cognitum-api"]
