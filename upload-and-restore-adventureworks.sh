#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_FILE="adventureworks/AdventureWorksLT2016.bak"
DB_NAME="AdventureWorksLT"
PULUMI_DIR="./sql-server-pulumi"
AUTO_RESTORE=false
QUERY_AFTER_RESTORE=false
DEBUG_MODE=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-restore)
            AUTO_RESTORE=true
            shift
            ;;
        --query-after-restore)
            QUERY_AFTER_RESTORE=true
            AUTO_RESTORE=true  # Auto restore is required if we want to query
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --auto-restore         Automatically restore the database after upload"
            echo "  --query-after-restore  Run a test query after restoring the database"
            echo "  --debug                Enable debug mode with verbose output"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Starting AdventureWorks database upload and restore script generation...${NC}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if the backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Backup file $BACKUP_FILE does not exist.${NC}"
    exit 1
fi

# Check if Pulumi is available and stack is initialized
if ! command -v pulumi &> /dev/null; then
    echo -e "${RED}Pulumi CLI is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if sqlcmd is installed if auto-restore is enabled
if [ "$AUTO_RESTORE" = true ] && ! command -v sqlcmd &> /dev/null; then
    echo -e "${RED}sqlcmd is not installed. Please install it first."
    echo -e "See the README-adventureworks.md file for installation instructions.${NC}"
    exit 1
fi

# Change to Pulumi directory
cd $PULUMI_DIR

# Check if setupAdventureWorks config is set to true
SETUP_AW_CONFIG=$(pulumi config get setupAdventureWorks 2>/dev/null)
if [ "$SETUP_AW_CONFIG" != "true" ]; then
    echo -e "${YELLOW}Setting 'setupAdventureWorks' to true in Pulumi config...${NC}"
    pulumi config set setupAdventureWorks true
    
    echo -e "${YELLOW}Running Pulumi update to create required infrastructure...${NC}"
    pulumi up --yes
    
    echo -e "${GREEN}AdventureWorks infrastructure setup complete.${NC}"
else
    echo -e "${GREEN}AdventureWorks infrastructure already set up in Pulumi config.${NC}"
fi

# Get the S3 bucket name from Pulumi outputs
echo -e "${YELLOW}Getting S3 bucket name from Pulumi outputs...${NC}"
S3_BUCKET=$(pulumi stack output adventureWorksS3Bucket)

if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}Failed to get S3 bucket name from Pulumi outputs. Make sure the Pulumi stack is deployed with setupAdventureWorks=true.${NC}"
    exit 1
fi

# Get RDS instance details
echo -e "${YELLOW}Getting RDS instance details from Pulumi...${NC}"
RDS_ENDPOINT=$(pulumi stack output sqlServerEndpoint)
DB_USERNAME=$(pulumi config get dbUsername)

if [ -z "$RDS_ENDPOINT" ]; then
    echo -e "${RED}Failed to get RDS endpoint from Pulumi. Is the stack deployed?${NC}"
    exit 1
fi

DB_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
DB_PORT=$(echo $RDS_ENDPOINT | cut -d':' -f2)
DB_PORT=${DB_PORT:-1433}

echo -e "${YELLOW}SQL Server details:${NC}"
echo -e "  Host: $DB_HOST"
echo -e "  Port: $DB_PORT"
echo -e "  Username: $DB_USERNAME"

# Retrieve the DB password from AWS Secrets Manager
echo -e "${YELLOW}Retrieving SQL Server password from AWS Secrets Manager...${NC}"
# Get the project and stack names to construct the secret name
# Get project name from Pulumi.yaml
PROJECT_NAME=$(grep "^name:" Pulumi.yaml | cut -d':' -f2 | tr -d ' ')

# Get current stack name
STACK_NAME=$(pulumi stack --show-name 2>/dev/null)

# If the stack name contains a slash, it means we got org/project/stack format
if [[ "$STACK_NAME" == *"/"* ]]; then
    # Extract just the stack name (last part after the last slash)
    STACK_NAME=$(echo $STACK_NAME | rev | cut -d'/' -f1 | rev)
fi

SECRET_NAME="rds/${PROJECT_NAME}-${STACK_NAME}/sqlserver-database-1/password"

if [ "$DEBUG_MODE" = true ]; then
    echo -e "${BLUE}Debug: Project name: $PROJECT_NAME${NC}"
    echo -e "${BLUE}Debug: Stack name: $STACK_NAME${NC}"
fi

echo -e "${BLUE}Using secret name: $SECRET_NAME${NC}"
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --query 'SecretString' --output text 2>/dev/null)

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${YELLOW}Failed to retrieve password using dynamic secret name. Trying legacy secret name...${NC}"
    LEGACY_SECRET_NAME="rds/sqlserver-database-1/password"
    DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id $LEGACY_SECRET_NAME --query 'SecretString' --output text 2>/dev/null)
    
    if [ -z "$DB_PASSWORD" ]; then
        echo -e "${RED}Failed to retrieve password from AWS Secrets Manager using both dynamic and legacy secret names.${NC}"
        echo -e "${RED}Tried:${NC}"
        echo -e "  - $SECRET_NAME"
        echo -e "  - $LEGACY_SECRET_NAME"
        
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${YELLOW}Debug: Listing available secrets that match 'rds' pattern:${NC}"
            aws secretsmanager list-secrets --query 'SecretList[?contains(Name, `rds`)].Name' --output table 2>/dev/null || echo -e "${RED}Failed to list secrets${NC}"
        fi
        
        echo -e "${YELLOW}Please check that the secret exists and you have the correct AWS permissions.${NC}"
        echo -e "${YELLOW}You can use --debug flag to see available secrets.${NC}"
        exit 1
    else
        echo -e "${GREEN}Successfully retrieved password using legacy secret name.${NC}"
    fi
