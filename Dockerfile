# Stage 1: Build & test
FROM node:20-alpine AS build
WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci

# Copy all source
COPY . .

# Run tests (optional – fail build if tests fail)
RUN npm test

# Stage 2: Production runtime
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

# Copy built app + node_modules from build stage
COPY --from=build /app /app

EXPOSE 3000

# Start server.js (not app.js)
CMD ["node", "server.js"]
