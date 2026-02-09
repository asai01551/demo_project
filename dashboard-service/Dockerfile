FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
COPY dashboard-service/package*.json ./dashboard-service/
COPY shared/package*.json ./shared/

RUN npm install --workspace=shared --workspace=dashboard-service

COPY shared/ ./shared/
COPY dashboard-service/ ./dashboard-service/

RUN npm run build --workspace=shared
RUN npm run build --workspace=dashboard-service

FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
COPY dashboard-service/package*.json ./dashboard-service/
COPY shared/package*.json ./shared/

RUN npm install --workspace=shared --workspace=dashboard-service --omit=dev

COPY --from=builder /app/shared/dist ./shared/dist
COPY --from=builder /app/shared/prisma ./shared/prisma
COPY --from=builder /app/dashboard-service/dist ./dashboard-service/dist
COPY dashboard-service/public ./dashboard-service/public

RUN cd shared && npx prisma generate

WORKDIR /app/dashboard-service

EXPOSE 3004

CMD ["node", "dist/index.js"]