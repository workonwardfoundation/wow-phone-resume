#!/bin/bash

# ECS Management Helper Script
# Provides common management tasks for your ECS deployment

set -e

REGION=${AWS_REGION:-us-east-1}
CLUSTER=${CLUSTER_NAME:-wow-phone-resume-cluster}
SERVICE=${SERVICE_NAME:-wow-phone-resume}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

show_menu() {
    clear
    print_header "ECS Management Console - $SERVICE"
    echo "Region: $REGION"
    echo "Cluster: $CLUSTER"
    echo "Service: $SERVICE"
    echo ""
    echo "1)  Service Status"
    echo "2)  View Logs (Live)"
    echo "3)  View Recent Logs"
    echo "4)  Get Service URL"
    echo "5)  Restart Service"
    echo "6)  Scale Service"
    echo "7)  Stop Service"
    echo "8)  Start Service"
    echo "9)  Update Secrets"
    echo "10) View Task Details"
    echo "11) View Service Metrics"
    echo "12) Deploy New Version"
    echo "13) Rollback to Previous Version"
    echo "14) Delete Service"
    echo "15) Delete Everything (Cleanup)"
    echo ""
    echo "0) Exit"
    echo ""
    read -p "Select option: " choice
    echo ""
}

service_status() {
    print_header "Service Status"
    
    if ! aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" >/dev/null 2>&1; then
        print_error "Service not found!"
        return 1
    fi
    
    STATUS=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].status' --output text)
    DESIRED=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].desiredCount' --output text)
    RUNNING=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].runningCount' --output text)
    PENDING=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].pendingCount' --output text)
    
    echo "Status:         $STATUS"
    echo "Desired Tasks:  $DESIRED"
    echo "Running Tasks:  $RUNNING"
    echo "Pending Tasks:  $PENDING"
    echo ""
    
    if [ "$RUNNING" -gt 0 ]; then
        print_success "Service is running!"
    else
        print_error "No tasks are running!"
    fi
    
    echo ""
    print_info "Recent Events:"
    aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].events[:5].[createdAt,message]' --output table
}

view_logs_live() {
    print_header "Live Logs"
    print_info "Streaming logs... (Press Ctrl+C to stop)"
    echo ""
    aws logs tail "/ecs/$SERVICE" --follow --region "$REGION"
}

view_logs_recent() {
    print_header "Recent Logs"
    read -p "How many minutes of logs? (default: 10): " minutes
    minutes=${minutes:-10}
    
    print_info "Fetching logs from last $minutes minutes..."
    echo ""
    aws logs tail "/ecs/$SERVICE" --since "${minutes}m" --region "$REGION"
}

get_service_url() {
    print_header "Service URL"
    ./get-service-url.sh
}

restart_service() {
    print_header "Restart Service"
    print_info "This will force a new deployment and restart all tasks..."
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ $confirm =~ ^[Yy][Ee][Ss]$ ]]; then
        aws ecs update-service \
            --cluster "$CLUSTER" \
            --service "$SERVICE" \
            --force-new-deployment \
            --region "$REGION" >/dev/null
        print_success "Service restart initiated!"
        print_info "It may take a few minutes for new tasks to start."
    else
        print_info "Cancelled."
    fi
}

scale_service() {
    print_header "Scale Service"
    
    CURRENT=$(aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION" --query 'services[0].desiredCount' --output text)
    echo "Current desired count: $CURRENT"
    echo ""
    read -p "Enter new desired count: " count
    
    if [[ ! $count =~ ^[0-9]+$ ]]; then
        print_error "Invalid number!"
        return 1
    fi
    
    print_info "Scaling service to $count tasks..."
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --desired-count "$count" \
        --region "$REGION" >/dev/null
    
    print_success "Service scaled to $count tasks!"
}

stop_service() {
    print_header "Stop Service"
    print_info "This will scale the service to 0 tasks (stop all containers)..."
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ $confirm =~ ^[Yy][Ee][Ss]$ ]]; then
        aws ecs update-service \
            --cluster "$CLUSTER" \
            --service "$SERVICE" \
            --desired-count 0 \
            --region "$REGION" >/dev/null
        print_success "Service stopped (scaled to 0)!"
    else
        print_info "Cancelled."
    fi
}

start_service() {
    print_header "Start Service"
    read -p "How many tasks to start? (default: 1): " count
    count=${count:-1}
    
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --desired-count "$count" \
        --region "$REGION" >/dev/null
    
    print_success "Service started with $count task(s)!"
}

update_secrets() {
    print_header "Update Secrets"
    ./setup-secrets.sh
    echo ""
    print_info "After updating secrets, you may need to restart the service."
    read -p "Restart service now? (yes/no): " restart
    
    if [[ $restart =~ ^[Yy][Ee][Ss]$ ]]; then
        restart_service
    fi
}

view_task_details() {
    print_header "Task Details"
    
    TASK_ARN=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name "$SERVICE" --region "$REGION" --query 'taskArns[0]' --output text)
    
    if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
        print_error "No running tasks found!"
        return 1
    fi
    
    print_info "Task ARN: $TASK_ARN"
    echo ""
    aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" --query 'tasks[0]' --output json | head -n 50
}

