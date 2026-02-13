#!/bin/bash

set -e

echo "🪣 AWS S3 Bucket Setup for Webhook Relay"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed.${NC}"
    echo "Please install it first: https://aws.amazon.com/cli/"
    exit 1
fi

# Prompt for AWS credentials if not set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo -e "${YELLOW}AWS credentials not found in environment.${NC}"
    echo ""
    read -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -sp "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_REGION
fi

# Prompt for bucket name
read -p "Enter S3 bucket name (default: webhook-relay-payloads-$(date +%s)): " BUCKET_NAME
BUCKET_NAME=${BUCKET_NAME:-webhook-relay-payloads-$(date +%s)}

echo ""
echo -e "${GREEN}Creating S3 bucket: ${BUCKET_NAME}${NC}"

# Create bucket
if aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION} 2>/dev/null; then
    echo -e "${GREEN}✅ Bucket created successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Bucket might already exist or there was an error${NC}"
fi

# Enable versioning
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket ${BUCKET_NAME} \
    --versioning-configuration Status=Enabled \
    --region ${AWS_REGION}

echo -e "${GREEN}✅ Versioning enabled${NC}"

# Set lifecycle policy (optional - archive old payloads after 90 days)
echo "Setting up lifecycle policy..."
cat > /tmp/lifecycle.json <<EOF
{
  "Rules": [{
    "ID": "ArchiveOldPayloads",
    "Status": "Enabled",
    "Prefix": "",
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
    --bucket ${BUCKET_NAME} \
    --lifecycle-configuration file:///tmp/lifecycle.json \
    --region ${AWS_REGION}

echo -e "${GREEN}✅ Lifecycle policy set${NC}"

# Block public access
echo "Blocking public access..."
aws s3api put-public-access-block \
    --bucket ${BUCKET_NAME} \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --region ${AWS_REGION}

echo -e "${GREEN}✅ Public access blocked${NC}"

# Update .env file
echo ""
echo -e "${GREEN}Updating .env file...${NC}"

# Backup existing .env
cp .env .env.backup

# Update or add AWS configuration
if grep -q "AWS_REGION=" .env; then
    sed -i.bak "s|AWS_REGION=.*|AWS_REGION=${AWS_REGION}|g" .env
    sed -i.bak "s|AWS_ACCESS_KEY_ID=.*|AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}|g" .env
    sed -i.bak "s|AWS_SECRET_ACCESS_KEY=.*|AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}|g" .env
    sed -i.bak "s|S3_BUCKET_NAME=.*|S3_BUCKET_NAME=${BUCKET_NAME}|g" .env
else
    echo "" >> .env
    echo "# AWS Configuration (Auto-generated)" >> .env
    echo "AWS_REGION=${AWS_REGION}" >> .env
    echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}" >> .env
    echo "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}" >> .env
    echo "S3_BUCKET_NAME=${BUCKET_NAME}" >> .env
fi

rm -f .env.bak

echo -e "${GREEN}✅ .env file updated${NC}"

# Test bucket access
echo ""
echo "Testing bucket access..."
if aws s3 ls s3://${BUCKET_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo -e "${GREEN}✅ Bucket access verified${NC}"
else
    echo -e "${RED}❌ Could not access bucket${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ S3 Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Bucket Details:"
echo "  Name: ${BUCKET_NAME}"
echo "  Region: ${AWS_REGION}"
echo "  Versioning: Enabled"
echo "  Lifecycle: Archive after 90 days, delete after 365 days"
echo "  Public Access: Blocked"
echo ""
echo "Your .env file has been updated with AWS credentials."
echo "Backup saved to: .env.backup"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Keep your AWS credentials secure!${NC}"
echo ""
echo "You can now start the webhook relay services:"
echo "  cd receiver-service && npm run dev"
echo ""

# Made with Bob
