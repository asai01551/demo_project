# AWS Deployment Guide

This guide provides step-by-step instructions for deploying the Webhook Relay & Logger application to AWS and cleaning up all resources.

## Prerequisites

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws configure
   ```

2. **AWS Account** with appropriate permissions:
   - CloudFormation
   - EC2, VPC, RDS, ElastiCache
   - S3, IAM, Secrets Manager
   - CloudWatch

3. **Docker** (optional, for containerized deployment)

## Quick Start

### Deploy Everything to AWS

```bash
cd cloudformation
./deploy.sh
```

This will:
- Create VPC with public/private subnets
- Deploy RDS PostgreSQL database
- Deploy ElastiCache Redis cluster
- Create S3 bucket for webhook payloads
- Set up IAM roles and security groups
- Configure CloudWatch logging

**Deployment time:** ~15-20 minutes

### Delete Everything from AWS

```bash
cd cloudformation
./cleanup-all.sh --delete-local-bucket
```

This will:
- Delete the CloudFormation stack
- Remove all AWS resources
- Delete S3 buckets and all contents
- Clean up IAM roles and policies

**Cleanup time:** ~10-15 minutes

## Detailed Deployment Steps

### 1. Deploy Infrastructure

```bash
cd cloudformation

# Deploy with default settings
./deploy.sh

# Or customize deployment
./deploy.sh \
  --stack-name my-webhook-relay \
  --region us-west-2 \
  --db-password MySecurePassword123
```

**Options:**
- `--stack-name`: CloudFormation stack name (default: webhook-relay-prod)
- `--region`: AWS region (default: us-east-1)
- `--db-password`: Database password (will prompt if not provided)

### 2. Get Stack Outputs

After deployment completes, get the connection details:

```bash
./get-outputs.sh --stack-name webhook-relay-prod --region us-east-1
```

You'll receive:
- RDS endpoint
- Redis endpoint
- S3 bucket name
- VPC and subnet IDs

### 3. Configure Application

Update your `.env` file with the stack outputs:

```bash
# From CloudFormation outputs
DATABASE_URL=postgresql://webhook_admin:password@<rds-endpoint>:5432/webhook_relay
REDIS_HOST=<redis-endpoint>
S3_BUCKET_NAME=<bucket-name>

# Keep existing values
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

### 4. Run Database Migrations

```bash
cd shared
DATABASE_URL='<connection-string>' npx prisma migrate deploy
```

### 5. Deploy Application

#### Option A: EC2 Deployment

1. Launch EC2 instances in the VPC
2. Install Node.js and dependencies
3. Clone repository
4. Configure environment variables
5. Start services with PM2

```bash
# On EC2 instance
npm install -g pm2
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

#### Option B: ECS/Fargate Deployment

1. Build Docker images
2. Push to ECR
3. Create ECS task definitions
4. Deploy services to ECS cluster

```bash
# Build and push images
docker build -t webhook-relay-receiver ./receiver-service
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
docker tag webhook-relay-receiver:latest <account>.dkr.ecr.us-east-1.amazonaws.com/webhook-relay-receiver:latest
docker push <account>.dkr.ecr.us-east-1.amazonaws.com/webhook-relay-receiver:latest
```

#### Option C: Kubernetes Deployment

```bash
cd k8s
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f receiver-deployment.yaml
kubectl apply -f logger-deployment.yaml
kubectl apply -f forwarder-deployment.yaml
kubectl apply -f dashboard-deployment.yaml
```

## Cleanup Options

### Option 1: Complete Cleanup (Recommended for Demo)

Delete everything including locally created S3 buckets:

```bash
cd cloudformation
./cleanup-all.sh --delete-local-bucket
```

**Confirmation required:** Type `DELETE EVERYTHING`

### Option 2: Stack Only

Delete CloudFormation stack but keep S3 data:

```bash
cd cloudformation
./delete-stack.sh
```

**Confirmation required:** Type `yes`

### Option 3: Force Delete (Non-interactive)

```bash
cd cloudformation
./delete-stack.sh --force
```

## Cost Estimation

**Monthly AWS costs (approximate):**

- RDS PostgreSQL (db.t3.micro): $15-20
- ElastiCache Redis (cache.t3.micro): $12-15
- S3 Storage (first 50GB): $1-2
- Data Transfer: $5-10
- CloudWatch Logs: $2-5

**Total:** ~$35-52/month

**Note:** Costs vary by region and usage. Use AWS Cost Calculator for accurate estimates.

## Monitoring

### CloudWatch Dashboards

Access CloudWatch to monitor:
- Application logs
- Database performance
- Redis metrics
- S3 usage

### Application Health Checks

```bash
# Check service health
curl http://<load-balancer>/health

# View logs
aws logs tail /aws/webhook-relay/receiver --follow
```

## Troubleshooting

### Deployment Fails

```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name webhook-relay-prod \
  --region us-east-1

# View failed resources
aws cloudformation describe-stack-resources \
  --stack-name webhook-relay-prod \
  --region us-east-1
```

### Database Connection Issues

1. Check security group rules
2. Verify database endpoint
3. Test connection from EC2 instance
4. Check RDS status in console

### S3 Access Issues

1. Verify IAM role permissions
2. Check bucket policy
3. Confirm bucket exists in correct region
4. Test with AWS CLI: `aws s3 ls s3://bucket-name`

## Security Best Practices

1. **Rotate Credentials:** Change database passwords regularly
2. **Use Secrets Manager:** Store sensitive data in AWS Secrets Manager
3. **Enable Encryption:** Enable encryption at rest for RDS and S3
4. **VPC Security:** Keep databases in private subnets
5. **IAM Policies:** Use least-privilege access
6. **Enable MFA:** Require MFA for AWS console access
7. **CloudTrail:** Enable CloudTrail for audit logging

## Backup and Recovery

### Automated Backups

RDS automatically creates daily backups with 7-day retention.

### Manual Backup

```bash
# Create RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier webhook-relay-db \
  --db-snapshot-identifier webhook-relay-backup-$(date +%Y%m%d)

# Backup S3 data
aws s3 sync s3://webhook-relay-payloads s3://webhook-relay-backup
```

### Restore from Backup

```bash
# Restore RDS from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier webhook-relay-db-restored \
  --db-snapshot-identifier webhook-relay-backup-20260213
```

## Scaling

### Horizontal Scaling

- Add more EC2 instances behind load balancer
- Scale ECS tasks up/down
- Use Auto Scaling Groups

### Vertical Scaling

- Upgrade RDS instance type
- Increase Redis cache size
- Resize EC2 instances

## Support

For issues or questions:
1. Check CloudFormation events
2. Review CloudWatch logs
3. Consult AWS documentation
4. Contact AWS Support

---

**Made with Bob**