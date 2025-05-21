#!/usr/bin/env python3
import sys
import subprocess
import json
import os
import argparse

try:
    import pyodbc
except ImportError:
    print("Error: pyodbc module not found.")
    print("Please install it with: pip install pyodbc")
    sys.exit(1)

# Get AWS region from environment variable or use default
AWS_REGION = os.environ.get("AWS_REGION", "us-east-2")

def get_password(region):
    """Get SQL Server password from AWS Secrets Manager"""
    secret_name = "rds/sqlserver-database-1/password"
    try:
        result = subprocess.run(
            ["aws", "secretsmanager", "get-secret-value",
             "--secret-id", secret_name, "--region", region],
            capture_output=True,
            text=True,
            check=True
        )
        secret_json = json.loads(result.stdout)
        return secret_json['SecretString']
    except Exception as e:
        print(f"Error retrieving password: {e}")
        sys.exit(1)

def get_rds_endpoint():
    """Get RDS endpoint from Pulumi stack output"""
    try:
        # Change to Pulumi directory
        pulumi_dir = os.environ.get("PULUMI_DIR", "./sql-server-pulumi")
        # Store current directory
        current_dir = os.getcwd()
        
        # Change to Pulumi directory if it exists
        if os.path.isdir(pulumi_dir):
            os.chdir(pulumi_dir)
            
        result = subprocess.run(
            ["pulumi", "stack", "output", "sqlServerEndpoint"],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Change back to original directory
        os.chdir(current_dir)
        
        # Split endpoint into host and port
        endpoint = result.stdout.strip()
        if ':' in endpoint:
            server, port = endpoint.split(':')
            return server, int(port)
        else:
            return endpoint, 1433
    except Exception as e:
        print(f"Error retrieving RDS endpoint from Pulumi: {e}")
        print("Using environment variables or configuration file as fallback.")
        
        # Try to read from config file first
        config_file = os.environ.get("SQL_CONFIG_FILE", "sql_config.json")
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    if 'server' in config and 'port' in config:
                        return config['server'], int(config['port'])
            except Exception as cf_err:
                print(f"Error reading config file: {cf_err}")
        
        # Fallback to environment variables with generic defaults
        server = os.environ.get("SQL_SERVER_HOST")
        if not server:
            print("SQL_SERVER_HOST not set. Please set this environment variable.")
            print("For example: export SQL_SERVER_HOST="
                  "your-server.region.rds.amazonaws.com")
            sys.exit(1)
            
        port = int(os.environ.get("SQL_SERVER_PORT", "1433"))
        return server, port

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Test connection to SQL Server RDS"
    )
    parser.add_argument(
        "--region",
        default=AWS_REGION,
        help=f"AWS region to use (default: {AWS_REGION})"
    )
    parser.add_argument(
        "--server",
        help="SQL Server hostname (overrides Pulumi output)"
    )
    parser.add_argument(
        "--port", 
        type=int,
        help="SQL Server port (overrides Pulumi output)"
    )
    parser.add_argument(
        "--username",
        default=os.environ.get("SQL_SERVER_USERNAME", "admin"),
        help="SQL Server username (default: from env or 'admin')"
    )
    return parser.parse_args()

def main():
    # Parse command line arguments
    args = parse_arguments()
    region = args.region
    
    print(f"Using AWS region: {region}")
    print("Retrieving password from AWS Secrets Manager...")
    password = get_password(region)
    
    # Get server info from args, env vars, or Pulumi
    if args.server and args.port:
        SERVER = args.server
        PORT = args.port
        print("Using server details from command line arguments.")
    else:
        SERVER, PORT = get_rds_endpoint()
        print("Using server details from Pulumi stack output.")
    
    USERNAME = args.username
    DATABASE = "master"
    
    # Build connection string
    connection_string = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={SERVER},{PORT};"
        f"DATABASE={DATABASE};"
        f"UID={USERNAME};PWD={password}"
    )
    
    print(f"Connecting to {DATABASE} database on {SERVER}:{PORT}...")
    try:
        # Use a longer timeout
        conn = pyodbc.connect(connection_string, timeout=30)
        cursor = conn.cursor()
        
        # Check SQL Server version
        cursor.execute("SELECT @@VERSION AS Version")
        row = cursor.fetchone()
        print(f"SQL Server Version: {row.Version}")
        
        # Check restore task status using the stored procedure
        print("\nChecking AdventureWorksLT restore task status:")
        cursor.execute(
            "EXEC msdb.dbo.rds_task_status @db_name = 'AdventureWorksLT'"
        )
        
        tasks = cursor.fetchall()
        if not tasks:
            print("No restore tasks found for AdventureWorksLT.")
        else:
            print("\nRestore tasks:")
            # Get column names
            columns = [column[0] for column in cursor.description]
            
            # Print tasks with important details first
            for task in tasks:
                # task_id is usually the first column
                print(f"\nTask ID: {task[0]}")
                
                # Find the status column
                lifecycle_index = (columns.index('lifecycle') 
                                   if 'lifecycle' in columns else -1)
                if lifecycle_index >= 0:
                    print(f"Status: {task[lifecycle_index]}")
                
                # Find the task_info column which contains error details
                task_info_index = (columns.index('task_info') 
                                   if 'task_info' in columns else -1)
                if task_info_index >= 0 and task[task_info_index]:
                    print("Error/Info details:")
                    print(task[task_info_index])
        
        # Check available databases
        print("\nChecking available databases:")
        cursor.execute("SELECT name FROM sys.databases ORDER BY name")
        databases = cursor.fetchall()
        for db in databases:
            print(f"  - {db.name}")
        
        # Check if AdventureWorksLT exists
        adv_works_exists = "AdventureWorksLT" in [db.name for db in databases]
        if adv_works_exists:
            print("\nAdventureWorksLT database found! Testing connection...")
            
            # Connect to AdventureWorksLT
            conn.close()
            connection_string = (
                f"DRIVER={{ODBC Driver 17 for SQL Server}};"
                f"SERVER={SERVER},{PORT};"
                f"DATABASE=AdventureWorksLT;"
                f"UID={USERNAME};PWD={password}"
            )
            
            conn = pyodbc.connect(connection_string, timeout=30)
            cursor = conn.cursor()
            
            # Check tables in AdventureWorksLT
            cursor.execute("""
                SELECT schema_name(schema_id) as schema_name, name 
                FROM sys.tables 
                ORDER BY schema_name, name
            """)
            
            print("\nAdventureWorksLT tables:")
            tables = cursor.fetchall()
            for table in tables:
                print(f"  - {table.schema_name}.{table.name}")
        else:
            print("\nAdventureWorksLT database not found.")
            print(
                "The restore task may have failed. "
                "Check the error details above."
            )
            print("To fix this, you might need to:")
            print("1. Re-run the upload-and-restore-adventureworks.sh script")
            print("2. Check IAM permissions for the RDS instance to access S3")
            print("3. Verify the backup file in S3 is accessible")
        
        conn.close()
        print("\n✅ Successfully tested SQL Server connection!")
    except pyodbc.Error as e:
        print(f"Database connection error: {e}")
        print("\n❌ Failed to connect to SQL Server.")
        print("Make sure the RDS instance is running and accessible.")
        print("Check security groups to ensure your IP has access.")
        sys.exit(1)

if __name__ == "__main__":
    main() 