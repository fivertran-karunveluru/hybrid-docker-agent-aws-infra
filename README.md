# Docker Hybrid Agent Infrastructure

This directory contains the infrastructure code and deployment scripts for deploying a Fivetran Docker Hybrid Agent on AWS. The infrastructure is defined using AWS CloudFormation and deployed using a bash script.

## Overview

The Docker Hybrid Agent infrastructure creates a complete environment for running Fivetran's hybrid deployment agent in a Docker container on AWS EC2. 

## Infrastructure Components

### 1. **IAM Roles and Policies**

#### DockerAgentEC2Role
- **Purpose**: Main IAM role attached to the EC2 instance
- **Permissions**: 
  - AmazonSSMManagedInstanceCore: Enables Systems Manager access
  - CloudWatchFullAccess: Allows CloudWatch monitoring and logging
  - AmazonRDSReadOnlyAccess: Read-only access to RDS databases
  - AmazonEC2ContainerServiceforEC2Role: ECS permissions for container operations
- **Trust Policy**: Allows both EC2 service and Fivetran AWS account to assume the role
- **External ID**: Uses the provided ExternalId for additional security

#### AgentEC2ReadMetadataPolicy
- **Purpose**: Allows the instance to read EC2 metadata and tags
- **Permissions**: `ec2:DescribeTags`, `ec2:DescribeInstances`
- **Scope**: All resources (`*`)

#### DockerAgentEC2S3Policy
- **Purpose**: Provides S3 access for the agent
- **Permissions**: `s3:GetObject`, `s3:ListBucket`
- **Scope**: All S3 resources (`*`)
- **Note**: This policy enables the agent to read data from S3 buckets out of the box, making it easy to sync S3 data without additional configuration

#### DockerAgentDynamoPolicy
- **Purpose**: Grants DynamoDB access for data operations
- **Permissions**:
  - `dynamodb:DescribeStream` - Read DynamoDB streams
  - `dynamodb:DescribeTable` - Get table metadata
  - `dynamodb:GetRecords` - Read stream records
  - `dynamodb:Scan` - Scan table data
  - `dynamodb:ListTables` - List available tables
  - `dynamodb:GetShardIterator` - Access stream shards
- **Scope**: All DynamoDB resources (`*`)
- **Note**: This policy enables the agent to read data from DynamoDB tables and streams out of the box, making it easy to sync DynamoDB data without additional configuration

#### DockerAgentEC2RoleInstanceProfile
- **Purpose**: IAM instance profile that attaches the role to the EC2 instance
- **Naming**: `{ProjectName}-EC2-IP`

### IAM Role and Policy Design Philosophy

The IAM setup is designed with **extensibility and ease of use** in mind. The policies included are **optional but pre-configured** to enable common data source access patterns without requiring additional setup.

#### **Optional Pre-Configured Policies**

1. **RDS Access Policy** (AmazonRDSReadOnlyAccess)
   - **Purpose**: Enables reading from RDS databases out of the box
   - **Use Case**: Sync data from MySQL, PostgreSQL, Aurora, or other RDS databases
   - **Benefit**: No additional IAM configuration needed for RDS data sources

2. **S3 Access Policy** (DockerAgentEC2S3Policy)
   - **Purpose**: Enables reading from S3 buckets out of the box
   - **Use Case**: Sync data from S3 buckets, logs, or data lakes
   - **Benefit**: Immediate access to S3 data without policy modifications

3. **DynamoDB Access Policy** (DockerAgentDynamoPolicy)
   - **Purpose**: Enables reading from DynamoDB tables and streams out of the box
   - **Use Case**: Sync data from DynamoDB tables, read change data capture streams
   - **Benefit**: Ready-to-use DynamoDB integration with comprehensive permissions

#### **Easy Extension for Additional Services**

The modular IAM policy design makes it simple to add access to other AWS services. You can easily extend the agent's capabilities by adding new policies:

**Example: Adding Kinesis Streams Access**
```yaml
# Add this policy to the CloudFormation template
KinesisAccessPolicy:
  Type: AWS::IAM::Policy
  Properties:
    PolicyName: !Join ["-",[!Ref ProjectName, "Kinesis-Access"]]
    PolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Action:
            - kinesis:DescribeStream
            - kinesis:GetRecords
            - kinesis:GetShardIterator
            - kinesis:ListStreams
          Resource: "*"
    Roles:
      - Ref: DockerAgentEC2Role
```

**Example: Adding Redshift Access**
```yaml
# Add this policy to the CloudFormation template
RedshiftAccessPolicy:
  Type: AWS::IAM::Policy
  Properties:
    PolicyName: !Join ["-",[!Ref ProjectName, "Redshift-Access"]]
    PolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Action:
            - redshift:DescribeClusters
            - redshift:DescribeLoggingStatus
            - redshift:DescribeResize
          Resource: "*"
    Roles:
      - Ref: DockerAgentEC2Role
```

