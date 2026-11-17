FROM ghcr.io/cirruslabs/flutter:stable AS web_builder
WORKDIR /workspace/app
COPY app/pubspec.yaml ./pubspec.yaml
RUN flutter pub get
COPY app/ ./
# USE_API makes the web build talk to the Fastify API on the same origin (/api).
RUN flutter build web --release --no-pub --dart-define=USE_API=true

FROM node:24-alpine AS api_builder
WORKDIR /workspace/api
COPY api/package*.json ./
RUN npm install
COPY api/ ./
RUN npm run build

FROM node:24-alpine AS runtime
ENV NODE_ENV=production PORT=3000
WORKDIR /app
COPY --from=api_builder /workspace/api/package*.json ./
COPY --from=api_builder /workspace/api/node_modules ./node_modules
COPY --from=api_builder /workspace/api/dist ./dist
COPY --from=api_builder /workspace/api/migrations ./migrations
COPY --from=web_builder /workspace/app/build/web ./public
EXPOSE 3000
CMD ["node", "dist/server.js"]
