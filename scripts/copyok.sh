#!/bin/bash

EC2_USER="ec2-user"
EC2_IP=$(cat instance_ip.txt)
KEY_PATH="conf/aws-key-pair.pem"
RDS_HOST="wordpress-db.cdaookoquxxr.eu-west-3.rds.amazonaws.com"
DB_USER="wp_user"
DB_PASS="StrongWpUserPass456!"
DB_NAME="wp_database"

echo "Vérification de la base de données RDS..."

echo "1. Test de connexion..."
ssh -i $KEY_PATH $EC2_USER@$EC2_IP \
"mysql -h $RDS_HOST -u $DB_USER -p'$DB_PASS' $DB_NAME -e 'SELECT 1;' > /dev/null && echo 'Connexion OK' || echo 'Échec de connexion'"

echo -e "\n2. Nombre de tables:"
ssh -i $KEY_PATH $EC2_USER@$EC2_IP \
"mysql -h $RDS_HOST -u $DB_USER -p'$DB_PASS' $DB_NAME -e 'SHOW TABLES;' | wc -l"

echo -e "\n3. Vérification des données WordPress:"
ssh -i $KEY_PATH $EC2_USER@$EC2_IP \
"mysql -h $RDS_HOST -u $DB_USER -p'$DB_PASS' $DB_NAME -e '
SELECT \"Users\" as Type, COUNT(*) as Count FROM wp_users
UNION ALL
SELECT \"Posts\", COUNT(*) FROM wp_posts
UNION ALL
SELECT \"Options\", COUNT(*) FROM wp_options;'"

echo -e "\n4. Tables et leurs enregistrements:"
ssh -i $KEY_PATH $EC2_USER@$EC2_IP \
"mysql -h $RDS_HOST -u $DB_USER -p'$DB_PASS' $DB_NAME -e '
SELECT 
    TABLE_NAME as TableName,
    TABLE_ROWS as RowCount
FROM 
    information_schema.tables 
WHERE 
    table_schema = \"$DB_NAME\"
    AND TABLE_TYPE = \"BASE TABLE\"
ORDER BY 
    TABLE_ROWS DESC;'"