# 🔗 Webhook Relay & Logger

A production-ready microservices system for receiving, logging, and forwarding webhooks with automatic retry logic, built with Node.js, TypeScript, PostgreSQL, Redis, and S3.

## 🏗️ Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Client    │────▶│   Receiver   │────▶│    Redis    │
│  (Webhook)  │     │   Service    │     │    Queue    │
└─────────────┘     └──────────────┘     └─────────────┘
                           │                     │
                           ▼                     ▼
                    ┌──────────────┐     ┌─────────────┐
                    │    Logger    │     │  Forwarder  │
                    │   Service    │     │   Service   │
                    └──────────────┘     └─────────────┘
                           │                     │
                           ▼                     ▼
                    ┌──────────────┐     ┌─────────────┐
                    │  PostgreSQL  │     │ Destination │
                    │   (RDS)      │     │   Webhook   │
                    └──────────────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │   S3 Bucket  │
                    │  (Payloads)  │
                    └──────────────┘
```

## 🎯 Features

- **High Availability**: Horizontally scalable microservices
- **Reliable Delivery**: Automatic retry with exponential backoff
- **Payload Storage**: All webhook payloads stored in S3
- **Comprehensive Logging**: Full request/response logging
- **Real-time Dashboard**: Web UI for monitoring webhooks
- **Production Ready**: Docker & Kubernetes deployment configs
- **Health Checks**: Liveness and readiness probes
- **Auto-scaling**: HPA configuration for dynamic scaling

## 📦 Services

### Receiver Service (Port 3001)
- Accepts incoming webhooks via HTTP
- Validates API keys
- Stores payloads to S3
- Enqueues for processing

### Logger Service (Port 3002)
- Provides API for log retrieval
- Manages S3 payload access
- Tracks delivery statistics

### Forwarder Service
- Processes webhook queue
- Forwards to destination URLs
- Implements retry logic
- Updates delivery status

### Dashboard Service (Port 3004)
- Web UI for webhook inspection
- Real-time event monitoring
- Endpoint management
- Statistics visualization

## 🚀 Quick Start

### Prerequisites

- Node.js 20+
- Docker & Docker Compose
- PostgreSQL 15+
- Redis 7+
- AWS Account (for S3)

### Local Development

1. **Clone and setup**
```bash
git clone <repository>
cd webhook-relay-logger
chmod +x scripts/*.sh
./scripts/setup.sh
```

2. **Configure environment**
```bash
cp .env.example .env
# Edit .env with your configuration
```

3. **Start with Docker Compose**
```bash
npm run docker:up
```

4. **Run database migrations**
```bash
./scripts/setup-db.sh
```

5. **Access services**
- Receiver: http://localhost:3001
- Logger: http://localhost:3002
- Dashboard: http://localhost:3004

## 🔧 Configuration

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/webhook_relay

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# AWS S3
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
S3_BUCKET_NAME=webhook-relay-payloads

# Retry Configuration
MAX_RETRY_ATTEMPTS=3
RETRY_DELAY_MS=300000
RETRY_BACKOFF_MULTIPLIER=2
```

## 📡 API Usage

### Send a Webhook

```bash
curl -X POST http://localhost:3001/webhook/{endpoint_id} \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"event": "user.created", "data": {"id": 123}}'
```

### Check Webhook Status

```bash
curl http://localhost:3001/webhook/{endpoint_id}/events/{event_id} \
  -H "X-API-Key: your_api_key"
```

### Get Event Logs

```bash
curl http://localhost:3002/logs/events/{event_id}
```

## ☸️ Kubernetes Deployment

### Prerequisites

- Kubernetes cluster (EKS, GKE, AKS, or local)
- kubectl configured
- AWS RDS PostgreSQL instance
- S3 bucket created

### Deploy

1. **Create secrets**
```bash
cp k8s/secret.yaml.example k8s/secret.yaml
# Edit k8s/secret.yaml with your credentials
```

2. **Deploy to Kubernetes**
```bash
./scripts/deploy-k8s.sh
```

3. **Verify deployment**
```bash
kubectl get pods -n webhook-relay
kubectl get services -n webhook-relay
```

4. **Access services**
```bash
# Get LoadBalancer IPs
kubectl get svc -n webhook-relay

# Port forward for local access
kubectl port-forward -n webhook-relay svc/receiver-service 3001:3001
kubectl port-forward -n webhook-relay svc/dashboard-service 3004:3004
```

## 📊 Monitoring

### Health Checks

- Receiver: `GET /health`, `/health/live`, `/health/ready`
- Logger: `GET /health`
- Dashboard: `GET /health`

### Logs

```bash
# Docker Compose
docker-compose logs -f receiver-service

# Kubernetes
kubectl logs -f deployment/receiver-service -n webhook-relay
kubectl logs -f deployment/forwarder-service -n webhook-relay
```

### Metrics

The system includes:
- Request/response logging
- Delivery success/failure tracking
- Average response times
- Daily statistics per endpoint

## 🔒 Security

- API key authentication
- Rate limiting (1000 req/15min per IP)
- Helmet.js security headers
- CORS configuration
- Secrets management via Kubernetes secrets

## 🧪 Testing

```bash
# Run tests
npm test

# Test with sample webhook
curl -X POST http://localhost:3001/webhook/{endpoint_id} \
  -H "X-API-Key: your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

## 📈 Scaling

### Horizontal Scaling

The system auto-scales based on CPU/memory:
- Receiver: 3-10 replicas
- Forwarder: 2-8 replicas
- Logger: 2 replicas
- Dashboard: 2 replicas

### Manual Scaling

```bash
kubectl scale deployment receiver-service --replicas=5 -n webhook-relay
```

## 🛠️ Development

### Project Structure

```
webhook-relay-logger/
├── shared/                 # Shared utilities and Prisma schema
│   ├── src/
│   │   ├── types/         # TypeScript types
│   │   └── utils/         # Logger, S3, Redis, Database
│   └── prisma/
│       └── schema.prisma  # Database schema
├── receiver-service/       # Webhook receiver
├── logger-service/         # Log retrieval API
├── forwarder-service/      # Webhook forwarder
├── dashboard-service/      # Web dashboard
├── k8s/                    # Kubernetes manifests
├── scripts/                # Deployment scripts
└── docker-compose.yml      # Local development
```

### Adding a New Service

1. Create service directory
2. Add package.json with dependencies
3. Create Dockerfile
4. Add to docker-compose.yml
5. Create Kubernetes deployment manifest

## 🐛 Troubleshooting

### Webhooks not forwarding

1. Check forwarder service logs
2. Verify Redis connection
3. Check destination URL accessibility

### Database connection issues

1. Verify DATABASE_URL in secrets
2. Check PostgreSQL is running
3. Run migrations: `npx prisma migrate deploy`

### S3 upload failures

1. Verify AWS credentials
2. Check S3 bucket permissions
3. Ensure bucket exists in correct region

## 📝 License

MIT

## 👥 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📞 Support

For issues and questions:
- GitHub Issues: [Create an issue]
- Documentation: See `/docs` folder

---

Built with ❤️ by Bob