#### **Benefits of This Design**

1. **Zero Configuration Required**: Common data sources work immediately
2. **Easy Customization**: Add new services with minimal policy additions
3. **Consistent Naming**: All policies follow the same naming convention
4. **Modular Structure**: Policies can be added/removed independently
5. **Best Practice Compliance**: Follows AWS IAM best practices for EC2 roles

#### **When to Modify Policies**

- **Add New Services**: When you need access to additional AWS services
- **Restrict Access**: When you want to limit permissions to specific resources
- **Custom Permissions**: When you need specific actions not covered by existing policies
- **Security Hardening**: When you want to implement least-privilege access patterns

#### **Extending the Deployment Script**

The deployment script can be easily extended to handle additional IAM policies or other AWS resources. Here are common extension patterns:

**Adding New IAM Policies**
1. **Update CloudFormation Template**: Add the new policy resource
2. **Update Deployment Script**: Add any new parameters if needed
3. **Redeploy**: Use the existing deployment script to apply changes

**Example: Adding Kinesis Policy to Deployment**
```bash
# The deployment script automatically handles new policies
# Just add the policy to the CloudFormation template and redeploy
./deploy-agent.sh deploy
```

**Adding New AWS Resources**
1. **Add Resource to Template**: Define new AWS resources in CloudFormation
2. **Update Parameters**: Add any new parameters if needed
3. **Extend Script**: Modify deployment script for new resource types if necessary

**Benefits of This Approach**
- **Incremental Updates**: Add new capabilities without rebuilding everything
- **Version Control**: Track infrastructure changes alongside code
- **Rollback Support**: CloudFormation provides automatic rollback capabilities
- **Consistent Deployment**: Same deployment process for all changes

### 2. **EC2 Instance (HybridAgentInstance)**

#### Specifications
- **Instance Type**: Configurable (default: t3.xlarge)
- **AMI**: Configurable (default: ami-0520f976ad2e6300c)
- **Storage**: 60GB GP3 EBS volume
- **Subnet**: Deployed in the first subnet of the specified environment
- **Monitoring**: Detailed CloudWatch monitoring enabled

#### User Data Script
The instance automatically runs a comprehensive setup script that:

1. **System Updates**: Updates the system packages
2. **Docker Installation**: Installs and starts Docker service
3. **SSM Agent**: Installs AWS Systems Manager agent
4. **User Creation**: Creates a `fivetran` user with sudo and docker group access
5. **Agent Installation**: Downloads and runs the Fivetran hybrid deployment installer

#### Security Features
- **IAM Instance Profile**: Attaches the configured IAM role
- **Security Groups**: Restricts network access based on security group rules
- **Key Pair**: SSH access using the specified key pair

### 3. **Security Group (AgentSecurityGroup)**

#### Inbound Rules
- **SSH Access**: Port 22 from your specified IP address
- **GitHub Access**: Full access to GitHub repositories (185.0.0.0/8)
- **Fivetran API**: HTTPS access to Fivetran API (35.236.237.87/32)
- **Fivetran IdP**: Access to Fivetran identity provider (35.188.225.82/32)
- **Google Artifactory**: Access to Google's artifact repositories (142.0.0.0/8)
- **Health Check**: Custom port (default: 8090) from your IP for monitoring

#### Network Configuration
- **VPC**: Deployed in the specified environment's VPC
- **Subnets**: Uses predefined subnet mappings for each environment
- **Availability Zones**: Automatically distributed across AZs

### 4. **Environment Mappings**

#### internal-sales
- **VPC**: vpc-0559852c7bdd6f4b7
- **Subnet 1**: subnet-0f768037aa7bebf93 (us-west-2b)
- **Subnet 2**: subnet-0ebf54d0f15f4de5b (us-west-2c)

#### internal-sales-dev
- **VPC**: vpc-08185b739d61a139f
- **Subnet 1**: subnet-0bb839954f00345b1 (us-west-2a)
- **Subnet 2**: subnet-09b162f69a76196df (us-west-2b)

## Configuration

### Configuration File (docker-agent-config.json)

Configuration file structure:

```json
{
  "agent_name": "your-agent-name",
  "group_id": "your_fivetran_group_id",
  "aws_region": "us-west-2",
  "ip_address_for_ssh_access": "your.ip.address.here/32",
  "fivetran_api_key": "your_fivetran_api_key",
  "fivetran_api_secret": "your_fivetran_api_secret"
}
```

#### Required Fields

- **agent_name**: Unique name for your agent (used in resource naming)
- **group_id**: Fivetran group ID for the agent
- **aws_region**: AWS region for deployment
- **ip_address_for_ssh_access**: Your IP address with /32 CIDR for SSH access
- **fivetran_api_key**: Fivetran API key for agent registration
- **fivetran_api_secret**: Fivetran API secret for authentication

