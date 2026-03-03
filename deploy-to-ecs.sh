#!/bin/bash

# ECS Fargate Deployment Script for wow-phone-resume
# This script can be run by anyone with AWS credentials configured
# Make sure you have AWS CLI installed and configured with appropriate permissions

set -e

# Auto-load .envrc if it exists (for AWS profile configuration)
if [ -f ".envrc" ]; then
    source .envrc
fi

# Check for .env file and load environment variables
if [ ! -f ".env" ]; then
    echo -e "\033[0;31m[ERROR]\033[0m .env file not found!"
    echo -e "\033[0;34m[INFO]\033[0m Please create a .env file with your credentials."
    exit 1
fi

echo -e "\033[0;34m[INFO]\033[0m Loading environment variables from .env file..."
set -a
source .env
set +a

# Validate required environment variables
REQUIRED_VARS=("TWILIO_ACCOUNT_SID" "TWILIO_AUTH_TOKEN" "TWILIO_PHONE_NUMBER" "OPENAI_API_KEY" "OPENAI_REALTIME_MODEL" "DB_URL")
MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "\033[0;31m[ERROR]\033[0m Missing required environment variables in .env file:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

echo -e "\033[0;32m[SUCCESS]\033[0m All required environment variables loaded"

# Configuration - Update these variables or use environment variables
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
SERVICE_NAME="${SERVICE_NAME:-wow-phone-resume}"
CLUSTER_NAME="${CLUSTER_NAME:-wow-phone-resume-cluster}"
ECR_REPOSITORY="${SERVICE_NAME}"
TASK_FAMILY="${SERVICE_NAME}"
DESIRED_COUNT="${DESIRED_COUNT:-1}"
MIN_CAPACITY="${MIN_CAPACITY:-1}"
MAX_CAPACITY="${MAX_CAPACITY:-5}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_info "Checking prerequisites..."

if ! command_exists aws; then
    print_error "AWS CLI is not installed. Please install it from https://aws.amazon.com/cli/"
    exit 1
fi

if ! command_exists docker; then
    print_error "Docker is not installed. Please install it from https://www.docker.com/get-started"
    exit 1
fi

if ! command_exists jq; then
    print_warning "jq is not installed. Installing it is recommended for better JSON handling."
    print_info "You can install it with: sudo apt-get install jq (Linux) or brew install jq (Mac)"
fi

# Get AWS account ID if not provided
if [ -z "$AWS_ACCOUNT_ID" ]; then
    print_info "Fetching AWS Account ID..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Could not determine AWS Account ID. Please set AWS_ACCOUNT_ID environment variable."
        exit 1
    fi
fi

print_success "Using AWS Account ID: $AWS_ACCOUNT_ID"
print_success "Using AWS Region: $AWS_REGION"

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    print_error "Dockerfile not found in current directory!"
    exit 1
fi

# Confirm deployment
echo ""
print_warning "You are about to deploy to:"
echo "  Region: $AWS_REGION"
echo "  Account: $AWS_ACCOUNT_ID"
echo "  Cluster: $CLUSTER_NAME"
echo "  Service: $SERVICE_NAME"
echo ""
read -p "Do you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Deployment cancelled."
    exit 0
fi

# Step 1: Create ECR repository if it doesn't exist
print_info "Step 1/9: Checking ECR repository..."
if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" >/dev/null 2>&1; then
    print_info "Creating ECR repository: $ECR_REPOSITORY"
    aws ecr create-repository \
        --repository-name "$ECR_REPOSITORY" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    print_success "ECR repository created"
else
    print_success "ECR repository already exists"
fi

# Step 2: Login to ECR
print_info "Step 2/9: Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
print_success "Logged into ECR"

# Step 3: Build Docker image
print_info "Step 3/9: Building Docker image..."
IMAGE_TAG="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:latest"
docker build -t "$IMAGE_TAG" .
print_success "Docker image built successfully"

# Step 4: Push image to ECR
print_info "Step 4/9: Pushing Docker image to ECR..."
docker push "$IMAGE_TAG"
print_success "Docker image pushed to ECR"

# Step 5: Create ECS cluster if it doesn't exist
print_info "Step 5/9: Checking ECS cluster..."
if ! aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    print_info "Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    print_success "ECS cluster created"
else
    print_success "ECS cluster already exists"
fi

# Step 6: Create CloudWatch log group if it doesn't exist
print_info "Step 6/9: Checking CloudWatch log group..."
LOG_GROUP="/ecs/$SERVICE_NAME"
# Fix for Git Bash on Windows path conversion
export MSYS_NO_PATHCONV=1
if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region "$AWS_REGION" --query 'logGroups[?logGroupName==`'$LOG_GROUP'`]' --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
    print_info "Creating CloudWatch log group: $LOG_GROUP"
    aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION"
    aws logs put-retention-policy --log-group-name "$LOG_GROUP" --retention-in-days 7 --region "$AWS_REGION"
    print_success "CloudWatch log group created"
else
    print_success "CloudWatch log group already exists"
fi
export MSYS_NO_PATHCONV=0

# Step 7: Create IAM roles if they don't exist
print_info "Step 7/9: Checking IAM roles..."

