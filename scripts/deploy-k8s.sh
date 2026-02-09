#!/bin/bash

set -e

echo "🚀 Deploying Webhook Relay to Kubernetes..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if secrets exist
if [ ! -f k8s/secret.yaml ]; then
    echo -e "${YELLOW}Creating secrets from example...${NC}"
    echo -e "${RED}⚠️  Please update k8s/secret.yaml with your actual secrets!${NC}"
    cp k8s/secret.yaml.example k8s/secret.yaml
    exit 1
fi

# Build Docker images
echo -e "${GREEN}🐳 Building Docker images...${NC}"
docker build -t webhook-relay/receiver-service:latest -f receiver-service/Dockerfile .
docker build -t webhook-relay/logger-service:latest -f logger-service/Dockerfile .
docker build -t webhook-relay/forwarder-service:latest -f forwarder-service/Dockerfile .
docker build -t webhook-relay/dashboard-service:latest -f dashboard-service/Dockerfile .

# Apply Kubernetes manifests
echo -e "${GREEN}☸️  Applying Kubernetes manifests...${NC}"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/redis-deployment.yaml
kubectl apply -f k8s/receiver-deployment.yaml
kubectl apply -f k8s/logger-deployment.yaml
kubectl apply -f k8s/forwarder-deployment.yaml
kubectl apply -f k8s/dashboard-deployment.yaml

# Wait for deployments
echo -e "${GREEN}⏳ Waiting for deployments to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s \
  deployment/receiver-service \
  deployment/logger-service \
  deployment/forwarder-service \
  deployment/dashboard-service \
  -n webhook-relay

# Run database migrations
echo -e "${GREEN}🗄️  Running database migrations...${NC}"
kubectl exec -n webhook-relay deployment/receiver-service -- sh -c "cd /app/shared && npx prisma migrate deploy"

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo "Get service URLs:"
echo "  kubectl get services -n webhook-relay"
echo ""
echo "View logs:"
echo "  kubectl logs -f deployment/receiver-service -n webhook-relay"
echo "  kubectl logs -f deployment/forwarder-service -n webhook-relay"

# Made with Bob
