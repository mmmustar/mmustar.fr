#!/bin/bash

AWS_REGION="eu-west-3"
INSTANCE_TYPE="t3.micro"
ENV_FILE=".env.preprod"
KEY_NAME="preprod-key"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"

log() {
   echo "[INFO] $1"
}

error() {
   echo "[ERROR] $1"
}

create_network() {
   log "Création du VPC et des ressources réseau..."
   
   VPC_ID=$(aws ec2 create-vpc \
       --cidr-block $VPC_CIDR \
       --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=preprod-vpc}]' \
       --query 'Vpc.VpcId' \
       --output text)
   
   aws ec2 modify-vpc-attribute \
       --vpc-id $VPC_ID \
       --enable-dns-hostnames "{\"Value\":true}"

   SUBNET_ID=$(aws ec2 create-subnet \
       --vpc-id $VPC_ID \
       --cidr-block $SUBNET_CIDR \
       --availability-zone ${AWS_REGION}a \
       --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=preprod-subnet}]' \
       --query 'Subnet.SubnetId' \
       --output text)

   aws ec2 modify-subnet-attribute \
       --subnet-id $SUBNET_ID \
       --map-public-ip-on-launch

   IGW_ID=$(aws ec2 create-internet-gateway \
       --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=preprod-igw}]' \
       --query 'InternetGateway.InternetGatewayId' \
       --output text)
   
   aws ec2 attach-internet-gateway \
       --internet-gateway-id $IGW_ID \
       --vpc-id $VPC_ID

   ROUTE_TABLE_ID=$(aws ec2 create-route-table \
       --vpc-id $VPC_ID \
       --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=preprod-rt}]' \
       --query 'RouteTable.RouteTableId' \
       --output text)

   aws ec2 create-route \
       --route-table-id $ROUTE_TABLE_ID \
       --destination-cidr-block 0.0.0.0/0 \
       --gateway-id $IGW_ID

   aws ec2 associate-route-table \
       --route-table-id $ROUTE_TABLE_ID \
       --subnet-id $SUBNET_ID

   SG_ID=$(aws ec2 create-security-group \
       --group-name preprod-sg \
       --description "Security group for preprod environment" \
       --vpc-id $VPC_ID \
       --query 'GroupId' \
       --output text)

   aws ec2 authorize-security-group-ingress \
       --group-id $SG_ID \
       --protocol tcp \
       --port 22 \
       --cidr 0.0.0.0/0

   aws ec2 authorize-security-group-ingress \
       --group-id $SG_ID \
       --protocol tcp \
       --port 80 \
       --cidr 0.0.0.0/0

   aws ec2 authorize-security-group-ingress \
       --group-id $SG_ID \
       --protocol tcp \
       --port 443 \
       --cidr 0.0.0.0/0

   cat > $ENV_FILE << EOF
VPC_ID=$VPC_ID
SUBNET_ID=$SUBNET_ID
SECURITY_GROUP_ID=$SG_ID
IGW_ID=$IGW_ID
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
EOF

   log "Infrastructure réseau créée avec succès"
}

create_env() {
   if [ ! -f $ENV_FILE ]; then
       log "Création de l'infrastructure réseau..."
       create_network
   fi

   source $ENV_FILE
   
   log "Création de l'instance preprod..."
   
   INSTANCE_ID=$(aws ec2 run-instances \
       --region $AWS_REGION \
       --image-id ami-009d5fce35d17d28c \
       --instance-type $INSTANCE_TYPE \
       --key-name "$KEY_NAME" \
       --security-group-ids $SECURITY_GROUP_ID \
       --subnet-id $SUBNET_ID \
       --user-data '#!/bin/bash
amazon-linux-extras install docker
systemctl enable docker
systemctl start docker
usermod -a -G docker ec2-user
yum install -y aws-cli
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose' \
       --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=preprod-instance},{Key=Environment,Value=preprod}]' \
       --query 'Instances[0].InstanceId' \
       --output text)
       
   log "Attente du démarrage de l'instance..."
   aws ec2 wait instance-running --instance-ids $INSTANCE_ID
   
   log "Attente de l'initialisation complète..."
   aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID
   
   INSTANCE_IP=$(aws ec2 describe-instances \
       --instance-ids $INSTANCE_ID \
       --query 'Reservations[0].Instances[0].PublicIpAddress' \
       --output text)

   cat >> $ENV_FILE << EOF
EC2_PREPROD_HOST=$INSTANCE_IP
EC2_PREPROD_INSTANCE_ID=$INSTANCE_ID
EOF

   log "Instance preprod créée avec succès :"
   log "- ID : $INSTANCE_ID"
   log "- IP : $INSTANCE_IP"
   log "Pour une connexion SSH : ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$INSTANCE_IP"
}

destroy_env() {
   if [ ! -f $ENV_FILE ]; then
       error "Fichier $ENV_FILE non trouvé"
       exit 1
   fi

   source $ENV_FILE

   if [ ! -z "$ROUTE_TABLE_ID" ]; then
       log "Suppression de la route vers internet..."
       aws ec2 delete-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0
   fi

   if [ ! -z "$IGW_ID" ] && [ ! -z "$VPC_ID" ]; then
       log "Détachement de l'Internet Gateway..."
       aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
   fi

   if [ ! -z "$IGW_ID" ]; then
       log "Suppression de l'Internet Gateway..."
       aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
   fi

   if [ ! -z "$ROUTE_TABLE_ID" ]; then
       ASSOCIATION_ID=$(aws ec2 describe-route-tables \
           --route-table-id $ROUTE_TABLE_ID \
           --query 'RouteTables[0].Associations[0].RouteTableAssociationId' \
           --output text)
       if [ ! -z "$ASSOCIATION_ID" ] && [ "$ASSOCIATION_ID" != "None" ]; then
           log "Désassociation de la table de routage..."
           aws ec2 disassociate-route-table --association-id $ASSOCIATION_ID
       fi
   fi

   if [ ! -z "$ROUTE_TABLE_ID" ]; then
       log "Suppression de la table de routage..."
       aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID
   fi

   if [ ! -z "$EC2_PREPROD_INSTANCE_ID" ]; then
       log "Destruction de l'instance $EC2_PREPROD_INSTANCE_ID..."
       aws ec2 terminate-instances --instance-ids $EC2_PREPROD_INSTANCE_ID
       log "Attente de la fin de la terminaison de l'instance..."
       aws ec2 wait instance-terminated --instance-ids $EC2_PREPROD_INSTANCE_ID
   fi

   if [ ! -z "$SECURITY_GROUP_ID" ]; then
       log "Suppression du groupe de sécurité..."
       aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID
   fi

   if [ ! -z "$SUBNET_ID" ]; then
       log "Suppression du subnet..."
       aws ec2 delete-subnet --subnet-id $SUBNET_ID
   fi

   if [ ! -z "$VPC_ID" ]; then
       log "Suppression du VPC..."
       aws ec2 delete-vpc --vpc-id $VPC_ID
   fi

   rm $ENV_FILE
   log "Environnement preprod complètement détruit"
}

case "$1" in
   "create")
       create_env
       ;;
   "destroy")
       destroy_env
       ;;
   *)
       echo "Usage: $0 {create|destroy}"
       exit 1
       ;;
esac