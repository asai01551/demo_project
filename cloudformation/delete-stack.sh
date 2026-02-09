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
        --help)
            echo "Usage: ./delete-stack.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME     CloudFormation stack name (default: webhook-relay-prod)"
            echo "  --region REGION       AWS region (default: us-east-1)"
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

echo -e "${YELLOW}⚠️  WARNING: This will delete the following resources:${NC}"
echo "  - VPC and all networking components"
echo "  - RDS PostgreSQL database (snapshot will be created)"
echo "  - ElastiCache Redis cluster"
echo "  - S3 bucket (will be retained with data)"
echo "  - IAM roles and policies"
echo "  - CloudWatch log groups"
echo "  - Secrets Manager secrets"
echo ""
echo -e "${RED}This action cannot be undone!${NC}"
echo ""

read -p "Are you sure you want to delete stack '$STACK_NAME'? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deletion cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}🗑️  Deleting stack...${NC}"

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
    echo -e "${YELLOW}Note: S3 bucket was retained and still contains data.${NC}"
    echo "To delete the S3 bucket manually:"
    echo "  aws s3 rb s3://${STACK_NAME}-payloads-<account-id> --force --region $REGION"
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
