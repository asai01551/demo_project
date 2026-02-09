FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
COPY forwarder-service/package*.json ./forwarder-service/
COPY shared/package*.json ./shared/

RUN npm install --workspace=shared --workspace=forwarder-service

COPY shared/ ./shared/
COPY forwarder-service/ ./forwarder-service/

RUN npm run build --workspace=shared
RUN npm run build --workspace=forwarder-service

FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
COPY forwarder-service/package*.json ./forwarder-service/
COPY shared/package*.json ./shared/

RUN npm install --workspace=shared --workspace=forwarder-service --omit=dev

COPY --from=builder /app/shared/dist ./shared/dist
COPY --from=builder /app/shared/prisma ./shared/prisma
COPY --from=builder /app/forwarder-service/dist ./forwarder-service/dist

RUN cd shared && npx prisma generate

WORKDIR /app/forwarder-service

CMD ["node", "dist/index.js"]