### Environment Variables

The script uses several environment-specific variables:

- **AWS_ACCOUNT**: Target AWS account (internal-sales or internal-sales-dev)
- **AWS_PROFILE**: AWS CLI profile to use
- **TEAM**: Team name for resource tagging
- **ENVIRONMENT**: Department/environment for resource tagging
- **OWNER**: Owner email for resource tagging
- **EXPIRES_ON**: Expiration date for resource lifecycle management

## Deployment Script Usage

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **jq**: JSON processor for configuration parsing
3. **curl**: HTTP client for API calls
4. **Valid AWS Credentials**: Configured via AWS CLI or environment variables
5. **Fivetran API Access**: Valid API key and secret

### Basic Commands

#### Deploy Infrastructure
```bash
# Deploy with default configuration
./deploy-agent.sh deploy

# Deploy with custom configuration file
./deploy-agent.sh -c my-config.json deploy
```

#### Check Deployment Status
```bash
./deploy-agent.sh status
```

#### Delete Infrastructure
```bash
./deploy-agent.sh delete
```

#### Show Help
```bash
./deploy-agent.sh --help
```

### Command Line Options

- **-c, --config-file**: Specify custom configuration file
- **-e, --aws-account**: Override AWS account setting
- **--profile**: Specify AWS CLI profile
- **-h, --help**: Display help information

### Deployment Process

1. **Environment Validation**
   - Checks for required tools (jq, curl, AWS CLI)
   - Validates configuration file
   - Displays deployment summary

2. **User Confirmation**
   - Shows all configuration parameters
   - Requests user confirmation before proceeding
   - No actions taken until confirmed

3. **Agent Registration**
   - Creates/registers agent with Fivetran API
   - Retrieves authentication token
   - Validates token retrieval

4. **Infrastructure Deployment**
   - Deploys CloudFormation stack with all parameters
   - Waits for stack completion
   - Retrieves and displays instance ID

5. **Post-Deployment**
   - Provides verification steps
   - Shows access instructions
   - Displays monitoring information

### References
- **Fivetran Documentation**: [Hybrid Deployment Guide](https://docs.fivetran.com/docs/hybrid-deployment)
- **AWS Documentation**: [CloudFormation User Guide](https://docs.aws.amazon.com/AWSCloudFormation/)
- **IAM Best Practices**: [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

---

## Practical Examples

### **Example 1: Adding Kinesis Streams Access**

To add Kinesis streams access to your agent:

1. **Add Policy to CloudFormation Template** (`agent-stack.yaml`):
```yaml
KinesisAccessPolicy:
  Type: AWS::IAM::Policy
  Properties:
    PolicyName: !Join ["-",[!Ref ProjectName, "Kinesis-Access"]]
    PolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Action:
            - kinesis:DescribeStream
            - kinesis:GetRecords
            - kinesis:GetShardIterator
            - kinesis:ListStreams
          Resource: "*"
    Roles:
      - Ref: DockerAgentEC2Role
```

2. **Redeploy the Stack**:
```bash
./deploy-agent.sh deploy
```

3. **Result**: Your agent now has immediate access to Kinesis streams for data syncing.

### **Example 2: Adding Redshift Access**

To add Redshift access to your agent:

1. **Add Policy to CloudFormation Template** (`agent-stack.yaml`):
```yaml
RedshiftAccessPolicy:
  Type: AWS::IAM::Policy
  Properties:
    PolicyName: !Join ["-",[!Ref ProjectName, "Redshift-Access"]]
    PolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Action:
            - redshift:DescribeClusters
            - redshift:DescribeLoggingStatus
            - redshift:DescribeResize
            - redshift:DescribeTables
            - redshift:DescribeSchemas
          Resource: "*"
    Roles:
      - Ref: DockerAgentEC2Role
```

2. **Redeploy the Stack**:
```bash
./deploy-agent.sh deploy
```

3. **Result**: Your agent now has immediate access to Redshift clusters for data syncing.

### **Example 3: Adding SQS Access**

To add SQS access to your agent:

1. **Add Policy to CloudFormation Template** (`agent-stack.yaml`):
```yaml
SQSAccessPolicy:
  Type: AWS::IAM::Policy
  Properties:
    PolicyName: !Join ["-",[!Ref ProjectName, "SQS-Access"]]
    PolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Action:
            - sqs:GetQueueAttributes
            - sqs:GetQueueUrl
            - sqs:ListQueues
            - sqs:ReceiveMessage
            - sqs:DeleteMessage
          Resource: "*"
    Roles:
      - Ref: DockerAgentEC2Role
```

2. **Redeploy the Stack**:
```bash
./deploy-agent.sh deploy
```

3. **Result**: Your agent now has immediate access to SQS queues for message processing.

---

**Note**: This infrastructure is designed for internal Fivetran use and follows company security and operational standards. Always review and test deployments in development environments before production use.
