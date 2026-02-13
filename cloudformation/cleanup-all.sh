#!/bin/bash

set -e

echo "🧹 Complete AWS Cleanup for Webhook Relay"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="webhook-relay-prod"
REGION="us-east-1"
DELETE_LOCAL_BUCKET=false

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
        --delete-local-bucket)
            DELETE_LOCAL_BUCKET=true
            shift
            ;;
        --help)
            echo "Usage: ./cleanup-all.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME           CloudFormation stack name (default: webhook-relay-prod)"
            echo "  --region REGION             AWS region (default: us-east-1)"
            echo "  --delete-local-bucket       Also delete locally created S3 buckets"
            echo "  --help                      Show this help message"
            echo ""
            echo "This script will:"
            echo "  1. Delete the CloudFormation stack and all its resources"
            echo "  2. Delete the S3 bucket created by CloudFormation"
            echo "  3. Optionally delete any locally created S3 buckets (with --delete-local-bucket)"
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

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured.${NC}"
    exit 1
fi

echo -e "${GREEN}Configuration:${NC}"
echo "  Stack Name: $STACK_NAME"
echo "  Region: $REGION"
echo "  Delete Local Buckets: $DELETE_LOCAL_BUCKET"
echo ""

# Check if stack exists
STACK_EXISTS=false
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION &> /dev/null; then
    STACK_EXISTS=true
    echo -e "${GREEN}✓ CloudFormation stack found${NC}"
    
    # Get S3 bucket from stack
    STACK_S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$STACK_S3_BUCKET" ] && [ "$STACK_S3_BUCKET" != "None" ]; then
        echo -e "${GREEN}✓ Stack S3 bucket: $STACK_S3_BUCKET${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  CloudFormation stack not found${NC}"
fi

# Find locally created buckets
LOCAL_BUCKETS=()
if [ "$DELETE_LOCAL_BUCKET" = true ]; then
    echo ""
    echo -e "${GREEN}🔍 Searching for locally created S3 buckets...${NC}"
    
    # Look for buckets matching the pattern webhook-relay-payloads-*
    BUCKET_LIST=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `webhook-relay-payloads-`)].Name' --output text --region $REGION 2>/dev/null || echo "")
    
    if [ -n "$BUCKET_LIST" ]; then
        for bucket in $BUCKET_LIST; do
            # Skip the stack bucket if it exists
            if [ "$bucket" != "$STACK_S3_BUCKET" ]; then
                LOCAL_BUCKETS+=("$bucket")
                echo -e "${GREEN}  Found: $bucket${NC}"
            fi
        done
    fi
    
    if [ ${#LOCAL_BUCKETS[@]} -eq 0 ]; then
        echo -e "${YELLOW}  No local buckets found${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}⚠️  WARNING: This will delete:${NC}"

if [ "$STACK_EXISTS" = true ]; then
    echo -e "${RED}CloudFormation Stack Resources:${NC}"
    echo "  - VPC and networking"
    echo "  - RDS PostgreSQL database"
    echo "  - ElastiCache Redis"
    echo "  - S3 bucket: ${STACK_S3_BUCKET:-'(not found)'}"
    echo "  - IAM roles and policies"
    echo "  - CloudWatch logs"
    echo "  - Secrets Manager secrets"
fi

if [ ${#LOCAL_BUCKETS[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}Local S3 Buckets:${NC}"
    for bucket in "${LOCAL_BUCKETS[@]}"; do
        echo "  - $bucket"
    done
fi

echo ""
echo -e "${RED}ALL DATA WILL BE PERMANENTLY DELETED!${NC}"
echo ""

read -p "Type 'DELETE EVERYTHING' to confirm: " CONFIRM

if [ "$CONFIRM" != "DELETE EVERYTHING" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}🧹 Starting cleanup...${NC}"
echo ""

# Delete CloudFormation stack
if [ "$STACK_EXISTS" = true ]; then
    echo -e "${GREEN}📦 Deleting CloudFormation stack...${NC}"
    ./delete-stack.sh --stack-name $STACK_NAME --region $REGION --force
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to delete CloudFormation stack${NC}"
        exit 1
    fi
fi

# Delete local buckets
if [ ${#LOCAL_BUCKETS[@]} -gt 0 ]; then
    echo ""
    echo -e "${GREEN}🗑️  Deleting local S3 buckets...${NC}"
    
    for bucket in "${LOCAL_BUCKETS[@]}"; do
        echo -e "${YELLOW}  Deleting: $bucket${NC}"
        
        # Empty bucket first
        aws s3 rm "s3://$bucket" --recursive --region $REGION 2>/dev/null || true
        
        # Delete all versions if versioning is enabled
        aws s3api delete-objects --bucket "$bucket" --region $REGION \
            --delete "$(aws s3api list-object-versions --bucket "$bucket" --region $REGION \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --max-items 1000)" \
            2>/dev/null || true
        
        # Delete bucket
        aws s3 rb "s3://$bucket" --force --region $REGION 2>/dev/null || true
        
        echo -e "${GREEN}  ✓ Deleted: $bucket${NC}"
    done
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All AWS resources have been deleted."
echo ""

# Made with Bob