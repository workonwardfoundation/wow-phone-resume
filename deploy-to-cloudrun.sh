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

# Check if Dockerfile exists
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}ERROR: Dockerfile not found!${NC}"
    echo "Make sure you have a Dockerfile in the current directory"
    exit 1
fi

echo -e "${GREEN}✅ Environment variables configured and ready for deployment${NC}"

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
  --memory 2Gi \
  --cpu 1 \
  --timeout 3600 \
  --max-instances 5 \
  --min-instances 1 \
  --set-env-vars NODE_ENV=production,TWILIO_ACCOUNT_SID="AC4bdd790ee3a3bb5d6b49c771a03e99d2",TWILIO_AUTH_TOKEN="19aebc8d4b3efd93a296859d25220631",TWILIO_PHONE_NUMBER="+16469561232",AZURE_OPENAI_ENDPOINT="https://wow-rg-ai.cognitiveservices.azure.com",AZURE_OPENAI_API_KEY="3U2zukcSZWNDiT999h4XnH7QPXoIeXgnwDBcSce6VI4dWW3h23dxJQQJ99BEACHYHv6XJ3w3AAAAACOGqCmH",AZURE_OPENAI_DEPLOYMENT_NAME="gpt-4o-realtime-preview",DB_URL="mongodb+srv://bloombook:AUxKDrIdvbdcl9eH@cluster0.44rdqx8.mongodb.net"

echo -e "${GREEN}✅ Deployment complete!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. ✅ Environment variables are configured"
echo "2. Update your Twilio phone number (+16469561232) webhook URLs to:"
echo "   - Incoming calls: \${SERVICE_URL}/api/v1/call/incoming"
echo "   - Language selection: \${SERVICE_URL}/api/v1/call/language" 
echo "   - Media stream: \${SERVICE_URL}/api/v1/media-stream"
echo "3. Test by calling +16469561232 to verify the deployment works"
echo ""

# Get the service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
echo -e "${GREEN}Health check: ${SERVICE_URL}/api/v1/health${NC}"
