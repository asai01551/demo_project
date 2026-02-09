# 🚀 Deployment Guide

Complete guide for deploying Webhook Relay & Logger to production.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [AWS Setup](#aws-setup)
3. [Database Setup](#database-setup)
4. [Docker Deployment](#docker-deployment)
5. [Kubernetes Deployment](#kubernetes-deployment)
6. [Post-Deployment](#post-deployment)
7. [Monitoring](#monitoring)

## Prerequisites

### Required Tools

- Docker 20+
- kubectl 1.25+
- AWS CLI configured
- Node.js 20+ (for local development)

### Required Services

- PostgreSQL 15+ (AWS RDS recommended)
- Redis 7+ (AWS ElastiCache recommended)
- S3 Bucket
- Kubernetes Cluster (EKS, GKE, or AKS)

## AWS Setup

### 1. Create S3 Bucket

```bash
aws s3 mb s3://webhook-relay-payloads --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket webhook-relay-payloads \
  --versioning-configuration Status=Enabled

# Set lifecycle policy (optional - archive old payloads)
cat > lifecycle.json <<EOF
{
  "Rules": [{
    "Id": "ArchiveOldPayloads",
    "Status": "Enabled",
    "Transitions": [{
      "Days": 90,
      "StorageClass": "GLACIER"
    }],
    "Expiration": {
      "Days": 365
    }
  }]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
  --bucket webhook-relay-payloads \
  --lifecycle-configuration file://lifecycle.json
```

### 2. Create IAM User/Role

```bash
# Create IAM policy
cat > s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::webhook-relay-payloads/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": "arn:aws:s3:::webhook-relay-payloads"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name WebhookRelayS3Policy \
  --policy-document file://s3-policy.json

# Create IAM user
aws iam create-user --user-name webhook-relay-service

# Attach policy
aws iam attach-user-policy \
  --user-name webhook-relay-service \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/WebhookRelayS3Policy

# Create access keys
aws iam create-access-key --user-name webhook-relay-service
```

### 3. Create RDS PostgreSQL Instance

```bash
aws rds create-db-instance \
  --db-instance-identifier webhook-relay-db \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.4 \
  --master-username webhook_admin \
  --master-user-password 'YourSecurePassword123!' \
  --allocated-storage 100 \
  --storage-type gp3 \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name your-subnet-group \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "mon:04:00-mon:05:00" \
  --multi-az \
  --publicly-accessible false
```

### 4. Create ElastiCache Redis

```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id webhook-relay-redis \
  --cache-node-type cache.t3.medium \
  --engine redis \
  --engine-version 7.0 \
  --num-cache-nodes 1 \
  --cache-subnet-group-name your-subnet-group \
  --security-group-ids sg-xxxxx
```

## Database Setup

### 1. Connect to RDS

```bash
# Get RDS endpoint
aws rds describe-db-instances \
  --db-instance-identifier webhook-relay-db \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text

# Connect via psql
psql -h your-rds-endpoint.rds.amazonaws.com \
  -U webhook_admin \
  -d postgres
```

### 2. Create Database

```sql
CREATE DATABASE webhook_relay;
CREATE USER webhook_user WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE webhook_relay TO webhook_user;
```

### 3. Run Migrations

```bash
# Set DATABASE_URL
export DATABASE_URL="postgresql://webhook_user:secure_password@your-rds-endpoint:5432/webhook_relay"

# Run migrations
cd shared
npx prisma migrate deploy
```

## Docker Deployment

### 1. Build Images

```bash
# Build all images
docker-compose build

# Or build individually
docker build -t webhook-relay/receiver-service:latest -f receiver-service/Dockerfile .
docker build -t webhook-relay/logger-service:latest -f logger-service/Dockerfile .
docker build -t webhook-relay/forwarder-service:latest -f forwarder-service/Dockerfile .
docker build -t webhook-relay/dashboard-service:latest -f dashboard-service/Dockerfile .
```

### 2. Push to Registry

```bash
# Tag for ECR
docker tag webhook-relay/receiver-service:latest \
  123456789.dkr.ecr.us-east-1.amazonaws.com/webhook-relay/receiver:latest

# Push to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.us-east-1.amazonaws.com

docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/webhook-relay/receiver:latest
```

### 3. Deploy with Docker Compose

```bash
# Update .env with production values
cp .env.example .env
nano .env

# Start services
docker-compose up -d

# Check logs
docker-compose logs -f
```

## Kubernetes Deployment

### 1. Create EKS Cluster

```bash
eksctl create cluster \
  --name webhook-relay \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.large \
  --nodes 3 \
  --nodes-min 3 \
  --nodes-max 10 \
  --managed
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name webhook-relay
```

### 3. Create Secrets

```bash
# Create namespace
kubectl create namespace webhook-relay

# Create secrets
kubectl create secret generic webhook-relay-secrets \
  --from-literal=DATABASE_URL='postgresql://webhook_user:password@rds-endpoint:5432/webhook_relay' \
  --from-literal=AWS_ACCESS_KEY_ID='your-access-key' \
  --from-literal=AWS_SECRET_ACCESS_KEY='your-secret-key' \
  --from-literal=S3_BUCKET_NAME='webhook-relay-payloads' \
  --from-literal=AWS_REGION='us-east-1' \
  --namespace=webhook-relay
```

### 4. Deploy Services

```bash
# Apply all manifests
kubectl apply -f k8s/

# Or use the deployment script
chmod +x scripts/deploy-k8s.sh
./scripts/deploy-k8s.sh
```

### 5. Verify Deployment

```bash
# Check pods
kubectl get pods -n webhook-relay

# Check services
kubectl get svc -n webhook-relay

# Check logs
kubectl logs -f deployment/receiver-service -n webhook-relay
```

## Post-Deployment

### 1. Run Database Migrations

```bash
kubectl exec -n webhook-relay deployment/receiver-service -- \
  sh -c "cd /app/shared && npx prisma migrate deploy"
```

### 2. Seed Database (Optional)

```bash
kubectl exec -n webhook-relay deployment/receiver-service -- \
  node /app/scripts/seed.js
```

### 3. Configure DNS

```bash
# Get LoadBalancer IPs
kubectl get svc -n webhook-relay

# Create DNS records
# receiver.yourdomain.com -> Receiver LoadBalancer IP
# dashboard.yourdomain.com -> Dashboard LoadBalancer IP
```

### 4. Setup SSL/TLS

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create ClusterIssuer for Let's Encrypt
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

## Monitoring

### 1. Setup Prometheus & Grafana

```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Access Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### 2. Setup CloudWatch Logs (AWS)

```bash
# Install Fluent Bit
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml
```

### 3. Setup Alerts

```bash
# Create AlertManager config
kubectl create configmap alertmanager-config \
  --from-file=alertmanager.yml \
  -n monitoring
```

## Backup & Recovery

### Database Backups

```bash
# RDS automated backups are enabled by default
# Manual snapshot
aws rds create-db-snapshot \
  --db-instance-identifier webhook-relay-db \
  --db-snapshot-identifier webhook-relay-backup-$(date +%Y%m%d)
```

### S3 Versioning

S3 versioning is enabled, allowing recovery of deleted/overwritten objects.

## Scaling

### Manual Scaling

```bash
kubectl scale deployment receiver-service --replicas=5 -n webhook-relay
```

### Auto-scaling

HPA is configured in the manifests. Adjust thresholds in:
- `k8s/receiver-deployment.yaml`
- `k8s/forwarder-deployment.yaml`

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n webhook-relay
kubectl describe pod <pod-name> -n webhook-relay
```

### View Logs

```bash
kubectl logs -f deployment/receiver-service -n webhook-relay
kubectl logs -f deployment/forwarder-service -n webhook-relay --tail=100
```

### Debug Connection Issues

```bash
# Test database connection
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h your-rds-endpoint -U webhook_user -d webhook_relay

# Test Redis connection
kubectl run -it --rm debug --image=redis:7 --restart=Never -- \
  redis-cli -h redis-service.webhook-relay.svc.cluster.local ping
```

## Security Checklist

- [ ] Secrets stored in Kubernetes secrets (not in code)
- [ ] RDS in private subnet
- [ ] Security groups properly configured
- [ ] S3 bucket not publicly accessible
- [ ] API keys rotated regularly
- [ ] SSL/TLS enabled
- [ ] Network policies configured
- [ ] RBAC enabled
- [ ] Pod security policies applied

## Cost Optimization

1. Use spot instances for non-critical workloads
2. Enable S3 lifecycle policies
3. Use RDS reserved instances
4. Configure HPA to scale down during low traffic
5. Use ElastiCache reserved nodes

---

For support, create an issue on GitHub or contact the team.