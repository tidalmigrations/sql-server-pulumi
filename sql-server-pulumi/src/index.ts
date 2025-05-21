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
const dbPasswordSecret = new aws.secretsmanager.Secret("db-password-secret", {
    name: "rds/sqlserver-database-1/password",
    description: "Password for SQL Server RDS instance",
});

const dbPasswordSecretVersion = new aws.secretsmanager.SecretVersion("db-password-secret-version", {
    secretId: dbPasswordSecret.id,
    secretString: dbPassword,
});

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
    optionGroupName: pulumi.interpolate`default:${sqlServerEngine}-${sqlServerVersion.split(".")[0]}-${sqlServerVersion.split(".")[1]}`,
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