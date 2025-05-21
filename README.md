# SQL Server Test Environment

This Pulumi stack creates a SQL Server RDS instance in AWS that matches the requested configuration, along with all necessary networking infrastructure to make it publicly accessible. The default version is SQL Server 2016, but you can configure it to use any SQL Server version.

## Prerequisites

1. [Install Pulumi CLI](https://www.pulumi.com/docs/install/)
2. [Configure AWS Credentials](https://www.pulumi.com/registry/packages/aws/installation-configuration/)
3. Node.js 14 or later
4. AWS CLI installed and configured

## Quick Start

For quick setup and deployment:

1. Make the scripts executable (if not already):
   ```
   chmod +x *.sh
   ```

2. Set up S3 state backend (optional but recommended for teams):
   ```
   export AWS_PROFILE=<your-profile-name>
   ./setup-s3-state-backend.sh
   ```

3. Initialize the project and install dependencies:
   ```
   ./init-project.sh
   ```

4. Deploy the infrastructure:
   ```
   pulumi up
   ```

## Setting Up S3 State Backend

Pulumi state can be stored in an S3 bucket for team collaboration and state recovery. To set this up:

1. Make the setup script executable (if not already):
   ```
   chmod +x setup-s3-state-backend.sh
   ```

2. Run the setup script:
   ```
   ./setup-s3-state-backend.sh
   ```

This script will:
- Create an S3 bucket named `pulumi-state-sql-server` in the ca-central-1 region (if it doesn't exist)
- Enable versioning for state recovery
- Configure encryption for the bucket
- Configure Pulumi to use this S3 bucket as the state backend

You can modify the bucket name and region in the script if needed.

## Project Initialization

To initialize the project and install dependencies:

1. Make the initialization script executable (if not already):
   ```
   chmod +x init-project.sh
   ```

2. Run the initialization script:
   ```
   ./init-project.sh
   ```

This script will:
- Check for required tools (Node.js, npm, Pulumi)
- Install project dependencies
- Check if you're using the S3 state backend
- Create a new stack named 'dev' (if it doesn't exist)

## Configuration

The stack is configured using Pulumi config commands. Do not commit `Pulumi.dev.yaml` to the repository.

Run the following commands to configure your environment:

```bash
# Set AWS region
pulumi config set aws:region us-east-2

# Set database admin username
pulumi config set sql-server-test-environment:dbUsername admin

# Set weekly maintenance window
pulumi config set sql-server-test-environment:maintenanceWindow "sun:07:26-sun:07:56"

# The following are optional configurations with defaults
```

### Configuring SQL Server Version

You can set the SQL Server version and engine type using Pulumi config commands:

```bash
# Set SQL Server version (default is 13.00.6300.2.v1 for SQL Server 2016)
pulumi config set sqlServerVersion 14.00.3381.3.v1  # For SQL Server 2017
pulumi config set sqlServerVersion 15.00.4198.2.v1  # For SQL Server 2019
pulumi config set sqlServerVersion 16.00.4085.2.v1  # For SQL Server 2022

# Set SQL Server engine (default is sqlserver-se for Standard Edition)
pulumi config set sqlServerEngine sqlserver-ee  # For Enterprise Edition
pulumi config set sqlServerEngine sqlserver-ex  # For Express Edition
pulumi config set sqlServerEngine sqlserver-web  # For Web Edition
```

## Manual Deployment Instructions

If you prefer to set up everything manually:

1. Install dependencies:
   ```
   npm install
   ```

2. Initialize a new Pulumi stack (after setting up the S3 backend):
   ```
   pulumi stack init dev
   ```

3. Deploy the infrastructure:
   ```
   pulumi up
   ```

4. Once deployed, you can get the connection information:
   ```
   pulumi stack output sqlServerEndpoint
   pulumi stack output sqlServerConnectionString
   ```

## Network Infrastructure

This stack creates:

- A new VPC with CIDR block 10.0.0.0/16
- Two public subnets across different availability zones
- A security group that allows inbound traffic on port 1433 (SQL Server) from anywhere
- An RDS subnet group using the public subnets
- All necessary route tables and internet gateway for public internet access

## SQL Server Configuration

This stack deploys an RDS SQL Server instance with the following configurations:

- Default Engine: SQL Server Standard Edition 2016 (13.00.6300.2.v1)
- Configurable: Can be set to any available SQL Server version
- Instance Class: db.t3.xlarge (4 vCPU, 16 GB RAM)
- Storage: 20 GiB GP3 with autoscaling up to 1000 GiB
- Network: Publicly accessible in the created VPC in ca-central-1a
- Security: Custom security group allowing SQL Server port (1433) from anywhere
- Maintenance: Disabled auto minor version upgrades with custom maintenance window
- Backups: Automated backups disabled
- Master username: admin

## Accessing the SQL Server

After deployment, you can connect to the SQL Server instance using the following information:

- Server Address: See output `sqlServerEndpoint`
- Port: 1433
- Username: admin
- Password: Stored in AWS Secrets Manager under `rds/sqlserver-database-1/password`

You can connect using SQL Server Management Studio or any other SQL client that supports SQL Server.

## Cleanup

To destroy the deployed resources:

```
pulumi destroy
```

To switch back to local state storage:

```
pulumi login --local
``` 