# Create execution role trust policy
cat > ./ecs-task-execution-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Check if execution role exists
EXECUTION_ROLE_NAME="ecsTaskExecutionRole"
if ! aws iam get-role --role-name "$EXECUTION_ROLE_NAME" >/dev/null 2>&1; then
    print_info "Creating ECS task execution role..."
    aws iam create-role \
        --role-name "$EXECUTION_ROLE_NAME" \
        --assume-role-policy-document file://./ecs-task-execution-trust-policy.json
    
    aws iam attach-role-policy \
        --role-name "$EXECUTION_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    
    # Add Secrets Manager permissions
    cat > /tmp/secrets-manager-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$EXECUTION_ROLE_NAME" \
        --policy-name "SecretsManagerAccess" \
        --policy-document file:///tmp/secrets-manager-policy.json
    
    print_success "ECS task execution role created"
    print_info "Waiting 10 seconds for IAM role propagation..."
    sleep 10
    
    # Clean up temp policy file
    rm -f ./ecs-task-execution-trust-policy.json
else
    print_success "ECS task execution role already exists"
fi

EXECUTION_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$EXECUTION_ROLE_NAME"

# Step 8: Create/Update task definition
print_info "Step 8/9: Registering ECS task definition..."

# Update the task definition template with actual values
TASK_DEF_FILE="ecs-task-definition.json"
TEMP_TASK_DEF="./ecs-task-definition-temp.json"

if [ -f "$TASK_DEF_FILE" ]; then
    # Use existing task definition file and replace placeholders with actual values
    sed -e "s|YOUR_ACCOUNT_ID|$AWS_ACCOUNT_ID|g" \
        -e "s|YOUR_REGION|$AWS_REGION|g" \
        -e "s|PLACEHOLDER_TWILIO_ACCOUNT_SID|$TWILIO_ACCOUNT_SID|g" \
        -e "s|PLACEHOLDER_TWILIO_AUTH_TOKEN|$TWILIO_AUTH_TOKEN|g" \
        -e "s|PLACEHOLDER_TWILIO_PHONE_NUMBER|$TWILIO_PHONE_NUMBER|g" \
        -e "s|PLACEHOLDER_OPENAI_API_KEY|$OPENAI_API_KEY|g" \
        -e "s|PLACEHOLDER_OPENAI_REALTIME_MODEL|$OPENAI_REALTIME_MODEL|g" \
        -e "s|PLACEHOLDER_DB_URL|$DB_URL|g" \
        "$TASK_DEF_FILE" > "$TEMP_TASK_DEF"
else
    print_warning "Task definition file not found. Creating a basic one..."
    cat > "$TEMP_TASK_DEF" << EOF
{
  "family": "$TASK_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "taskRoleArn": "$EXECUTION_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "$SERVICE_NAME",
      "image": "$IMAGE_TAG",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8080,
          "hostPort": 8080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "PORT",
          "value": "8080"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "node -e \"require('http').get('http://localhost:8080/api/v1/health', (res) => process.exit(res.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))\""
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
EOF
    print_warning "NOTE: This task definition does not include secrets. You need to add them manually or use the setup-secrets.sh script."
fi

aws ecs register-task-definition \
    --cli-input-json file://"$TEMP_TASK_DEF" \
    --region "$AWS_REGION"

print_success "Task definition registered"

# Clean up temp file
rm -f "$TEMP_TASK_DEF"

# Step 9: Create or update ECS service
print_info "Step 9/9: Checking ECS service..."

# Get default VPC and subnets
print_info "Fetching VPC and subnet information..."
DEFAULT_VPC=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
if [ -z "$DEFAULT_VPC" ] || [ "$DEFAULT_VPC" == "None" ]; then
    print_error "No default VPC found. Please create a VPC or specify VPC_ID and SUBNET_IDS environment variables."
    exit 1
fi

SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC" --query 'Subnets[*].SubnetId' --output text --region "$AWS_REGION" | tr '\t' ',')
if [ -z "$SUBNETS" ]; then
    print_error "No subnets found in VPC $DEFAULT_VPC"
    exit 1
fi

print_success "Using VPC: $DEFAULT_VPC"
print_success "Using Subnets: $SUBNETS"

# Create security group if it doesn't exist
SG_NAME="${SERVICE_NAME}-sg"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$DEFAULT_VPC" --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null)

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    print_info "Creating security group: $SG_NAME"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group for $SERVICE_NAME ECS service" \
        --vpc-id "$DEFAULT_VPC" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Allow inbound traffic on port 8080
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 8080 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Allow all outbound traffic (default)
    print_success "Security group created: $SG_ID"
else
    print_success "Security group already exists: $SG_ID"
fi

# Check if service exists
if aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --region "$AWS_REGION" --query 'services[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
    print_info "Updating existing ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_FAMILY" \
        --desired-count "$DESIRED_COUNT" \
        --force-new-deployment \
        --region "$AWS_REGION"
    print_success "ECS service updated"
else
    print_info "Creating new ECS service..."
    aws ecs create-service \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --task-definition "$TASK_FAMILY" \
        --desired-count "$DESIRED_COUNT" \
        --launch-type FARGATE \
        --platform-version LATEST \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --region "$AWS_REGION"
    print_success "ECS service created"
fi

# Clean up temporary files
rm -f ./ecs-task-execution-trust-policy.json ./ecs-task-definition-temp.json

echo ""
print_success "🎉 Deployment complete!"
echo ""
print_info "Next steps:"
echo "  1. Wait for the service to stabilize (may take 2-3 minutes)"
echo "  2. Get your service URL:"
echo "     ./get-service-url.sh"
echo ""
echo "  3. Configure Twilio webhook with your service URL"
echo ""
echo "  4. View logs:"
echo "     aws logs tail /ecs/$SERVICE_NAME --follow --region $AWS_REGION"
echo "     OR: ./ecs-manage.sh (interactive menu)"
echo ""
echo "  5. Check service status:"
echo "     aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
print_info "Run './get-service-url.sh' in 2-3 minutes to get your service URL!"
