# CloudFormation Deployment Guide

Complete AWS infrastructure for Webhook Relay & Logger using CloudFormation.

## 📋 What Gets Created

### Networking
- ✅ VPC with public and private subnets across 2 AZs
- ✅ Internet Gateway and NAT Gateway
- ✅ Route tables and security groups

### Database & Cache
- ✅ RDS PostgreSQL 15.4 (Multi-AZ, db.t3.medium)
- ✅ ElastiCache Redis 7.0 (cache.t3.medium)
- ✅ Automated backups and maintenance windows

### Storage
- ✅ S3 bucket with versioning enabled
- ✅ Lifecycle policies (archive after 90 days, delete after 365 days)
- ✅ Server-side encryption (AES256)
- ✅ Public access blocked

### Security
- ✅ IAM roles and policies for services
- ✅ Secrets Manager for database credentials
- ✅ Security groups with least privilege access

### Monitoring
- ✅ CloudWatch Log Groups for all services
- ✅ 30-day log retention

### Tags
All resources are tagged with:
- `Project: webhook-relay`
- `ManagedBy: CloudFormation`
- `Environment: production`

## 🚀 Quick Start

### 1. Deploy the Stack

```bash
cd cloudformation
./deploy.sh --stack-name webhook-relay-prod --region us-east-1
```

You'll be prompted for:
- Database password (min 8 characters)
- Confirmation to proceed

**Deployment time:** ~15-20 minutes

### 2. Get Stack Outputs

After deployment completes:

```bash
./get-outputs.sh --stack-name webhook-relay-prod
```

This shows:
- RDS endpoint and port
- Redis endpoint and port
- S3 bucket name
- Database connection string
- IAM role ARNs

### 3. Export as Environment Variables

```bash
source <(./get-outputs.sh --stack-name webhook-relay-prod --env)
```

### 4. Update Your Application

Update your `.env` file with the outputs:

```bash
DATABASE_URL=<DatabaseURL from outputs>
REDIS_HOST=<RedisEndpoint from outputs>
REDIS_PORT=<RedisPort from outputs>
S3_BUCKET_NAME=<S3BucketName from outputs>
AWS_REGION=us-east-1
```

### 5. Run Database Migrations

```bash
cd ../shared
npx prisma migrate deploy
```

## 🔧 Advanced Usage

### Custom Stack Name

```bash
./deploy.sh --stack-name my-webhook-stack --region us-west-2
```

### Update Existing Stack

```bash
aws cloudformation update-stack \
  --stack-name webhook-relay-prod \
  --template-body file://webhook-relay-stack.yaml \
  --parameters \
    ParameterKey=EnvironmentName,UsePreviousValue=true \
    ParameterKey=DBPassword,UsePreviousValue=true \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

### View Stack Events

```bash
aws cloudformation describe-stack-events \
  --stack-name webhook-relay-prod \
  --region us-east-1 \
  --max-items 20
```

### Get Specific Output

```bash
aws cloudformation describe-stacks \
  --stack-name webhook-relay-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`DatabaseURL`].OutputValue' \
  --output text
```

## 🗑️ Tear Down

### Delete the Stack

```bash
./delete-stack.sh --stack-name webhook-relay-prod --region us-east-1
```

**Important Notes:**
- RDS will create a final snapshot before deletion
- S3 bucket is retained (DeletionPolicy: Retain)
- Deletion takes ~10-15 minutes

### Manually Delete S3 Bucket

After stack deletion, if you want to delete the S3 bucket:

```bash
# List bucket contents
aws s3 ls s3://webhook-relay-prod-payloads-<account-id>

# Delete bucket and all contents
aws s3 rb s3://webhook-relay-prod-payloads-<account-id> --force
```

## 💰 Cost Estimation

Monthly costs (us-east-1, approximate):

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| RDS PostgreSQL | db.t3.medium Multi-AZ | ~$120 |
| ElastiCache Redis | cache.t3.medium | ~$50 |
| NAT Gateway | 1 gateway | ~$32 |
| S3 Storage | 100GB + requests | ~$3-10 |
| Data Transfer | Varies | ~$10-50 |
| **Total** | | **~$215-262/month** |

### Cost Optimization Tips

1. **Use Reserved Instances** for RDS and ElastiCache (~40% savings)
2. **Single AZ** for non-production (remove Multi-AZ from RDS)
3. **Smaller instances** for dev/test:
   - RDS: db.t3.small (~$30/month)
   - Redis: cache.t3.micro (~$12/month)
4. **S3 Lifecycle** policies already configured
5. **Remove NAT Gateway** if services don't need internet access

## 🔐 Security Best Practices

### 1. Rotate Database Password

```bash
# Update in Secrets Manager
aws secretsmanager update-secret \
  --secret-id webhook-relay-prod/database \
  --secret-string '{"username":"webhook_admin","password":"NEW_PASSWORD",...}'

# Update RDS
aws rds modify-db-instance \
  --db-instance-identifier webhook-relay-prod-postgres \
  --master-user-password NEW_PASSWORD
```

### 2. Enable Enhanced Monitoring

Add to RDS configuration:
```yaml
MonitoringInterval: 60
MonitoringRoleArn: !GetAtt RDSMonitoringRole.Arn
```

### 3. Enable VPC Flow Logs

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/webhook-relay
```

### 4. Enable AWS Config

Track configuration changes:
```bash
aws configservice put-configuration-recorder \
  --configuration-recorder name=webhook-relay-config \
  --recording-group allSupported=true
```

## 📊 Monitoring

### CloudWatch Dashboards

Create a dashboard:
```bash
aws cloudwatch put-dashboard \
  --dashboard-name webhook-relay \
  --dashboard-body file://dashboard.json
```

### Alarms

Set up alarms for:
- RDS CPU > 80%
- RDS storage < 20%
- Redis memory > 80%
- NAT Gateway errors

Example:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name webhook-relay-rds-cpu \
  --alarm-description "RDS CPU utilization" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2
```

## 🔄 Backup & Recovery

### RDS Backups

Automated backups are configured:
- Retention: 7 days
- Backup window: 03:00-04:00 UTC
- Maintenance window: Monday 04:00-05:00 UTC

### Manual Snapshot

```bash
aws rds create-db-snapshot \
  --db-instance-identifier webhook-relay-prod-postgres \
  --db-snapshot-identifier webhook-relay-manual-$(date +%Y%m%d)
```

### Restore from Snapshot

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier webhook-relay-restored \
  --db-snapshot-identifier webhook-relay-manual-20240115
```

## 🐛 Troubleshooting

### Stack Creation Failed

1. Check events:
```bash
aws cloudformation describe-stack-events \
  --stack-name webhook-relay-prod \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

2. Common issues:
   - Insufficient IAM permissions
   - Service limits exceeded
   - Invalid parameter values

### Can't Connect to RDS

1. Check security group rules
2. Verify you're connecting from allowed source
3. Check RDS is in available state
4. Verify credentials in Secrets Manager

### S3 Access Denied

1. Check IAM role has S3 permissions
2. Verify bucket policy
3. Check bucket exists in correct region

## 📚 Additional Resources

- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [ElastiCache Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/BestPractices.html)
- [VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)

## 🆘 Support

For issues:
1. Check CloudFormation events
2. Review CloudWatch logs
3. Verify AWS service limits
4. Check AWS Service Health Dashboard

---

**Note:** Always test in a non-production environment first!