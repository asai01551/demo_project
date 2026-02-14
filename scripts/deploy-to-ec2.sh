#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Webhook Relay - Deploy to EC2 ===${NC}"

# Get stack name
STACK_NAME=${1:-webhook-relay-prod}

echo -e "${YELLOW}Getting EC2 instance information...${NC}"

# Get instance ID from Auto Scaling Group
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "${STACK_NAME}-asg" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
  echo -e "${RED}Error: No EC2 instance found in Auto Scaling Group${NC}"
  exit 1
fi

echo -e "${GREEN}Found instance: $INSTANCE_ID${NC}"

# Get instance public IP
INSTANCE_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo -e "${GREEN}Instance IP: $INSTANCE_IP${NC}"

# Get stack outputs
echo -e "${YELLOW}Getting stack configuration...${NC}"
DB_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`RDSEndpoint`].OutputValue' \
  --output text)

REDIS_ENDPOINT=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`RedisEndpoint`].OutputValue' \
  --output text)

S3_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
  --output text)

DB_URL=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`DatabaseURL`].OutputValue' \
  --output text)

REDIS_PORT=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`RedisPort`].OutputValue' \
  --output text)

AWS_REGION=$(aws configure get region)

echo -e "${YELLOW}Creating deployment package...${NC}"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy project files
cp -r . "$TEMP_DIR/webhook-relay"
cd "$TEMP_DIR/webhook-relay"

# Remove node_modules and build artifacts
find . -name "node_modules" -type d -prune -exec rm -rf {} +
find . -name "dist" -type d -prune -exec rm -rf {} +
find . -name ".git" -type d -prune -exec rm -rf {} +

# Create .env file
cat > .env << EOF
NODE_ENV=production
DATABASE_URL=$DB_URL
REDIS_HOST=$REDIS_ENDPOINT
REDIS_PORT=$REDIS_PORT
S3_BUCKET_NAME=$S3_BUCKET
AWS_REGION=$AWS_REGION
PORT=3001
EOF

# Create deployment archive
cd ..
tar -czf webhook-relay.tar.gz webhook-relay/

echo -e "${YELLOW}Uploading to S3...${NC}"

# Upload to S3
aws s3 cp webhook-relay.tar.gz "s3://$S3_BUCKET/deployments/webhook-relay-$(date +%Y%m%d-%H%M%S).tar.gz"
aws s3 cp webhook-relay.tar.gz "s3://$S3_BUCKET/deployments/webhook-relay-latest.tar.gz"

echo -e "${YELLOW}Deploying to EC2 instance...${NC}"

# Create deployment script for EC2
cat > deploy-on-ec2.sh << 'DEPLOY_SCRIPT'
#!/bin/bash
set -e

echo "=== Starting deployment on EC2 ==="

# Download from S3
cd /tmp
aws s3 cp s3://S3_BUCKET_PLACEHOLDER/deployments/webhook-relay-latest.tar.gz .

# Extract
rm -rf /opt/webhook-relay
mkdir -p /opt/webhook-relay
tar -xzf webhook-relay-latest.tar.gz -C /opt
mv /opt/webhook-relay/webhook-relay/* /opt/webhook-relay/
rmdir /opt/webhook-relay/webhook-relay

cd /opt/webhook-relay

# Install dependencies for shared module
echo "Installing shared dependencies..."
cd shared
npm install --production
npm run build

# Build shared module
cd ..

# Install and build each service
for service in receiver-service logger-service forwarder-service dashboard-service; do
  echo "Setting up $service..."
  cd /opt/webhook-relay/$service
  npm install --production
  npm run build || true
done

cd /opt/webhook-relay

# Run database migrations
echo "Running database migrations..."
cd shared
npx prisma migrate deploy || echo "Migration failed or already applied"
cd ..

# Stop existing services
pm2 delete all || true

# Start services with PM2
echo "Starting services..."

cd /opt/webhook-relay/receiver-service
pm2 start dist/index.js --name receiver-service --env production

cd /opt/webhook-relay/logger-service
pm2 start dist/index.js --name logger-service --env production

cd /opt/webhook-relay/forwarder-service
pm2 start dist/index.js --name forwarder-service --env production

cd /opt/webhook-relay/dashboard-service
pm2 start dist/index.js --name dashboard-service --env production

# Save PM2 configuration
pm2 save
pm2 startup systemd -u ec2-user --hp /home/ec2-user

echo "=== Deployment complete ==="
pm2 status
DEPLOY_SCRIPT

# Replace S3 bucket placeholder
sed -i.bak "s|S3_BUCKET_PLACEHOLDER|$S3_BUCKET|g" deploy-on-ec2.sh
rm deploy-on-ec2.sh.bak

# Copy and execute deployment script on EC2
echo -e "${YELLOW}Executing deployment on EC2...${NC}"

# Note: This requires SSH key access. For production, use AWS Systems Manager Session Manager
# For now, we'll use SSM to run commands
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    'sudo su -',
    '$(cat deploy-on-ec2.sh | base64)'
  ]" \
  --output text

echo -e "${GREEN}=== Deployment initiated ===${NC}"
echo -e "${YELLOW}Note: Deployment is running in the background on EC2${NC}"
echo -e "${YELLOW}Check CloudWatch Logs for deployment status${NC}"

# Get Load Balancer URL
LB_DNS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)

echo ""
echo -e "${GREEN}=== Deployment Information ===${NC}"
echo -e "Load Balancer URL: ${GREEN}http://$LB_DNS${NC}"
echo -e "Dashboard URL: ${GREEN}http://$LB_DNS${NC}"
echo -e "Webhook API URL: ${GREEN}http://$LB_DNS/webhook${NC}"
echo -e "Instance ID: ${GREEN}$INSTANCE_ID${NC}"
echo -e "Instance IP: ${GREEN}$INSTANCE_IP${NC}"
echo ""
echo -e "${YELLOW}Wait 5-10 minutes for services to start and health checks to pass${NC}"

# Made with Bob
