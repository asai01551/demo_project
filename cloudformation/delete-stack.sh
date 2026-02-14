#!/bin/bash

set -e

echo "🗑️  Deleting Webhook Relay CloudFormation Stack"
echo "=============================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="webhook-relay-prod"
REGION="us-east-1"
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: ./delete-stack.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME     CloudFormation stack name (default: webhook-relay-prod)"
            echo "  --region REGION       AWS region (default: us-east-1)"
            echo "  --force               Skip confirmation prompt"
            echo "  --help                Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed.${NC}"
    exit 1
fi

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
    echo -e "${RED}❌ Stack '$STACK_NAME' not found in region $REGION${NC}"
    exit 1
fi

# Get S3 bucket name from stack outputs
echo -e "${GREEN}📋 Getting stack resources...${NC}"
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text 2>/dev/null || echo "")

echo -e "${YELLOW}⚠️  WARNING: This will delete the following resources:${NC}"
echo "  - EC2 instances and Auto Scaling Group"
echo "  - Application Load Balancer"
echo "  - VPC and all networking components (NAT Gateway, Internet Gateway, etc.)"
echo "  - RDS PostgreSQL database (snapshot will be created)"
echo "  - ElastiCache Redis cluster"
echo "  - S3 bucket and ALL its contents: ${S3_BUCKET:-'(not found)'}"
echo "  - IAM roles and instance profiles"
echo "  - CloudWatch log groups"
echo "  - Secrets Manager secrets"
echo "  - Security groups"
echo ""
echo -e "${RED}This action cannot be undone!${NC}"
echo -e "${RED}All webhook payloads in S3 will be permanently deleted!${NC}"
echo ""

if [ "$FORCE" = false ]; then
    read -p "Are you sure you want to delete stack '$STACK_NAME'? (type 'yes' to confirm): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Deletion cancelled"
        exit 0
    fi
else
    echo -e "${YELLOW}⚠️  Force mode enabled - skipping confirmation${NC}"
fi

# Empty and delete S3 bucket first if it exists
if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "None" ]; then
    echo ""
    echo -e "${GREEN}🗑️  Emptying S3 bucket: $S3_BUCKET${NC}"
    
    # Check if bucket exists
    if aws s3 ls "s3://$S3_BUCKET" --region $REGION &> /dev/null; then
        # Delete all objects and versions
        aws s3 rm "s3://$S3_BUCKET" --recursive --region $REGION || true
        
        # Delete all versions if versioning is enabled
        aws s3api delete-objects --bucket "$S3_BUCKET" --region $REGION \
            --delete "$(aws s3api list-object-versions --bucket "$S3_BUCKET" --region $REGION \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --max-items 1000)" \
            2>/dev/null || true
        
        echo -e "${GREEN}✅ S3 bucket emptied${NC}"
    else
        echo -e "${YELLOW}⚠️  S3 bucket not found or already deleted${NC}"
    fi
fi

echo ""
echo -e "${GREEN}🗑️  Deleting CloudFormation stack...${NC}"

aws cloudformation delete-stack \
    --stack-name $STACK_NAME \
    --region $REGION

echo ""
echo -e "${YELLOW}Waiting for stack deletion to complete...${NC}"
echo "This may take 10-15 minutes..."

aws cloudformation wait stack-delete-complete \
    --stack-name $STACK_NAME \
    --region $REGION

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Stack deleted successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Delete S3 bucket if it still exists
    if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "None" ]; then
        if aws s3 ls "s3://$S3_BUCKET" --region $REGION &> /dev/null; then
            echo -e "${GREEN}🗑️  Deleting S3 bucket: $S3_BUCKET${NC}"
            aws s3 rb "s3://$S3_BUCKET" --force --region $REGION || true
            echo -e "${GREEN}✅ S3 bucket deleted${NC}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}All resources have been deleted!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Deleted resources included:"
    echo "  ✅ EC2 instances and Auto Scaling Group"
    echo "  ✅ Application Load Balancer and Target Groups"
    echo "  ✅ RDS PostgreSQL (snapshot created)"
    echo "  ✅ ElastiCache Redis"
    echo "  ✅ S3 bucket and all payloads"
    echo "  ✅ VPC and networking"
    echo "  ✅ IAM roles and policies"
    echo "  ✅ CloudWatch logs"
    echo "  ✅ Secrets Manager secrets"
    echo ""
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ Stack deletion failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Check the events for details:"
    echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION"
    exit 1
fi

# Made with Bob
