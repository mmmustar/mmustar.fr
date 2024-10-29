#!/bin/bash
set -e

TAG="book"
REGION="eu-west-3"
DB_INSTANCE_IDENTIFIER="wordpress-db"
EC2_USER="ec2-user"
EC2_IP=$(cat instance_ip.txt)
KEY_PATH="conf/aws-key-pair.pem"

BACKUP_FILE=$(ls -t database_backup/wordpress_backup_*.sql.gz | head -1)
if [ ! -f "$BACKUP_FILE" ]; then
    echo "No backup file found in database_backup/"
    exit 1
fi
echo "Using backup file: $BACKUP_FILE"

SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id $TAG \
    --region $REGION \
    --query 'SecretString' \
    --output text)

DB_NAME=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_DATABASE":")[^"]*')
DB_USER=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_USER":")[^"]*')
DB_PASSWORD=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_PASSWORD":")[^"]*')
ROOT_PASSWORD=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_ROOT_PASSWORD":")[^"]*')

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=WP-VPC" --query 'Vpcs[0].VpcId' --output text)
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].CidrBlock' --output text)
echo "Using VPC: $VPC_ID with CIDR: $VPC_CIDR"

echo "Setting up subnets..."
EXISTING_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
    --output text)

if [[ $(echo "$EXISTING_SUBNETS" | wc -l) -lt 2 ]]; then
    echo "Creating additional subnet for RDS..."
    SUBNET_PREFIX=$(echo $VPC_CIDR | cut -d'.' -f1-2)
    NEW_SUBNET_CIDR="$SUBNET_PREFIX.2.0/24"
    
    NEW_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block $NEW_SUBNET_CIDR \
        --availability-zone eu-west-3b \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=WP-Subnet-2},{Key=$TAG,Value=$TAG}]" \
        --query 'Subnet.SubnetId' \
        --output text)
    
    ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[0].RouteTableId' \
        --output text)
    
    aws ec2 associate-route-table \
        --subnet-id $NEW_SUBNET_ID \
        --route-table-id $ROUTE_TABLE_ID \
        --output text > /dev/null
    
    echo "Created new subnet in eu-west-3b"
fi

SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' \
    --output text)

RDS_SG_ID=$(aws ec2 describe-security-groups \
    --filters Name=group-name,Values=WordPress-RDS-SG Name=vpc-id,Values=$VPC_ID \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ -z "$RDS_SG_ID" ]; then
    RDS_SG_ID=$(aws ec2 create-security-group \
        --group-name WordPress-RDS-SG \
        --description "Security group for WordPress RDS" \
        --vpc-id $VPC_ID \
        --query 'GroupId' \
        --output text)
    
    EC2_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=WP-SecurityGroup" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    aws ec2 authorize-security-group-ingress \
        --group-id $RDS_SG_ID \
        --protocol tcp \
        --port 3306 \
        --source-group $EC2_SG_ID \
        --output text > /dev/null
fi

echo "Setting up subnet group..."
SUBNET_GROUP_EXISTS=$(aws rds describe-db-subnet-groups \
    --query 'DBSubnetGroups[?DBSubnetGroupName==`wordpress-subnet-group`].DBSubnetGroupName' \
    --output text 2>/dev/null || echo "")

if [ -z "$SUBNET_GROUP_EXISTS" ]; then
    echo "Creating DB subnet group..."
    aws rds create-db-subnet-group \
        --db-subnet-group-name wordpress-subnet-group \
        --db-subnet-group-description "Subnet group for WordPress RDS" \
        --subnet-ids $SUBNET_IDS \
        --tags Key=$TAG,Value=$TAG \
        --output text > /dev/null
fi

RDS_EXISTS=$(aws rds describe-db-instances \
    --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
    --query 'DBInstances[0].DBInstanceIdentifier' \
    --output text 2>/dev/null || echo "")

if [ -z "$RDS_EXISTS" ]; then
    echo "Creating RDS instance (this will take about 10-15 minutes)..."
    aws rds create-db-instance \
        --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
        --db-instance-class db.t3.micro \
        --engine mariadb \
        --engine-version 10.6.14 \
        --master-username $DB_USER \
        --master-user-password $DB_PASSWORD \
        --allocated-storage 20 \
        --db-name $DB_NAME \
        --vpc-security-group-ids $RDS_SG_ID \
        --db-subnet-group-name wordpress-subnet-group \
        --backup-retention-period 7 \
        --no-multi-az \
        --no-publicly-accessible \
        --tags Key=Name,Value=wordpress-db Key=$TAG,Value=$TAG \
        --output text > /dev/null

    echo "Waiting for RDS instance to be available..."
    aws rds wait db-instance-available \
        --db-instance-identifier $DB_INSTANCE_IDENTIFIER
fi

RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

echo "Importing database dump..."
gunzip -c $BACKUP_FILE > temp_dump.sql
ssh -i $KEY_PATH $EC2_USER@$EC2_IP "sudo yum install -y mysql" > /dev/null 2>&1
scp -i $KEY_PATH temp_dump.sql $EC2_USER@$EC2_IP:~/
ssh -i $KEY_PATH $EC2_USER@$EC2_IP "mysql -h $RDS_ENDPOINT -u $DB_USER -p'$DB_PASSWORD' $DB_NAME < temp_dump.sql"

rm -f temp_dump.sql
ssh -i $KEY_PATH $EC2_USER@$EC2_IP "rm -f temp_dump.sql"

aws secretsmanager update-secret \
    --secret-id $TAG \
    --region $REGION \
    --secret-string "{
    \"MYSQL_DATABASE\": \"$DB_NAME\",
    \"MYSQL_USER\": \"$DB_USER\",
    \"MYSQL_PASSWORD\": \"$DB_PASSWORD\",
    \"MYSQL_ROOT_PASSWORD\": \"$ROOT_PASSWORD\",
    \"MYSQL_HOST\": \"$RDS_ENDPOINT\",
    \"PMA_HOST\": \"$RDS_ENDPOINT\",
    \"PMA_PORT\": \"3306\",
    \"PMA_USER\": \"$DB_USER\",
    \"PMA_PASSWORD\": \"$DB_PASSWORD\",
    \"DB_HOST\": \"$RDS_ENDPOINT\"
}" > /dev/null

echo "RDS setup completed!"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Next step: Update wp-config.php with new RDS endpoint"