import * as pulumi from "@pulumi/pulumi";
import * as aws from "@pulumi/aws";
import * as random from "@pulumi/random";
import * as awsx from "@pulumi/awsx";

// Get configuration values
const config = new pulumi.Config();
const dbUsername = config.require("dbUsername");
const maintenanceWindow = config.require("maintenanceWindow");
const sqlServerVersion = config.get("sqlServerVersion") || "13.00.6300.2.v1"; // SQL Server 2016 as default
const sqlServerEngine = config.get("sqlServerEngine") || "sqlserver-se"; // SQL Server Standard Edition as default
const dbParameterGroupName = config.get("dbParameterGroupName") || "default.sqlserver-se-13.0"; // Default parameter group name
const setupAdventureWorks = config.getBoolean("setupAdventureWorks") || false; // Whether to set up AdventureWorks DB

// Get stack information for deterministic naming
const stack = pulumi.getStack();
const project = pulumi.getProject();

// Create a new VPC
const vpc = new awsx.ec2.Vpc("sqlserver-vpc", {
    cidrBlock: "10.0.0.0/16",
    numberOfAvailabilityZones: 2,
    subnetSpecs: [
        {
            type: awsx.ec2.SubnetType.Public,
            name: "public",
            cidrMask: 24,
        },
    ],
    natGateways: {
        strategy: awsx.ec2.NatGatewayStrategy.None,
    },
    enableDnsHostnames: true,
    enableDnsSupport: true,
    tags: {
        Name: "sqlserver-vpc",
    },
});

// Create a security group for SQL Server
const sqlServerSecurityGroup = new aws.ec2.SecurityGroup("sqlserver-testdb-public-sg", {
    vpcId: vpc.vpcId,
    description: "Security group for SQL Server RDS instance",
    ingress: [
        {
            protocol: "tcp",
            fromPort: 1433,
            toPort: 1433,
            cidrBlocks: ["0.0.0.0/0"], // Allow SQL Server port from anywhere
        },
    ],
    egress: [
        {
            protocol: "-1",
            fromPort: 0,
            toPort: 0,
            cidrBlocks: ["0.0.0.0/0"],
        },
    ],
    tags: {
        Name: "sqlserver-testdb-public-sg",
    },
});

// Create an RDS subnet group using the public subnets from our VPC
const dbSubnetGroup = new aws.rds.SubnetGroup("sqlserver-subnet-group", {
    subnetIds: vpc.publicSubnetIds,
    tags: {
        Name: "sqlserver-subnet-group",
    },
});

// Create a random password for the SQL Server instance
const dbPassword = new random.RandomPassword("password", {
    length: 16,
    special: false,
}).result;

// Store the password in AWS Secrets Manager
// Note: If you get an error about a secret already scheduled for deletion,
// you can either:
// 1. Use the dynamic name approach above (recommended)
// 2. Force delete the existing secret with: aws secretsmanager delete-secret --secret-id "rds/sqlserver-database-1/password" --force-delete-without-recovery
const dbPasswordSecret = new aws.secretsmanager.Secret("db-password-secret", {
    name: `rds/${project}-${stack}/sqlserver-database-1/password`,
    description: "Password for SQL Server RDS instance",
    recoveryWindowInDays: 0, // Allow immediate deletion without recovery window
    tags: {
        Name: "SQLServer-Database-Password",
        Environment: stack,
        Project: project,
    },
});

const dbPasswordSecretVersion = new aws.secretsmanager.SecretVersion("db-password-secret-version", {
    secretId: dbPasswordSecret.id,
    secretString: dbPassword,
});

// ===== Begin AdventureWorks Database Setup =====
// Only create these resources if setupAdventureWorks is true
let s3Bucket: aws.s3.Bucket | undefined;
let iamRole: aws.iam.Role | undefined;
let iamRolePolicy: aws.iam.Policy | undefined;
let iamRolePolicyAttachment: aws.iam.RolePolicyAttachment | undefined;
let optionGroup: aws.rds.OptionGroup | undefined;

