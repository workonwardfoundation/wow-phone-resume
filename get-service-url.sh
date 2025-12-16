#!/bin/bash

# Helper script to get the public URL of your ECS service
# Run this after deploying to find your service endpoint

set -e

REGION=${AWS_REGION:-us-east-1}
CLUSTER=${CLUSTER_NAME:-wow-phone-resume-cluster}
SERVICE=${SERVICE_NAME:-wow-phone-resume}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Fetching service information...${NC}"
echo "Region: $REGION"
echo "Cluster: $CLUSTER"
echo "Service: $SERVICE"
echo ""

# Check if service exists
if ! aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" >/dev/null 2>&1; then
    echo -e "${RED}Error: Service not found. Make sure you've run ./deploy-to-ecs.sh first.${NC}"
    exit 1
fi

# Get task ARN
echo -e "${YELLOW}Getting task ARN...${NC}"
TASK_ARN=$(aws ecs list-tasks \
    --cluster "$CLUSTER" \
    --service-name "$SERVICE" \
    --region "$REGION" \
    --query 'taskArns[0]' \
    --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
    echo -e "${RED}Error: No running tasks found. The service might be starting up.${NC}"
    echo "Wait a few minutes and try again, or check service status:"
    echo "  aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $REGION"
    exit 1
fi

echo -e "${GREEN}✓ Found task: $TASK_ARN${NC}"

# Get network interface ID
echo -e "${YELLOW}Getting network interface...${NC}"
ENI_ID=$(aws ecs describe-tasks \
    --cluster "$CLUSTER" \
    --tasks "$TASK_ARN" \
    --region "$REGION" \
    --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
    --output text)

if [ -z "$ENI_ID" ] || [ "$ENI_ID" == "None" ]; then
    echo -e "${RED}Error: Could not find network interface.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found network interface: $ENI_ID${NC}"

# Get public IP
echo -e "${YELLOW}Getting public IP address...${NC}"
PUBLIC_IP=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$ENI_ID" \
    --region "$REGION" \
    --query 'NetworkInterfaces[0].Association.PublicIp' \
    --output text)

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; then
    echo -e "${RED}Error: Task does not have a public IP address.${NC}"
    echo "This might mean the task is not running or public IP assignment is disabled."
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Service is running!${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Service URL:${NC}       http://$PUBLIC_IP:8080"
echo -e "${GREEN}Health Check:${NC}     http://$PUBLIC_IP:8080/api/v1/health"
echo -e "${GREEN}API Docs:${NC}         http://$PUBLIC_IP:8080/docs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Twilio Webhook URLs:"
echo -e "${YELLOW}  Incoming Call:${NC}  http://$PUBLIC_IP:8080/api/v1/call/incoming"
echo -e "${YELLOW}  Language:${NC}       http://$PUBLIC_IP:8080/api/v1/call/language"
echo -e "${YELLOW}  Media Stream:${NC}   ws://$PUBLIC_IP:8080/api/v1/media-stream"
echo ""

# Test health endpoint
echo -e "${YELLOW}Testing health endpoint...${NC}"
if curl -s -f "http://$PUBLIC_IP:8080/api/v1/health" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed!${NC}"
else
    echo -e "${RED}✗ Health check failed. The service might still be starting up.${NC}"
    echo "Wait a minute and try accessing the URL manually."
fi

echo ""
echo "View logs:"
echo "  aws logs tail /ecs/$SERVICE --follow --region $REGION"

