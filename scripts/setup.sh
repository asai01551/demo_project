#!/bin/bash

set -e

echo "🚀 Setting up Webhook Relay & Logger System"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env file from .env.example...${NC}"
    cp .env.example .env
    echo -e "${RED}⚠️  Please update .env with your actual configuration!${NC}"
    exit 1
fi

# Install dependencies
echo -e "${GREEN}📦 Installing dependencies...${NC}"
npm install

# Generate Prisma client
echo -e "${GREEN}🔧 Generating Prisma client...${NC}"
cd shared && npx prisma generate && cd ..

# Build all services
echo -e "${GREEN}🏗️  Building all services...${NC}"
npm run build:all

echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Update .env with your configuration"
echo "2. Set up your database (see scripts/setup-db.sh)"
echo "3. Run 'npm run docker:up' for local development"
echo "4. Or deploy to Kubernetes with 'kubectl apply -f k8s/'"

# Made with Bob
