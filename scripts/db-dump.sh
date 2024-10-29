#!/bin/bash
set -e

echo "Starting MariaDB database backup..."

EC2_USER="ec2-user"
EC2_IP=$(cat instance_ip.txt)
KEY_PATH="conf/aws-key-pair.pem"
BACKUP_DIR="database_backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DUMP_FILE="wordpress_backup_${TIMESTAMP}.sql"
ROOT_PASSWORD="StrongRootPass123!"

mkdir -p $BACKUP_DIR 2>/dev/null || true

echo "Creating database dump..."
ssh -T -i $KEY_PATH $EC2_USER@$EC2_IP "mysqldump --user=root --password='$ROOT_PASSWORD' wp_database > $DUMP_FILE"

echo "Compressing dump file..."
ssh -T -i $KEY_PATH $EC2_USER@$EC2_IP "gzip $DUMP_FILE"

echo "Copying dump file locally..."
scp -i $KEY_PATH $EC2_USER@$EC2_IP:${DUMP_FILE}.gz $BACKUP_DIR/

echo "Cleaning up..."
ssh -T -i $KEY_PATH $EC2_USER@$EC2_IP "rm ${DUMP_FILE}.gz"

echo "Backup completed: $BACKUP_DIR/${DUMP_FILE}.gz"