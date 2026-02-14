#!/bin/bash

set -e

echo "🚀 Deploying Webhook Relay CloudFormation Stack"
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
DB_PASSWORD=""
DEPLOY_APP="true"

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
        --db-password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --skip-app-deployment)
            DEPLOY_APP="false"
            shift
            ;;
        --help)
            echo "Usage: ./deploy.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME     CloudFormation stack name (default: webhook-relay-prod)"
            echo "  --region REGION           AWS region (default: us-east-1)"
            echo "  --db-password PASS        Database password (will prompt if not provided)"
            echo "  --skip-app-deployment     Skip application deployment to EC2 (infrastructure only)"
            echo "  --help                    Show this help message"
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
    echo "Please install it first: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured.${NC}"
    echo "Please run: aws configure"
    exit 1
fi

# Prompt for database password if not provided
if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}Database password not provided.${NC}"
    read -sp "Enter database password (min 8 characters): " DB_PASSWORD
    echo ""
    
    if [ ${#DB_PASSWORD} -lt 8 ]; then
        echo -e "${RED}❌ Password must be at least 8 characters${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Stack Name: $STACK_NAME"
echo "  Region: $REGION"
echo "  Environment: ${STACK_NAME}"
echo ""

# Confirm deployment
read -p "Deploy stack with these settings? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo -e "${GREEN}📦 Validating CloudFormation template...${NC}"
aws cloudformation validate-template \
    --template-body file://webhook-relay-stack.yaml \
    --region $REGION > /dev/null

echo -e "${GREEN}✅ Template is valid${NC}"

echo ""
echo -e "${GREEN}🚀 Deploying stack...${NC}"
echo "This may take 15-20 minutes..."
echo ""

aws cloudformation create-stack \
    --stack-name $STACK_NAME \
    --template-body file://webhook-relay-stack.yaml \
    --parameters \
        ParameterKey=EnvironmentName,ParameterValue=$STACK_NAME \
        ParameterKey=DBPassword,ParameterValue=$DB_PASSWORD \
    --capabilities CAPABILITY_NAMED_IAM \
    --region $REGION \
    --tags \
        Key=Project,Value=webhook-relay \
        Key=ManagedBy,Value=CloudFormation \
        Key=Environment,Value=production

echo ""
echo -e "${GREEN}Stack creation initiated!${NC}"
echo ""
echo "Monitor progress:"
echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION"
echo ""
echo "Or in AWS Console:"
echo "  https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
echo ""
echo -e "${YELLOW}Waiting for stack creation to complete...${NC}"

aws cloudformation wait stack-create-complete \
    --stack-name $STACK_NAME \
    --region $REGION

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✅ Stack deployed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Get stack outputs
    echo -e "${GREEN}Stack Outputs:${NC}"
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    
    # Deploy application to EC2 if not skipped
    if [ "$DEPLOY_APP" = "true" ]; then
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}🚀 Deploying Application to EC2...${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        
        # Wait a bit for EC2 instance to be fully ready
        echo -e "${YELLOW}Waiting for EC2 instance to be ready...${NC}"
        sleep 30
        
        # Run deployment script
        cd ..
        chmod +x scripts/deploy-to-ec2.sh
        ./scripts/deploy-to-ec2.sh "$STACK_NAME"
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}✅ Complete Deployment Successful!${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            
            # Get Load Balancer URL
            LB_DNS=$(aws cloudformation describe-stacks \
                --stack-name $STACK_NAME \
                --region $REGION \
                --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
                --output text)
            
            echo -e "${GREEN}🌐 Your Application URLs:${NC}"
            echo ""
            echo -e "  Dashboard:      ${GREEN}http://$LB_DNS${NC}"
            echo -e "  Webhook API:    ${GREEN}http://$LB_DNS/webhook${NC}"
            echo -e "  Health Check:   ${GREEN}http://$LB_DNS/health${NC}"
            echo ""
            echo -e "${YELLOW}⏳ Note: Services may take 5-10 minutes to fully start${NC}"
            echo -e "${YELLOW}   Monitor health checks in the AWS Console${NC}"
            echo ""
        else
            echo ""
            echo -e "${YELLOW}⚠️  Infrastructure deployed but application deployment failed${NC}"
            echo -e "${YELLOW}   You can retry with: ./scripts/deploy-to-ec2.sh $STACK_NAME${NC}"
            echo ""
        fi
    else
        echo ""
        echo -e "${GREEN}Next Steps:${NC}"
        echo "1. Deploy application to EC2:"
        echo "   cd .. && ./scripts/deploy-to-ec2.sh $STACK_NAME"
        echo ""
    fi
    
    echo "To get outputs again:"
    echo "  ./get-outputs.sh --stack-name $STACK_NAME --region $REGION"
    echo ""
    echo "To delete everything:"
    echo "  ./delete-stack.sh --stack-name $STACK_NAME --region $REGION --force"
    
else
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}❌ Stack deployment failed!${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "Check the events for details:"
    echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION"
    exit 1
fi

# Made with Bob
