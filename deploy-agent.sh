#!/bin/bash

# Deployment script for Docker Hybrid Agent Infrastructure
# This script deploys the Docker agent stack with proper error handling

set -e  # Exit on any error

# Configuration file path
CONFIG_FILE="docker-agent-config.json"
HYBRID_AGENT_API_URL="https://api.fivetran.com/v1/hybrid-deployment-agents"

# Default values (will be overridden by config file)
PROJECT_NAME=""
AWS_ACCOUNT="internal-sales"
STACK_NAME=""
CFN_TEMPLATE_FILE="agent-stack.yaml"
AWS_REGION=""
AWS_PROFILE="fivetran"
OWNER="karunakar.veluru@fivetran.com"
TEAM="solution_architects"
ENVIRONMENT="customer_solutions_group"
EXPIRES_ON="2025-08-31"
MANAGED_RESOURCE="true"
EXTERNAL_ID=""
HYBRID_AGENT_TOKEN=""
DEPLOYMENT_MODE="deploy"  # deploy, delete, or status

# Function to check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "Error: jq is not installed or not in PATH. Please install jq to parse JSON."
        exit 1
    fi
}

# Function to check if curl is available
check_curl() {
    if ! command -v curl &> /dev/null; then
        echo "Error: curl is not installed or not in PATH. Please install curl to make API calls."
        exit 1
    fi
}

# Function to read configuration from JSON file
read_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "Error: Configuration file $CONFIG_FILE not found"
        exit 1
    fi
    
    echo "Reading configuration from $CONFIG_FILE..."
    
    # Read all required values from config file
    PROJECT_NAME=$(jq -r '.agent_name' "$CONFIG_FILE")
    EXTERNAL_ID=$(jq -r '.group_id' "$CONFIG_FILE")
    AWS_REGION=$(jq -r '.aws_region' "$CONFIG_FILE")
    MY_IP=$(jq -r '.ip_address_for_ssh_access' "$CONFIG_FILE")
    
    # Read API credentials
    FIVETRAN_API_KEY=$(jq -r '.fivetran_api_key' "$CONFIG_FILE")
    FIVETRAN_API_SECRET=$(jq -r '.fivetran_api_secret' "$CONFIG_FILE")
    
    # Validate that all required values are present and not null
    if [[ "$PROJECT_NAME" == "null" || -z "$PROJECT_NAME" ]]; then
        echo "Error: agent_name is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [[ "$EXTERNAL_ID" == "null" || -z "$EXTERNAL_ID" ]]; then
        echo "Error: group_id is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [[ "$AWS_REGION" == "null" || -z "$AWS_REGION" ]]; then
        echo "Error: aws_region is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [[ "$FIVETRAN_API_KEY" == "null" || -z "$FIVETRAN_API_KEY" ]]; then
        echo "Error: fivetran_api_key is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [[ "$FIVETRAN_API_SECRET" == "null" || -z "$FIVETRAN_API_SECRET" ]]; then
        echo "Error: fivetran_api_secret is required in $CONFIG_FILE"
        exit 1
    fi
    
    if [[ "$MY_IP" == "null" || -z "$MY_IP" ]]; then
        echo "Error: ip_address_for_ssh_access is required in $CONFIG_FILE"
        exit 1
    fi
    
    # Set stack name based on project name
    STACK_NAME="${PROJECT_NAME}-stack"
    
    echo "✓ Configuration loaded successfully"
}

# Function to create agent via API and get token
create_agent_and_get_token() {
    echo "Creating/registering hybrid agent via API..."
    
    # Create payload on the fly
    local payload
    payload=$(cat <<EOF
{
  "accept_terms": "true",
  "display_name": "$PROJECT_NAME",
  "env_type": "DOCKER",
  "auth_type": "AUTO",
  "group_id": "$EXTERNAL_ID"
}
EOF
)
    
    echo "Making API call to create/register agent..."
    
    # Create Basic Auth header
    local auth_header
    auth_header=$(echo -n "${FIVETRAN_API_KEY}:${FIVETRAN_API_SECRET}" | base64)
    
    # Make the API call with Basic Auth
    local response
    response=$(curl -s -X POST "$HYBRID_AGENT_API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Basic $auth_header" \
        -d "$payload" \
        -w "\n%{http_code}")
    
    # Extract HTTP status code (last line)
    # shellcheck disable=SC2155
    local http_code=$(echo "$response" | tail -n1)
    # shellcheck disable=SC2155
    local response_body=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
        # Parse token from response
        HYBRID_AGENT_TOKEN=$(echo "$response_body" | jq -r '.data.token')
        
        if [[ "$HYBRID_AGENT_TOKEN" == "null" || -z "$HYBRID_AGENT_TOKEN" ]]; then
            echo "Error: Could not extract token from API response"
            echo "Response: $response_body"
            exit 1
        fi
        
        echo "✓ Agent registered successfully and token retrieved"
    else
        echo "Error: API call failed with status code $http_code"
        echo "Response: $response_body"
        exit 1
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy    Deploy the Docker agent stack (default)"
    echo "  delete    Delete the infrastructure"
    echo "  status    Check deployment status"
    echo ""
    echo "Options:"
    echo "  -c, --config-file FILE             Configuration file (default: $CONFIG_FILE)"
    echo "  -e, --aws-account AWS_ACCOUNT      AWS Account (default: $AWS_ACCOUNT)"
    echo "  --profile PROFILE                  AWS profile (default: $AWS_PROFILE)"
    echo "  -h, --help                         Display this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy                           # Deploy infrastructure"
    echo "  $0 -c my-config.json deploy"
    echo "  $0 delete                           # Delete infrastructure"
    echo "  $0 status                           # Check status"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        deploy|delete|status)
            DEPLOYMENT_MODE="$1"
            shift
            ;;
        -c|--config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -e|--aws-account)
            AWS_ACCOUNT="$2"
            shift 2
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize configuration
check_jq
check_curl
read_config