if (setupAdventureWorks) {
    // Create S3 bucket for AdventureWorks backup
    // S3 bucket names must be <= 63 characters, so we'll use a shorter format
    // Replace long project names with hash to ensure uniqueness while staying short
    const projectHash = project.replace(/[^a-z0-9]/g, '').substring(0, 10);
    const bucketName = `sqlserver-aw-${projectHash}-${stack}`.toLowerCase();
    s3Bucket = new aws.s3.Bucket("adventureworks-backup-bucket", {
        bucket: bucketName,
        acl: "private",
        forceDestroy: true, // Allow Pulumi to delete the bucket even if it contains objects
        tags: {
            Name: "SQLServer-AdventureWorks-Backups",
            Environment: "testing",
        },
    });
    
    // Create IAM policy for RDS to access S3
    iamRolePolicy = new aws.iam.Policy("rds-s3-access-policy", {
        name: "RDSBackupRestorePolicy",
        description: "Policy allowing RDS to access S3 for backup/restore",
        policy: s3Bucket.arn.apply(bucketArn => JSON.stringify({
            Version: "2012-10-17",
            Statement: [
                {
                    Effect: "Allow",
                    Action: [
                        "s3:ListBucket",
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:GetBucketLocation"
                    ],
                    Resource: [
                        bucketArn,
                        `${bucketArn}/*`
                    ]
                }
            ]
        })),
    });
    
    // Create IAM role for RDS
    iamRole = new aws.iam.Role("rds-s3-integration-role", {
        name: "rds-s3-integration-role",
        description: "Role allowing RDS to access S3",
        assumeRolePolicy: JSON.stringify({
            Version: "2012-10-17",
            Statement: [
                {
                    Effect: "Allow",
                    Principal: {
                        Service: "rds.amazonaws.com"
                    },
                    Action: "sts:AssumeRole"
                }
            ]
        }),
        tags: {
            Name: "RDS-S3-Integration-Role",
            Environment: "testing",
        },
    });
    
    // Attach IAM policy to role
    iamRolePolicyAttachment = new aws.iam.RolePolicyAttachment("rds-s3-policy-attachment", {
        role: iamRole.name,
        policyArn: iamRolePolicy.arn,
    });
    
    // Create RDS option group for backup/restore
    const optionGroupName = "sqlserver-se-13-backup-restore";
    optionGroup = new aws.rds.OptionGroup("sql-server-backup-restore-option-group", {
        name: optionGroupName,
        engineName: "sqlserver-se",
        majorEngineVersion: "13.00",
        optionGroupDescription: "Option group for SQL Server backup and restore",
        options: [{
            optionName: "SQLSERVER_BACKUP_RESTORE",
            optionSettings: [{
                name: "IAM_ROLE_ARN",
                value: iamRole.arn,
            }],
        }],
        tags: {
            Name: "SQLServer-Backup-Restore-Option-Group",
            Environment: "testing",
        },
    });
}
// ===== End AdventureWorks Database Setup =====

// Create the SQL Server RDS instance
const sqlServerInstance = new aws.rds.Instance("sqlserver-database-1", {
    identifier: "sqlserver-database-1",
    engine: sqlServerEngine,
    engineVersion: sqlServerVersion,
    instanceClass: "db.t3.xlarge",
    allocatedStorage: 20,
    storageType: "gp3",
    storageEncrypted: true,
    maxAllocatedStorage: 1000, // Enable storage autoscaling with max 1000 GB
    username: dbUsername,
    password: dbPassword,
    port: 1433,
    publiclyAccessible: true,
    skipFinalSnapshot: true,
    dbSubnetGroupName: dbSubnetGroup.name,
    vpcSecurityGroupIds: [sqlServerSecurityGroup.id],
    licenseModel: "license-included",
    multiAz: false,
    iamDatabaseAuthenticationEnabled: false,
    maintenanceWindow: maintenanceWindow,
    backupRetentionPeriod: 0, // Disable automated backups
    copyTagsToSnapshot: true,
    deleteAutomatedBackups: true,
    autoMinorVersionUpgrade: false,
    // Let AWS choose a valid availability zone automatically
    // Use parameter group from config
    parameterGroupName: dbParameterGroupName,
    // Use the backup/restore option group if setupAdventureWorks is true, otherwise use the default
    optionGroupName: setupAdventureWorks && optionGroup 
        ? optionGroup.name 
        : pulumi.interpolate`default:${sqlServerEngine}-${sqlServerVersion.split(".")[0]}-${sqlServerVersion.split(".")[1]}`,
    performanceInsightsEnabled: false,
    iops: 3000,
    tags: {
        Name: "sqlserver-database-1",
        Environment: "testing",
    },
});

// Export important outputs
export const vpcId = vpc.vpcId;
export const publicSubnetIds = vpc.publicSubnetIds;
export const securityGroupId = sqlServerSecurityGroup.id;
export const sqlServerEndpoint = sqlServerInstance.endpoint;
export const sqlServerPort = sqlServerInstance.port;
export const sqlServerConnectionString = pulumi.interpolate`Server=${sqlServerInstance.endpoint};Database=master;User Id=${dbUsername};Password=${dbPassword};`;

// Define AdventureWorks outputs
let adventureWorksS3Bucket: pulumi.Output<string> | undefined;
let adventureWorksS3BucketArn: pulumi.Output<string> | undefined;
let adventureWorksSqlRestoreCommand: pulumi.Output<string> | undefined;

// Set AdventureWorks values if applicable
if (setupAdventureWorks && s3Bucket) {
    adventureWorksS3Bucket = s3Bucket.bucket;
    adventureWorksS3BucketArn = s3Bucket.arn;
    adventureWorksSqlRestoreCommand = pulumi.interpolate`EXEC msdb.dbo.rds_restore_database @restore_db_name = 'AdventureWorksLT', @s3_arn_to_restore_from = '${s3Bucket.arn}/AdventureWorksLT2016.bak';`;
}

// Export AdventureWorks outputs conditionally
if (adventureWorksS3Bucket) {
    exports.adventureWorksS3Bucket = adventureWorksS3Bucket;
}
if (adventureWorksS3BucketArn) {
    exports.adventureWorksS3BucketArn = adventureWorksS3BucketArn;
}
if (adventureWorksSqlRestoreCommand) {
    exports.adventureWorksSqlRestoreCommand = adventureWorksSqlRestoreCommand;
} 