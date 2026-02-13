# CloudFormation Deployment Scripts

Quick reference for deploying and managing the Webhook Relay infrastructure on AWS.

## 🚀 Quick Start

### Deploy to AWS
```bash
./deploy.sh
```

### Delete Everything
```bash
./cleanup-all.sh --delete-local-bucket
```

## 📋 Available Scripts

### `deploy.sh` - Deploy Infrastructure

Deploys the complete CloudFormation stack with all AWS resources.

```bash
# Basic deployment
./deploy.sh

# Custom deployment
./deploy.sh \
  --stack-name my-webhook-relay \
  --region us-west-2 \
  --db-password MySecurePass123
```

**Options:**
- `--stack-name NAME` - Stack name (default: webhook-relay-prod)
- `--region REGION` - AWS region (default: us-east-1)
- `--db-password PASS` - Database password (prompts if not provided)
- `--help` - Show help

**Creates:**
- VPC with public/private subnets
- RDS PostgreSQL database
- ElastiCache Redis cluster
- S3 bucket for payloads
- IAM roles and security groups
- CloudWatch log groups

**Time:** ~15-20 minutes

---

### `delete-stack.sh` - Delete CloudFormation Stack

Deletes the CloudFormation stack and associated resources.

```bash
# Interactive deletion
./delete-stack.sh

# Force deletion (no confirmation)
./delete-stack.sh --force

# Custom stack
./delete-stack.sh \
  --stack-name my-webhook-relay \
  --region us-west-2
```

**Options:**
- `--stack-name NAME` - Stack name (default: webhook-relay-prod)
- `--region REGION` - AWS region (default: us-east-1)
- `--force` - Skip confirmation prompt
- `--help` - Show help

**Deletes:**
- All CloudFormation resources
- S3 bucket and contents
- Database snapshots (retained)

**Time:** ~10-15 minutes

---

### `cleanup-all.sh` - Complete Cleanup

Comprehensive cleanup that removes ALL AWS resources including locally created buckets.

```bash
# Complete cleanup
./cleanup-all.sh --delete-local-bucket

# Stack only (keep local buckets)
./cleanup-all.sh

# Custom configuration
./cleanup-all.sh \
  --stack-name my-webhook-relay \
  --region us-west-2 \
  --delete-local-bucket
```

**Options:**
- `--stack-name NAME` - Stack name (default: webhook-relay-prod)
- `--region REGION` - AWS region (default: us-east-1)
- `--delete-local-bucket` - Also delete locally created S3 buckets
- `--help` - Show help

**Deletes:**
- CloudFormation stack
- All stack resources
- S3 buckets created by CloudFormation
- Locally created S3 buckets (with --delete-local-bucket)

**Confirmation:** Type `DELETE EVERYTHING`

**Time:** ~10-15 minutes

---

### `get-outputs.sh` - Get Stack Information

Retrieves and displays CloudFormation stack outputs.

```bash
# Get outputs
./get-outputs.sh

# Custom stack
./get-outputs.sh \
  --stack-name my-webhook-relay \
  --region us-west-2
```

**Shows:**
- RDS endpoint
- Redis endpoint
- S3 bucket name
- VPC and subnet IDs
- Security group IDs

---

## 📊 Deployment Flow

```
1. Run deploy.sh
   ↓
2. Wait 15-20 minutes
   ↓
3. Get outputs with get-outputs.sh
   ↓
4. Update .env file
   ↓
5. Run database migrations
   ↓
6. Deploy application
   ↓
7. Test endpoints
```

## 🗑️ Cleanup Flow

```
1. Run cleanup-all.sh --delete-local-bucket
   ↓
2. Confirm with "DELETE EVERYTHING"
   ↓
3. Wait 10-15 minutes
   ↓
4. All resources deleted
```

## 💰 Cost Estimate

**Monthly AWS costs:**
- RDS (db.t3.micro): ~$15-20
- Redis (cache.t3.micro): ~$12-15
- S3 Storage: ~$1-2
- Data Transfer: ~$5-10
- CloudWatch: ~$2-5

**Total:** ~$35-52/month

## 🔍 Monitoring

### Check Stack Status
```bash
aws cloudformation describe-stacks \
  --stack-name webhook-relay-prod \
  --region us-east-1
```

### View Stack Events
```bash
aws cloudformation describe-stack-events \
  --stack-name webhook-relay-prod \
  --region us-east-1
```

### Check Resources
```bash
aws cloudformation describe-stack-resources \
  --stack-name webhook-relay-prod \
  --region us-east-1
```

## 🐛 Troubleshooting

### Deployment Failed
```bash
# Check events
aws cloudformation describe-stack-events \
  --stack-name webhook-relay-prod \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### Deletion Failed
```bash
# Check what's blocking deletion
aws cloudformation describe-stack-resources \
  --stack-name webhook-relay-prod \
  --region us-east-1 \
  --query 'StackResources[?ResourceStatus!=`DELETE_COMPLETE`]'
```

### S3 Bucket Not Emptying
```bash
# Manually empty bucket
aws s3 rm s3://bucket-name --recursive --region us-east-1

# Delete all versions
aws s3api delete-objects --bucket bucket-name \
  --delete "$(aws s3api list-object-versions \
  --bucket bucket-name \
  --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
```

## 📚 Additional Resources

- [Full Deployment Guide](../DEPLOYMENT_GUIDE.md)
- [CloudFormation Template](./webhook-relay-stack.yaml)
- [AWS CloudFormation Docs](https://docs.aws.amazon.com/cloudformation/)

## ⚠️ Important Notes

1. **Database Password:** Must be at least 8 characters
2. **Region:** Ensure all resources are in the same region
3. **Costs:** Resources incur charges while running
4. **Cleanup:** Always run cleanup-all.sh when done with demo
5. **Backups:** RDS snapshots are retained after deletion

## 🔐 Security

- Database credentials stored in Secrets Manager
- Resources deployed in private subnets
- Security groups restrict access
- IAM roles follow least-privilege principle

---

**Made with Bob**