# Note: Agent creation will be handled during deployment, not automatically

echo ""
echo "=== Docker Hybrid Agent Infrastructure Deployment ==="
echo ""
echo "Agent Name:                $PROJECT_NAME"
echo "AWS Account:               $AWS_ACCOUNT"
echo "External ID:               $EXTERNAL_ID"
echo "My IP:                     $MY_IP"
echo "Stack Name:                $STACK_NAME"
echo "Template File:             $CFN_TEMPLATE_FILE"
echo "AWS Region:                $AWS_REGION"
echo "AWS Profile:               $AWS_PROFILE"
echo "Deployment Mode:           $DEPLOYMENT_MODE"
if [[ "$DEPLOYMENT_MODE" != "delete" && "$DEPLOYMENT_MODE" != "status" ]]; then
    echo "Agent Token:               [Automatically created during deployment]"
fi
echo ""

# Get user confirmation before proceeding
if [[ "$DEPLOYMENT_MODE" != "status" ]]; then
    if [[ "$DEPLOYMENT_MODE" == "delete" ]]; then
        read -p "Do you want to proceed with deleting the infrastructure? (y/N): " -n 1 -r
    else
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    fi
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        if [[ "$DEPLOYMENT_MODE" == "delete" ]]; then
            echo "Infrastructure deletion cancelled by user."
        else
            echo "Deployment cancelled by user."
        fi
        exit 0
    fi
    echo ""
fi

# Function to check if AWS CLI is available
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI is not installed or not in PATH"
        exit 1
    fi
}

# Function to get stack status
get_stack_status() {
    local stack_name="$1"
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "Stacks[0].StackStatus" \
        --output text 2>/dev/null || echo "STACK_NOT_FOUND"
}

# Function to deploy the Docker agent stack
deploy_stack() {
    echo "Deploying stack: $STACK_NAME"
    
    # Create agent and get token before deployment
    create_agent_and_get_token
    
    # Set AWS region
    aws configure set default.region "${AWS_REGION}"
    
    # Deploy the stack (create or update automatically)
    aws cloudformation deploy \
        --template-file "$CFN_TEMPLATE_FILE" \
        --stack-name "$STACK_NAME" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --parameter-overrides \
            ProjectName="$PROJECT_NAME" \
            Environment="$AWS_ACCOUNT" \
            MyIp="$MY_IP" \
            ExternalId="$EXTERNAL_ID" \
            AgentToken="$HYBRID_AGENT_TOKEN" \
            TeamName="$TEAM" \
            DepartmentName="$ENVIRONMENT" \
            OwnerName="$OWNER" \
            ExpiresOn="$EXPIRES_ON" \
        --tags \
            Name="$STACK_NAME" \
            Project="$PROJECT_NAME" \
            owner="$OWNER" \
            team="$TEAM" \
            environment="$ENVIRONMENT" \
            expires_on="$EXPIRES_ON" \
            ManagedResource="$MANAGED_RESOURCE"
    
    echo "✓ Stack $STACK_NAME deployed successfully"
    
    # Wait for stack to be created/updated
    echo "Waiting for stack $STACK_NAME to be created/updated..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" 2>/dev/null || \
    aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE"
    
    echo "✓ Stack $STACK_NAME is ready"
    
    # Get the instance id from stack outputs
    local instance_id
    instance_id=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "Stacks[0].Outputs[?OutputKey=='AgentInstanceId'].OutputValue" \
        --output text)
    
    if [[ -n "$instance_id" && "$instance_id" != "None" ]]; then
        echo "✓ Agent Instance ID: $instance_id"
    else
        echo "Warning: Could not retrieve Agent Instance ID from stack outputs"
    fi
}

# Function to delete the stack
delete_stack() {
    echo "Deleting stack: $STACK_NAME"
    
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --profile "$AWS_PROFILE" &> /dev/null; then
        aws cloudformation delete-stack \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE"
        
        echo "✓ Stack deletion initiated successfully"
        echo "Note: Stack deletion may take several minutes to complete"
    else
        echo "Stack $STACK_NAME does not exist, nothing to delete"
    fi
}

# Function to show stack status
show_status() {
    echo "Stack Status:"
    echo "============="
    
    local status
    status=$(get_stack_status "$STACK_NAME")
    echo "$STACK_NAME: $status"
    
    if [[ "$status" != "STACK_NOT_FOUND" ]]; then
        echo "  Outputs:"
        aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" \
            --query "Stacks[0].Outputs" \
            --output table 2>/dev/null || echo "    No outputs"
        echo ""
    fi
}

# Function to run post-deployment steps
post_deployment() {
    echo ""
    echo "=== Post-Deployment Steps ==="
    echo "1. Verify the deployment:"
    echo "   $0 status"
    echo ""
    echo "2. Check your Docker agent stack in AWS CloudFormation console"
    echo "3. Verify the agent is running and connected to Fivetran"
}

# Main execution
main() {
    # Check prerequisites
    check_aws_cli
    
    case $DEPLOYMENT_MODE in
        deploy)
            echo "Deploying Docker agent stack..."
            deploy_stack
            post_deployment
            ;;
        delete)
            echo "Warning: This will delete the Docker agent infrastructure!"
            read -p "Are you sure you want to continue? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                delete_stack
            else
                echo "Deletion cancelled"
            fi
            ;;
        status)
            show_status
            ;;
        *)
            echo "Error: Unknown deployment mode '$DEPLOYMENT_MODE'"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
