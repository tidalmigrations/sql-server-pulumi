# SQL Server Test Environment

> **Warning:** This environment is for testing and development purposes only. It is not configured for production use and exposes the database publicly. **DO NOT USE IN PRODUCTION.**

This Pulumi stack creates a SQL Server RDS instance in AWS that matches the requested configuration, along with all necessary networking infrastructure to make it publicly accessible. The default version is SQL Server 2016, but you can configure it to use any SQL Server version. The stack also includes support for deploying the AdventureWorks sample database, making it easy to set up a complete test environment for SQL Server development and testing.

- [SQL Server Test Environment](#sql-server-test-environment)
   - [Prerequisites](#prerequisites)
   - [Quick Start](#quick-start)
   - [Setting Up S3 State Backend](#setting-up-s3-state-backend)
   - [Project Initialization](#project-initialization)
   - [Configuration](#configuration)
      - [Configuring SQL Server Version](#configuring-sql-server-version)
      - [Enabling AdventureWorks Infrastructure](#enabling-adventureworks-infrastructure)
   - [Manual Deployment Instructions](#manual-deployment-instructions)
   - [Network Infrastructure](#network-infrastructure)
   - [SQL Server Configuration](#sql-server-configuration)
   - [Accessing the SQL Server](#accessing-the-sql-server)
   - [AWS Region Configuration](#aws-region-configuration)
   - [Setting Up the SQL Command Line Tool (sqlcmd) on Mac](#setting-up-the-sql-command-line-tool-sqlcmd-on-mac)
      - [Method 1: Using Homebrew](#method-1-using-homebrew)
      - [Troubleshooting ODBC Driver Installation](#troubleshooting-odbc-driver-installation)
      - [Method 2: Using the Microsoft Installer Package](#method-2-using-the-microsoft-installer-package)
   - [AdventureWorks Sample Database (Optional)](#adventureworks-sample-database-optional)
      - [Prerequisites for AdventureWorks](#prerequisites-for-adventureworks)
      - [Enabling AdventureWorks Infrastructure](#enabling-adventureworks-infrastructure-1)
      - [Uploading and Restoring AdventureWorks](#uploading-and-restoring-adventureworks)
      - [Testing the AdventureWorks Connection](#testing-the-adventureworks-connection)
      - [AdventureWorks Database Structure](#adventureworks-database-structure)
      - [Common Issues with AdventureWorks Setup](#common-issues-with-adventureworks-setup)
      - [AdventureWorks Troubleshooting](#adventureworks-troubleshooting)
   - [Cleanup](#cleanup)


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
- Create an S3 bucket with a unique name in the format `pulumi-state-sql-server-<timestamp>-<random_string>` in the specified AWS region
- Enable versioning for state recovery
- Configure encryption for the bucket
- Configure Pulumi to use this S3 bucket as the state backend
- Save the bucket name to a `.pulumi-state-bucket` file for future reference

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

### Enabling AdventureWorks Infrastructure

To enable the AdventureWorks sample database infrastructure in your Pulumi stack:

```bash
pulumi config set setupAdventureWorks true
pulumi up
```

This will create all the necessary AWS resources for AdventureWorks database setup, including:
1. An S3 bucket for storing the database backup file
2. IAM roles and policies for RDS to access S3
3. RDS option group with backup/restore capabilities
4. Configuration of the SQL Server RDS instance to use these components

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

## AWS Region Configuration

All scripts in this project support configuring the AWS region in one of these ways:

1. **Environment Variable**: Set the `AWS_REGION` environment variable
   ```bash
   export AWS_REGION=us-east-2
   ```

2. **Default Value**: If no region is specified, scripts will default to `us-east-2`

3. **Command Line Arguments**: For Python scripts that support it, you can specify the region directly:
   ```bash
   python simple_odbc_test.py --region us-east-2
   ```

## Setting Up the SQL Command Line Tool (sqlcmd) on Mac

To connect to and manage your SQL Server database from the command line on macOS, you need to install the SQL Server command-line tools:

### Method 1: Using Homebrew

1. If you don't have Homebrew installed, install it first:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Install the Microsoft ODBC Driver and SQL Tools:
   ```bash
   brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
   brew update
   # You can install either version 17 or 18 of the ODBC driver
   # Option 1: Install version 17 (tested and confirmed working)
   brew install msodbcsql17 mssql-tools
   # Option 2: Install version 18 (newer version)
   # brew install msodbcsql18 mssql-tools18
   ```

3. Add sqlcmd to your PATH environment variable:
   ```bash
   # If you installed mssql-tools (with version 17)
   echo 'export PATH="/usr/local/opt/mssql-tools/bin:$PATH"' >> ~/.zshrc
   # If you installed mssql-tools18 (with version 18)
   # echo 'export PATH="/usr/local/opt/mssql-tools18/bin:$PATH"' >> ~/.zshrc
   
   # For bash users
   # echo 'export PATH="/usr/local/opt/mssql-tools/bin:$PATH"' >> ~/.bash_profile
   # Or for mssql-tools18
   # echo 'export PATH="/usr/local/opt/mssql-tools18/bin:$PATH"' >> ~/.bash_profile
   ```

4. Reload your shell profile:
   ```bash
   source ~/.zshrc  # or source ~/.bash_profile for bash users
   ```

4. Verify the installation:
   ```bash
   sqlcmd -?
   ```

### Troubleshooting ODBC Driver Installation

If you encounter the error `Can't open lib 'ODBC Driver 17 for SQL Server' : file not found` when trying to connect to SQL Server, it means the ODBC driver was not properly installed or configured. Use the following commands to verify the installation:

```bash
# Check ODBC configuration
odbcinst -j

# Check if the ODBC driver is listed in the configuration
cat /opt/homebrew/etc/odbcinst.ini
```

The Microsoft ODBC Driver should be listed in the odbcinst.ini file. If not, try reinstalling the driver:

```bash
brew reinstall msodbcsql17
```

For ARM64-based Macs (M1, M2, etc.), the library path might be in `/opt/homebrew/lib/` instead of `/usr/local/`.

### Method 2: Using the Microsoft Installer Package

1. Download the Microsoft ODBC Driver for SQL Server:
   - Visit [Microsoft's SQL Server downloads page](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server)
   - Download the driver package for macOS (.pkg file)

2. Install the downloaded package by double-clicking it and following the instructions.

3. Download and install the SQL Server command-line tools:
   - Visit [Microsoft's SQL Tools download page](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility)
   - Download the command-line tools package for macOS (.pkg file)

4. Install the downloaded package by double-clicking it and following the instructions.

5. Add sqlcmd to your PATH:
   ```bash
   echo 'export PATH="/opt/mssql-tools/bin:$PATH"' >> ~/.zshrc
   # or for bash users
   echo 'export PATH="/opt/mssql-tools/bin:$PATH"' >> ~/.bash_profile
   ```

6. Reload your shell profile:
   ```bash
   source ~/.zshrc  # or source ~/.bash_profile for bash users
   ```

7. Verify the installation:
   ```bash
   sqlcmd -?
   ```

## AdventureWorks Sample Database (Optional)

This project includes support for deploying the AdventureWorks sample database. This is useful for testing applications that require a pre-populated database.

### Prerequisites for AdventureWorks

- Python 3.6+ with pip
- SQL Server Management Studio or Azure Data Studio (optional, for database exploration)
- The AdventureWorks backup file (`AdventureWorksLT2016.bak`) in the `adventureworks` directory.

### Enabling AdventureWorks Infrastructure

To enable the AdventureWorks sample database infrastructure in your Pulumi stack:

```bash
pulumi config set setupAdventureWorks true
pulumi up
```

This command will configure Pulumi to create the necessary AWS resources when you next run `pulumi up`. These resources include:

1. An S3 bucket for storing the database backup file.
2. IAM roles and policies for RDS to access S3.
3. An RDS option group with backup/restore capabilities.
4. Configuration of the SQL Server RDS instance to use these components.

After running `pulumi up`, proceed to the next step to upload and restore the database.

### Uploading and Restoring AdventureWorks

Once the infrastructure is in place (after running `pulumi up` with `setupAdventureWorks` set to `true`), you can upload the AdventureWorks backup file and restore it to your RDS instance.

The `upload-and-restore-adventureworks.sh` script automates this process:

```bash
# Make the script executable (if not already)
chmod +x upload-and-restore-adventureworks.sh

# Run the script
./upload-and-restore-adventureworks.sh
```

**Available Script Options:**

*   `--auto-restore`: Automatically restore the database after uploading the backup file.
*   `--query-after-restore`: Run a test query after restoration to verify the database is working.
*   `--help`: Show usage information.

**Example:**

```bash
# Upload the backup file, restore the database, and run a test query
./upload-and-restore-adventureworks.sh --query-after-restore
```

**Manual Restoration (if not using `--auto-restore`):**

If you didn't use the `--auto-restore` option, you need to execute the SQL restoration commands manually:

1.  Connect to your SQL Server RDS instance using SQL Server Management Studio, Azure Data Studio, or the `sqlcmd` command-line utility (see [Setting Up sqlcmd](#setting-up-the-sql-command-line-tool-sqlcmd-on-mac)).
2.  Execute the generated `restore-adventureworks.sql` script (created by `upload-and-restore-adventureworks.sh`). It contains a command similar to this:

    ```sql
    EXEC msdb.dbo.rds_restore_database
        @restore_db_name = 'AdventureWorksLT',
        @s3_arn_to_restore_from = 'arn:aws:s3:::your-bucket-name/AdventureWorksLT2016.bak';
    ```
3.  Monitor the restoration progress:

    ```sql
    EXEC msdb.dbo.rds_task_status @db_name = 'AdventureWorksLT';
    ```
    The restoration process may take several minutes.

### Testing the AdventureWorks Connection

You can test the connection to the restored AdventureWorks database using one of these methods:

1.  **Using the script-generated SQL query:** The `upload-and-restore-adventureworks.sh` script generates a `query-adventureworks.sql` file. You can run it with `sqlcmd`:

    ```bash
    sqlcmd -S <host>,<port> -U <username> -P <password> -i query-adventureworks.sql
    ```
    (Replace placeholders with your actual connection details).
2.  **Using the `simple_odbc_test.py` script:** This Python script checks the SQL Server connection and AdventureWorks database status.

    ```bash
    # Install dependencies (if not already installed)
    pip install pyodbc

    # Run the test script
    python simple_odbc_test.py
    ```
    This script will:
    *   Connect to the SQL Server RDS instance.
    *   Verify the server is accessible.
    *   Check if the AdventureWorksLT database is restored and accessible.
    *   Report the status of any restore tasks.
    *   List available tables in the AdventureWorksLT database if it exists.

### AdventureWorks Database Structure

The AdventureWorksLT (Lightweight) database is a simplified version of the full AdventureWorks database, containing the following schemas:

*   `SalesLT`: Contains sales-related tables like Customer, Product, SalesOrderHeader, etc.

### Common Issues with AdventureWorks Setup

1.  **Connection issues**: Ensure your security group allows connections on port 1433 from your IP address.
2.  **Permission issues**: Make sure the IAM role associated with the RDS instance has the necessary permissions for S3 access.
3.  **Restoration failures**: Check the task status using the SQL command above to identify any errors in the restoration process. Review RDS logs in the AWS console if needed.

### AdventureWorks Troubleshooting

If you encounter issues during the AdventureWorks setup process:

1.  Check the AWS RDS console for the status of your instance and any pending modifications or events.
2.  Verify that the option group (with S3 integration) is correctly attached to your RDS instance.
3.  Double-check the IAM role and policy permissions for S3 access.
4.  Look for errors in the RDS event logs in the AWS console.
5.  If infrastructure creation related to AdventureWorks fails during `pulumi up`, check the Pulumi error messages and the AWS CloudFormation console for related stack events.
6.  Run the `simple_odbc_test.py` script to get a detailed status of the connection and database.

## Cleanup

To destroy the deployed resources:

```