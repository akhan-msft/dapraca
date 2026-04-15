# Multi-stage: build React → copy into Node.js BFF image
FROM node:20-slim AS client-builder
WORKDIR /client
COPY client/package*.json ./
RUN npm ci
COPY client/ .
RUN npm run build    # outputs to /client/build

# ── Node.js BFF runtime ───────────────────────────────────────────────────────
FROM node:20-slim AS runtime
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY server/ ./server/
COPY --from=client-builder /client/build ./client/build

RUN chown -R node /app
USER node

EXPOSE 3000
ENV PORT=3000
ENV NODE_ENV=production

CMD ["node", "server/index.js"]
