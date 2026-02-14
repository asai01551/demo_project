# AWS Complete Deployment Guide

This guide covers deploying the entire Webhook Relay & Logger application to AWS with a single command, including infrastructure and application services.

## 🎯 What Gets Deployed

### Infrastructure
- **VPC** with public and private subnets across 2 availability zones
- **NAT Gateway** for private subnet internet access
- **Internet Gateway** for public subnet access
- **RDS PostgreSQL 15.16** (Multi-AZ, db.t3.medium, 100GB storage)
- **ElastiCache Redis 7.0** (cache.t3.medium)
- **S3 Bucket** for webhook payloads (versioned, encrypted)
- **IAM Roles** and instance profiles
- **CloudWatch Log Groups** for all services
- **Secrets Manager** for database credentials

### Application Services (on EC2)
- **Application Load Balancer** (internet-facing)
- **EC2 Auto Scaling Group** (1-2 instances, t3.medium)
- **4 Microservices** running on EC2:
  - Receiver Service (port 3001) - Webhook ingestion
  - Logger Service (port 3002) - Log management
  - Forwarder Service (port 3003) - Webhook forwarding
  - Dashboard Service (port 3004) - Web UI

## 📋 Prerequisites

### Required Tools
```bash
# AWS CLI v2
aws --version  # Should be 2.x.x

# Configured AWS credentials
aws sts get-caller-identity

# Git (for cloning)
git --version
```

### AWS Account Requirements
- AWS account with appropriate permissions
- IAM permissions for:
  - CloudFormation (full access)
  - EC2, VPC, RDS, ElastiCache, S3
  - IAM role creation
  - CloudWatch Logs
  - Secrets Manager
  - Auto Scaling
  - Elastic Load Balancing

### Estimated Costs
- **RDS PostgreSQL (db.t3.medium)**: ~$60/month
- **ElastiCache Redis (cache.t3.medium)**: ~$50/month
- **EC2 (t3.medium)**: ~$30/month
- **NAT Gateway**: ~$32/month
- **Application Load Balancer**: ~$16/month
- **S3 Storage**: Variable (pay per GB)
- **Data Transfer**: Variable

**Total: ~$190-250/month** (varies by usage)

## 🚀 One-Command Deployment

### Step 1: Clone Repository
```bash
git clone <your-repo-url>
cd webhook-relay-logger
```

### Step 2: Deploy Everything
```bash
cd cloudformation
chmod +x deploy.sh
./deploy.sh
```

You'll be prompted for:
- Database password (min 8 characters)
- Deployment confirmation

### What Happens During Deployment

1. **Validates CloudFormation template** (30 seconds)
2. **Creates infrastructure stack** (15-20 minutes)
   - VPC and networking
   - RDS PostgreSQL
   - ElastiCache Redis
   - S3 bucket
   - IAM roles
   - Load Balancer
   - EC2 Auto Scaling Group
3. **Waits for EC2 instance** (2-3 minutes)
4. **Deploys application code** (5-10 minutes)
   - Packages application
   - Uploads to S3
   - Installs on EC2
   - Runs database migrations
   - Starts all services with PM2

**Total Time: 25-35 minutes**

### Deployment Output
```
🌐 Your Application URLs:

  Dashboard:      http://webhook-relay-prod-alb-123456789.us-east-1.elb.amazonaws.com
  Webhook API:    http://webhook-relay-prod-alb-123456789.us-east-1.elb.amazonaws.com/webhook
  Health Check:   http://webhook-relay-prod-alb-123456789.us-east-1.elb.amazonaws.com/health

⏳ Note: Services may take 5-10 minutes to fully start
   Monitor health checks in the AWS Console
```

## 🔧 Advanced Deployment Options

### Custom Stack Name
```bash
./deploy.sh --stack-name my-webhook-app
```

### Different Region
```bash
./deploy.sh --region eu-west-1
```

### Skip Application Deployment (Infrastructure Only)
```bash
./deploy.sh --skip-app-deployment
```

Then deploy application later:
```bash
cd ..
./scripts/deploy-to-ec2.sh webhook-relay-prod
```

### Non-Interactive Deployment
```bash
./deploy.sh --db-password "MySecurePassword123" --stack-name webhook-relay-prod
```

## 📊 Monitoring & Management

### View Stack Outputs
```bash
./get-outputs.sh
```

### Check Service Status
```bash
# Get EC2 instance ID
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names webhook-relay-prod-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text

# Connect via SSM Session Manager (no SSH key needed)
aws ssm start-session --target <instance-id>

# Check PM2 status
sudo pm2 status
sudo pm2 logs
```

### CloudWatch Logs
```bash
# View receiver service logs
aws logs tail /aws/webhook-relay-prod/receiver-service --follow

# View all services
aws logs tail /aws/webhook-relay-prod/logger-service --follow
aws logs tail /aws/webhook-relay-prod/forwarder-service --follow
aws logs tail /aws/webhook-relay-prod/dashboard-service --follow
```

