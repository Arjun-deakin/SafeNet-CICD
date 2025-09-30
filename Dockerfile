# ---------- Stage 1: build & test ----------
FROM node:20-alpine AS build
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
# optional but recommended in CI — fails the build if tests fail
RUN npm test

# ---------- Stage 2: production runtime ----------
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

# curl for HEALTHCHECK
RUN apk add --no-cache curl

# bring in the built app + node_modules from the build stage
COPY --from=build /app /app

EXPOSE 3000

# Docker-native health check (Docker marks container healthy/unhealthy)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# IMPORTANT: server.js starts the listener
CMD ["node", "server.js"]