view_metrics() {
    print_header "Service Metrics (Last Hour)"
    
    START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
    
    print_info "Fetching CPU utilization..."
    aws cloudwatch get-metric-statistics \
        --namespace AWS/ECS \
        --metric-name CPUUtilization \
        --dimensions Name=ServiceName,Value="$SERVICE" Name=ClusterName,Value="$CLUSTER" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Average Maximum \
        --region "$REGION" \
        --query 'Datapoints | sort_by(@, &Timestamp)[-5:].[Timestamp,Average,Maximum]' \
        --output table
    
    echo ""
    print_info "Fetching memory utilization..."
    aws cloudwatch get-metric-statistics \
        --namespace AWS/ECS \
        --metric-name MemoryUtilization \
        --dimensions Name=ServiceName,Value="$SERVICE" Name=ClusterName,Value="$CLUSTER" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Average Maximum \
        --region "$REGION" \
        --query 'Datapoints | sort_by(@, &Timestamp)[-5:].[Timestamp,Average,Maximum]' \
        --output table
}

deploy_new_version() {
    print_header "Deploy New Version"
    print_info "This will run the deployment script..."
    ./deploy-to-ecs.sh
}

rollback() {
    print_header "Rollback to Previous Version"
    
    print_info "Fetching task definition history..."
    aws ecs list-task-definitions --family-prefix "$SERVICE" --region "$REGION" --query 'taskDefinitionArns[-5:]' --output table
    
    echo ""
    read -p "Enter task definition ARN or revision number to rollback to: " task_def
    
    if [ -z "$task_def" ]; then
        print_error "No task definition provided!"
        return 1
    fi
    
    # If it's just a number, construct full ARN
    if [[ $task_def =~ ^[0-9]+$ ]]; then
        task_def="$SERVICE:$task_def"
    fi
    
    print_info "Rolling back to $task_def..."
    aws ecs update-service \
        --cluster "$CLUSTER" \
        --service "$SERVICE" \
        --task-definition "$task_def" \
        --region "$REGION" >/dev/null
    
    print_success "Rollback initiated!"
}

delete_service() {
    print_header "Delete Service"
    print_error "WARNING: This will delete the ECS service!"
    print_info "The cluster and other resources will remain."
    echo ""
    read -p "Type 'DELETE' to confirm: " confirm
    
    if [ "$confirm" == "DELETE" ]; then
        print_info "Deleting service..."
        aws ecs delete-service \
            --cluster "$CLUSTER" \
            --service "$SERVICE" \
            --force \
            --region "$REGION" >/dev/null
        print_success "Service deleted!"
    else
        print_info "Cancelled."
    fi
}

cleanup_all() {
    print_header "Delete Everything (Complete Cleanup)"
    print_error "WARNING: This will delete ALL resources:"
    echo "  - ECS Service"
    echo "  - ECS Cluster"
    echo "  - ECR Repository and all images"
    echo "  - CloudWatch Log Group"
    echo "  - Security Group"
    echo ""
    read -p "Type 'DELETE EVERYTHING' to confirm: " confirm
    
    if [ "$confirm" == "DELETE EVERYTHING" ]; then
        print_info "Starting cleanup..."
        
        # Delete service
        print_info "Deleting ECS service..."
        aws ecs delete-service --cluster "$CLUSTER" --service "$SERVICE" --force --region "$REGION" 2>/dev/null || true
        
        # Wait a bit
        sleep 5
        
        # Delete cluster
        print_info "Deleting ECS cluster..."
        aws ecs delete-cluster --cluster "$CLUSTER" --region "$REGION" 2>/dev/null || true
        
        # Delete ECR repository
        print_info "Deleting ECR repository..."
        aws ecr delete-repository --repository-name "$SERVICE" --force --region "$REGION" 2>/dev/null || true
        
        # Delete CloudWatch log group
        print_info "Deleting CloudWatch log group..."
        aws logs delete-log-group --log-group-name "/ecs/$SERVICE" --region "$REGION" 2>/dev/null || true
        
        # Delete security group
        print_info "Deleting security group..."
        SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${SERVICE}-sg" --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null)
        if [ ! -z "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
            aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" 2>/dev/null || true
        fi
        
        print_success "Cleanup complete!"
        print_info "Note: Secrets in AWS Secrets Manager were not deleted. Delete them manually if needed."
    else
        print_info "Cancelled."
    fi
}

# Main loop
while true; do
    show_menu
    
    case $choice in
        1) service_status ;;
        2) view_logs_live ;;
        3) view_logs_recent ;;
        4) get_service_url ;;
        5) restart_service ;;
        6) scale_service ;;
        7) stop_service ;;
        8) start_service ;;
        9) update_secrets ;;
        10) view_task_details ;;
        11) view_metrics ;;
        12) deploy_new_version ;;
        13) rollback ;;
        14) delete_service ;;
        15) cleanup_all ;;
        0) 
            echo "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
done