else
    echo -e "${GREEN}Successfully retrieved password using dynamic secret name.${NC}"
fi

# Return to project root directory
cd ..

# Upload the backup file to S3
echo -e "${YELLOW}Uploading AdventureWorks backup file to S3...${NC}"
aws s3 cp $BACKUP_FILE s3://$S3_BUCKET/

# Create SQL script to restore database
echo -e "${YELLOW}Creating SQL script to restore database from S3...${NC}"
RESTORE_COMMAND=$(pulumi stack output adventureWorksSqlRestoreCommand --cwd=$PULUMI_DIR)

cat > restore-adventureworks.sql << EOF
-- SQL Server AdventureWorks database restoration script
-- Generated on $(date)

-- Restore the AdventureWorksLT database from S3
$RESTORE_COMMAND

GO

-- Check the status of the restore
EXEC msdb.dbo.rds_task_status @db_name = '$DB_NAME';
EOF

# Create a query file for testing the database
cat > query-adventureworks.sql << EOF
-- SQL Server AdventureWorks database query test
-- Generated on $(date)

USE $DB_NAME;
GO

-- Get the list of tables
SELECT 
    schema_name(schema_id) as schema_name,
    name as table_name
FROM 
    sys.tables
ORDER BY 
    schema_name, table_name;
GO

-- Count number of customers
SELECT COUNT(*) AS CustomerCount FROM SalesLT.Customer;
GO

-- Show sample customer data
SELECT TOP 5 
    CustomerID, 
    FirstName, 
    LastName, 
    EmailAddress
FROM 
    SalesLT.Customer
ORDER BY 
    CustomerID;
GO
EOF

# If auto-restore is enabled, restore the database
if [ "$AUTO_RESTORE" = true ]; then
    echo -e "${BLUE}Restoring AdventureWorks database to SQL Server...${NC}"
    echo -e "${YELLOW}This may take several minutes. Please wait...${NC}"
    
    sqlcmd -S $DB_HOST,$DB_PORT -U $DB_USERNAME -P $DB_PASSWORD -i restore-adventureworks.sql
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to restore database.${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Waiting for database restoration to complete...${NC}"
    
    # Check restoration status in a loop until complete
    RESTORE_COMPLETE=false
    ATTEMPT=0
    MAX_ATTEMPTS=30
    
    while [ "$RESTORE_COMPLETE" = false ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        let ATTEMPT=ATTEMPT+1
        
        # Query the status
        STATUS=$(sqlcmd -S $DB_HOST,$DB_PORT -U $DB_USERNAME -P $DB_PASSWORD -Q "EXEC msdb.dbo.rds_task_status @db_name = '$DB_NAME';" -h-1 | grep "SUCCESS")
        
        if [ ! -z "$STATUS" ]; then
            RESTORE_COMPLETE=true
            echo -e "${GREEN}Database restoration completed successfully!${NC}"
        else
            echo -e "${YELLOW}Restoration in progress... (Attempt $ATTEMPT/$MAX_ATTEMPTS)${NC}"
            sleep 10
        fi
    done
    
    if [ "$RESTORE_COMPLETE" = false ]; then
        echo -e "${RED}Database restoration is taking longer than expected.${NC}"
        echo -e "${YELLOW}To check the status manually, run:${NC}"
        echo -e "sqlcmd -S $DB_HOST,$DB_PORT -U $DB_USERNAME -P <password> -Q \"EXEC msdb.dbo.rds_task_status @db_name = '$DB_NAME';\""
    fi
    
    # If query after restore is enabled, run the query
    if [ "$QUERY_AFTER_RESTORE" = true ] && [ "$RESTORE_COMPLETE" = true ]; then
        echo -e "${BLUE}Running test query on AdventureWorks database...${NC}"
        sqlcmd -S $DB_HOST,$DB_PORT -U $DB_USERNAME -P $DB_PASSWORD -i query-adventureworks.sql
    fi
fi

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}=====================================================================\n"
echo -e "To restore the AdventureWorks database:${NC}"
echo -e "1. Connect to your SQL Server instance using:"
echo -e "   - Server: $DB_HOST"
echo -e "   - Port: $DB_PORT"
echo -e "   - Username: $DB_USERNAME"
echo -e "   - Password: (Retrieved from AWS Secrets Manager)"
echo -e ""
echo -e "2. Run the restore-adventureworks.sql script using SQL Server Management Studio"
echo -e "   or use the sqlcmd tool:\n"
echo -e "   sqlcmd -S $DB_HOST,$DB_PORT -U $DB_USERNAME -P <password> -i restore-adventureworks.sql"
echo -e "\n"
echo -e "3. The restoration process may take several minutes. You can check the status"
echo -e "   of the restore operation using:\n"
echo -e "   EXEC msdb.dbo.rds_task_status @db_name = '$DB_NAME';"
echo -e "\n"
echo -e "4. To run a test query after restoration is complete:\n"
echo -e "   sqlcmd -S $DB_HOST,$DB_PORT -U $DB_USERNAME -P <password> -i query-adventureworks.sql"
echo -e "\n"
echo -e "5. You can also run this script with the following options:\n"
echo -e "   --auto-restore         Automatically restore the database"
echo -e "   --query-after-restore  Run a test query after restoring"
echo -e "\n=====================================================================\n" 