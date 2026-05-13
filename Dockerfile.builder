# Railway service: Typebot Builder
ARG BUN_VERSION=1.3.9

FROM oven/bun:${BUN_VERSION}-slim AS bun

FROM node:24-bullseye-slim AS base

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
RUN ln -s /usr/local/bin/bun /usr/local/bin/bunx

RUN apt-get update -qq \
    && apt-get install -qq --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    g++ \
    openssl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

FROM base AS builder
COPY . .
RUN SENTRYCLI_SKIP_DOWNLOAD=1 bun install
RUN bunx nx sync
RUN SKIP_ENV_CHECK=true DATABASE_URL=postgresql:// NEXT_PUBLIC_VIEWER_URL=http://localhost bunx nx build builder
RUN DATABASE_URL=postgresql:// bunx nx db:generate prisma

FROM base AS release
ENV SCOPE=builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/prisma/postgresql ./packages/prisma/postgresql
COPY --from=builder /app/packages/prisma/prisma.config.ts ./packages/prisma/prisma.config.ts
COPY --from=builder --chown=node:node /app/apps/builder/.next/standalone ./
COPY --from=builder --chown=node:node /app/apps/builder/.next/static ./apps/builder/.next/static
COPY --from=builder --chown=node:node /app/apps/builder/public ./apps/builder/public
COPY scripts/builder-entrypoint.sh ./
RUN chmod +x ./builder-entrypoint.sh
USER node
ENTRYPOINT ["sh", "/app/builder-entrypoint.sh"]

EXPOSE 3000
ENV PORT=3000
