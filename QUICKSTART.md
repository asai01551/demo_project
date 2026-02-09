# 🚀 Quick Start Guide

## Local Development Setup (Without Docker)

Since you have Redis and PostgreSQL already running locally, here's how to run the services:

### Prerequisites Met ✅
- ✅ PostgreSQL running on port 5434 (Docker)
- ✅ Redis running on port 6380 (Docker)
- ✅ Database migrated and seeded
- ✅ Dependencies installed

### Test Credentials
```
API Key: a147e5e4634cec1b9fb0bf26e48a0d40dbf9194a1513b926aae1d2b8292a4ccb
Endpoint ID (Production): cf40c473-f2f0-4d65-a71e-68efe26b07b4
Endpoint ID (Staging): 9c287947-7f12-47a1-abbd-9aa0c8923637
```

### Start Services

Open 4 separate terminal windows and run:

**Terminal 1 - Receiver Service:**
```bash
cd receiver-service
npm run dev
```

**Terminal 2 - Logger Service:**
```bash
cd logger-service
npm run dev
```

**Terminal 3 - Forwarder Service:**
```bash
cd forwarder-service
npm run dev
```

**Terminal 4 - Dashboard Service:**
```bash
cd dashboard-service
npm run dev
```

### Access Points

- **Receiver API**: http://localhost:3001
- **Logger API**: http://localhost:3002
- **Dashboard UI**: http://localhost:3004

### Test the System

1. **Send a test webhook:**
```bash
curl -X POST http://localhost:3001/webhook/cf40c473-f2f0-4d65-a71e-68efe26b07b4 \
  -H "X-API-Key: a147e5e4634cec1b9fb0bf26e48a0d40dbf9194a1513b926aae1d2b8292a4ccb" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "test.webhook",
    "data": {
      "message": "Hello from webhook relay!"
    }
  }'
```

2. **Check health:**
```bash
curl http://localhost:3001/health
curl http://localhost:3002/health
curl http://localhost:3004/health
```

3. **Open Dashboard:**
Open http://localhost:3004 in your browser and enter your API key.

### Important Notes

⚠️ **AWS S3 Configuration Required**

The system needs AWS credentials to store webhook payloads. Update your `.env` file:

```bash
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
S3_BUCKET_NAME=your-bucket-name
```

Without S3, webhooks will be received but payload storage will fail.

### Troubleshooting

**Services won't start:**
- Make sure ports 3001, 3002, 3004 are not in use
- Check that PostgreSQL (5434) and Redis (6380) are running:
  ```bash
  docker ps
  ```

**Database connection errors:**
- Verify DATABASE_URL in .env matches: `postgresql://webhook_user:webhook_pass@localhost:5434/webhook_relay`

**Redis connection errors:**
- Verify REDIS_PORT in .env is set to 6380

### Stop Services

Press `Ctrl+C` in each terminal window to stop the services.

To stop Docker containers:
```bash
docker-compose down