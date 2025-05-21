#!/bin/bash
set -e

# Configuration
BASE_BUCKET_NAME="pulumi-state-sql-server"
# Generate a unique suffix using timestamp and random string
TIMESTAMP=$(date +%Y%m%d%H%M%S)
RANDOM_STRING=$(head /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | head -c 6)
BUCKET_NAME="${BASE_BUCKET_NAME}-${TIMESTAMP}-${RANDOM_STRING}"
# Get region from environment or use default
AWS_REGION="${AWS_REGION:-us-east-2}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Pulumi S3 state backend...${NC}"
echo "Using AWS region: ${AWS_REGION}"
echo "Using bucket name: ${BUCKET_NAME}"

# Check if the AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Create S3 bucket if it doesn't exist
echo "Creating S3 bucket for Pulumi state if it doesn't exist..."
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"
    
    # Enable versioning for state recovery
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled

    # Add encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    echo -e "${GREEN}S3 bucket created successfully.${NC}"
else
    echo -e "${GREEN}S3 bucket already exists.${NC}"
fi

# Configure Pulumi to use S3 backend
echo "Configuring Pulumi to use S3 backend..."
pulumi login "s3://$BUCKET_NAME?region=$AWS_REGION"

echo -e "${GREEN}Pulumi S3 state backend setup complete!${NC}"
echo "Your Pulumi state will be stored in s3://$BUCKET_NAME"
echo -e "You can run ${YELLOW}pulumi stack init dev${NC} to create a new stack."

# Save the bucket name to a file for reference
echo "$BUCKET_NAME" > .pulumi-state-bucket 