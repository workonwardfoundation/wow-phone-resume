#!/bin/bash

# Cloud Run Deployment Script
# Make sure you have gcloud CLI installed and authenticated

set -e

# Configuration - Update these variables
PROJECT_ID="workonward"  # Your GCP Project ID
SERVICE_NAME="wow-phone-resume"
REGION="us-east1"  # Closest to New York
IMAGE_NAME="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Cloud Run deployment for ${SERVICE_NAME}...${NC}"

# Check if PROJECT_ID is set
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}ERROR: Please set PROJECT_ID variable in this script${NC}"
    echo "Update the PROJECT_ID variable at the top of this script with your GCP project ID"
    exit 1
fi

# Set the project
echo -e "${YELLOW}Setting GCP project to: ${PROJECT_ID}${NC}"
gcloud config set project $PROJECT_ID

# Enable required APIs
echo -e "${YELLOW}Enabling required GCP APIs...${NC}"
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable containerregistry.googleapis.com

# Build and submit to Cloud Build
echo -e "${YELLOW}Building Docker image with Cloud Build...${NC}"
gcloud builds submit --tag $IMAGE_NAME

# Deploy to Cloud Run
echo -e "${YELLOW}Deploying to Cloud Run...${NC}"
gcloud run deploy $SERVICE_NAME \
  --image $IMAGE_NAME \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --port 8080 \
  --memory 1Gi \
  --cpu 1 \
  --timeout 300 \
  --max-instances 10 \
  --set-env-vars NODE_ENV=production

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Set your environment variables in Cloud Run console"
echo "2. Your service URL will be displayed above"
echo "3. Update your Twilio webhooks to point to your new Cloud Run URL"

# Get the service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
echo -e "${GREEN}Health check: ${SERVICE_URL}/api/v1/health${NC}"