### Load Balancer Health Checks
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn>
```

## 🔄 Updating the Application

### Redeploy Application Code
```bash
cd scripts
./deploy-to-ec2.sh webhook-relay-prod
```

This will:
1. Package latest code
2. Upload to S3
3. Deploy to EC2
4. Restart services with zero downtime

### Update Infrastructure
```bash
# Modify cloudformation/webhook-relay-stack.yaml
# Then update stack
aws cloudformation update-stack \
  --stack-name webhook-relay-prod \
  --template-body file://webhook-relay-stack.yaml \
  --capabilities CAPABILITY_NAMED_IAM
```

## 🧪 Testing the Deployment

### 1. Check Health Endpoints
```bash
LB_URL="http://your-alb-url.elb.amazonaws.com"

# Dashboard health
curl $LB_URL/health

# Receiver health
curl $LB_URL/webhook/health
```

### 2. Create an Endpoint
```bash
# Get API key from dashboard or database
API_KEY="your-api-key"

# Create endpoint
curl -X POST $LB_URL/endpoints \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Endpoint",
    "description": "Testing AWS deployment",
    "forwardUrl": "https://webhook.site/your-unique-url"
  }'
```

### 3. Send Test Webhook
```bash
ENDPOINT_ID="your-endpoint-id"

curl -X POST $LB_URL/webhook/$ENDPOINT_ID \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "timestamp": "2024-01-01T00:00:00Z"}'
```

### 4. View Logs
```bash
# Via API
curl $LB_URL/logs?endpointId=$ENDPOINT_ID \
  -H "x-api-key: $API_KEY"

# Via Dashboard
open $LB_URL
```

## 🗑️ Cleanup & Deletion

### Delete Everything
```bash
cd cloudformation
./delete-stack.sh --force
```

This will delete:
- ✅ EC2 instances and Auto Scaling Group
- ✅ Application Load Balancer
- ✅ RDS PostgreSQL (snapshot created)
- ✅ ElastiCache Redis
- ✅ S3 bucket and all payloads
- ✅ VPC and networking
- ✅ IAM roles
- ✅ CloudWatch logs
- ✅ Secrets Manager secrets

**Time: 10-15 minutes**

### Delete with Confirmation
```bash
./delete-stack.sh
# Type 'yes' when prompted
```

## 🔒 Security Best Practices

### 1. Database Password
- Use strong passwords (min 16 characters)
- Store in AWS Secrets Manager (done automatically)
- Rotate regularly

### 2. API Keys
- Generate strong API keys
- Store securely
- Rotate periodically
- Use different keys for different environments

### 3. Network Security
- RDS and Redis are in private subnets (no internet access)
- Only ALB is internet-facing
- Security groups restrict traffic between components
- NAT Gateway for outbound traffic from private subnets

### 4. S3 Bucket
- Encryption at rest (AES256)
- Versioning enabled
- Public access blocked
- Lifecycle policies for cost optimization

### 5. IAM Roles
- Least privilege principle
- Instance profiles for EC2
- No hardcoded credentials

## 🐛 Troubleshooting

### Deployment Fails
```bash
# Check CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name webhook-relay-prod \
  --max-items 20

# Check specific resource
aws cloudformation describe-stack-resource \
  --stack-name webhook-relay-prod \
  --logical-resource-id RDSInstance
```

### Services Not Starting
```bash
# Connect to EC2
aws ssm start-session --target <instance-id>

# Check PM2 logs
sudo pm2 logs

# Check system logs
sudo journalctl -u webhook-relay-deploy -n 100

# Restart services
sudo pm2 restart all
```

### Health Checks Failing
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <arn>

# Check security groups
aws ec2 describe-security-groups \
  --group-ids <sg-id>

# Test from EC2 instance
curl localhost:3001/health
curl localhost:3004/health
```

### Database Connection Issues
```bash
# Test from EC2
psql "$DATABASE_URL"

# Check security group rules
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*rds*"
```

## 📈 Scaling

### Horizontal Scaling (More Instances)
```bash
# Update Auto Scaling Group
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name webhook-relay-prod-asg \
  --min-size 2 \
  --max-size 4 \
  --desired-capacity 2
```

### Vertical Scaling (Bigger Instances)
Update CloudFormation template:
```yaml
InstanceType: t3.large  # Change from t3.medium
```

Then update stack.

### Database Scaling
```bash
# Modify RDS instance class
aws rds modify-db-instance \
  --db-instance-identifier webhook-relay-prod-postgres \
  --db-instance-class db.t3.large \
  --apply-immediately
```

## 🎓 Architecture Overview

```
Internet
    ↓
Application Load Balancer (Public Subnets)
    ↓
EC2 Auto Scaling Group (Public Subnets)
    ├── Receiver Service :3001
    ├── Logger Service :3002
    ├── Forwarder Service :3003
    └── Dashboard Service :3004
    ↓
Private Subnets
    ├── RDS PostgreSQL (Multi-AZ)
    ├── ElastiCache Redis
    └── NAT Gateway → Internet
    ↓
S3 Bucket (Webhook Payloads)
```

## 📞 Support

For issues or questions:
1. Check CloudWatch Logs
2. Review CloudFormation events
3. Check EC2 instance logs via SSM
4. Review this documentation

## 🔄 CI/CD Integration

### GitHub Actions Example
```yaml
name: Deploy to AWS
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Deploy Application
        run: |
          cd scripts
          ./deploy-to-ec2.sh webhook-relay-prod
```

---

**Made with ❤️ by IBM Bob**