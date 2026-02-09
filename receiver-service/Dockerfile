FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY receiver-service/package*.json ./receiver-service/
COPY shared/package*.json ./shared/

# Install dependencies
RUN npm install --workspace=shared --workspace=receiver-service

# Copy source code
COPY shared/ ./shared/
COPY receiver-service/ ./receiver-service/

# Build shared and service
RUN npm run build --workspace=shared
RUN npm run build --workspace=receiver-service

# Production stage
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY receiver-service/package*.json ./receiver-service/
COPY shared/package*.json ./shared/

# Install production dependencies only
RUN npm install --workspace=shared --workspace=receiver-service --omit=dev

# Copy built files
COPY --from=builder /app/shared/dist ./shared/dist
COPY --from=builder /app/shared/prisma ./shared/prisma
COPY --from=builder /app/receiver-service/dist ./receiver-service/dist

# Generate Prisma client
RUN cd shared && npx prisma generate

# Set working directory to service
WORKDIR /app/receiver-service

EXPOSE 3001

CMD ["node", "dist/index.js"]