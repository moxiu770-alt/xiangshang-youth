FROM node:24-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:24-alpine
ENV NODE_ENV=production
RUN apk add --no-cache postgresql16-client
WORKDIR /app
COPY --from=dependencies /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY src ./src
COPY public ./public
COPY db ./db
COPY scripts ./scripts
RUN mkdir -p storage && chown -R node:node /app
USER node
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=5s --retries=5 CMD wget -qO- http://127.0.0.1:8080/readyz || exit 1
CMD ["node", "src/server.js"]
