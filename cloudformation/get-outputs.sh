#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
STACK_NAME="webhook-relay-prod"
REGION="us-east-1"
FORMAT="table"

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
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --env)
            FORMAT="env"
            shift
            ;;
        --help)
            echo "Usage: ./get-outputs.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME     CloudFormation stack name (default: webhook-relay-prod)"
            echo "  --region REGION       AWS region (default: us-east-1)"
            echo "  --format FORMAT       Output format: table, json, env (default: table)"
            echo "  --env                 Output as environment variables"
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

if [ "$FORMAT" = "env" ]; then
    # Output as environment variables
    echo "# Webhook Relay CloudFormation Stack Outputs"
    echo "# Generated: $(date)"
    echo "# Stack: $STACK_NAME"
    echo "# Region: $REGION"
    echo ""
    
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output text | while read key value; do
        echo "export ${key}=\"${value}\""
    done
    
    echo ""
    echo "# To use these variables, run:"
    echo "# source <(./get-outputs.sh --stack-name $STACK_NAME --region $REGION --env)"
    
elif [ "$FORMAT" = "json" ]; then
    # Output as JSON
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs'
else
    # Output as table (default)
    echo -e "${GREEN}Stack Outputs for: $STACK_NAME${NC}"
    echo ""
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue,Description]' \
        --output table
fi

# Made with Bob
