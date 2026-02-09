FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
COPY logger-service/package*.json ./logger-service/
COPY shared/package*.json ./shared/

RUN npm install --workspace=shared --workspace=logger-service

COPY shared/ ./shared/
COPY logger-service/ ./logger-service/

RUN npm run build --workspace=shared
RUN npm run build --workspace=logger-service

FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
COPY logger-service/package*.json ./logger-service/
COPY shared/package*.json ./shared/

RUN npm install --workspace=shared --workspace=logger-service --omit=dev

COPY --from=builder /app/shared/dist ./shared/dist
COPY --from=builder /app/shared/prisma ./shared/prisma
COPY --from=builder /app/logger-service/dist ./logger-service/dist

RUN cd shared && npx prisma generate

WORKDIR /app/logger-service

EXPOSE 3002

CMD ["node", "dist/index.js"]