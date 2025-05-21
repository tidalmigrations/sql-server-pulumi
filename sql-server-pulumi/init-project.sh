#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Initializing SQL Server Pulumi project...${NC}"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Please install it first."
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "npm is not installed. Please install it first."
    exit 1
fi

# Check if Pulumi is installed
if ! command -v pulumi &> /dev/null; then
    echo "Pulumi CLI is not installed. Please install it first."
    exit 1
fi

# Install dependencies
echo "Installing project dependencies..."
npm install

echo -e "${GREEN}Dependencies installed successfully.${NC}"

# Check if we're using S3 backend
if [[ $(pulumi whoami --verbose | grep "Backend URL:" | cut -d' ' -f3) == s3* ]]; then
    echo -e "${GREEN}Using S3 state backend: $(pulumi whoami --verbose | grep "Backend URL:" | cut -d' ' -f3)${NC}"
else
    echo -e "${YELLOW}Using local state backend. If you want to use S3 backend, run ./setup-s3-state-backend.sh${NC}"
fi

# Check if stack already exists
if pulumi stack ls | grep -q "dev"; then
    echo -e "${GREEN}Stack 'dev' already exists.${NC}"
else
    echo "Creating new stack 'dev'..."
    pulumi stack init dev
    echo -e "${GREEN}Stack 'dev' created successfully.${NC}"
fi

echo -e "${GREEN}Project initialization complete!${NC}"
echo -e "You can now run ${YELLOW}pulumi up${NC} to deploy the infrastructure." 