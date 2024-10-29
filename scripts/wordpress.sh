#!/bin/bash

set -e

SECRET_NAME="book"
REGION="eu-west-3"

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id $SECRET_NAME --region $REGION --query 'SecretString' --output text)

DB_NAME=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_DATABASE":")[^"]*')
DB_USER=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_USER":")[^"]*')
DB_PASSWORD=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_PASSWORD":")[^"]*')
DB_ROOT_PASSWORD=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_ROOT_PASSWORD":")[^"]*')
DB_HOST=$(echo $SECRET_JSON | grep -oP '(?<="MYSQL_HOST":")[^"]*')

WORDPRESS_DIR="/var/www/html"
CUSTOM_INI="/etc/php.d/custom.ini"
NGINX_CONF="/etc/nginx/conf.d/default.conf"

sudo yum update -y
sudo amazon-linux-extras enable nginx1

sudo amazon-linux-extras enable php7.4
sudo yum clean metadata
sudo yum install -y php php-cli php-pdo php-fpm php-json php-mysqlnd

sudo yum install -y nginx mariadb-server wget unzip

sudo sed -i 's/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm\/www.sock/' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.owner = nobody/listen.owner = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.group = nobody/listen.group = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/group = apache/group = nginx/' /etc/php-fpm.d/www.conf

sudo mkdir -p /var/lib/php/session
sudo chown -R nginx:nginx /var/lib/php

sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo systemctl start nginx
sudo systemctl enable nginx
sudo systemctl start php-fpm
sudo systemctl enable php-fpm

sudo mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$DB_ROOT_PASSWORD');"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"

sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE User='$DB_USER';" | grep -q "$DB_USER" || sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

sudo wget https://wordpress.org/latest.tar.gz
sudo tar -xzf latest.tar.gz
sudo rsync -avP wordpress/ $WORDPRESS_DIR/
sudo chown -R nginx:nginx $WORDPRESS_DIR
sudo rm -rf wordpress latest.tar.gz

sudo cp $WORDPRESS_DIR/wp-config-sample.php $WORDPRESS_DIR/wp-config.php
sudo sed -i "s/database_name_here/$DB_NAME/" $WORDPRESS_DIR/wp-config.php
sudo sed -i "s/username_here/$DB_USER/" $WORDPRESS_DIR/wp-config.php
sudo sed -i "s/password_here/$DB_PASSWORD/" $WORDPRESS_DIR/wp-config.php

sudo tee $NGINX_CONF > /dev/null <<EOL
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }

    location /phpmyadmin {
        root /usr/share/nginx/html;
        index index.php index.html index.htm;
        location ~ ^/phpmyadmin/(.+\.php)$ {
            try_files \$uri =404;
            root /usr/share/nginx/html;
            fastcgi_pass unix:/var/run/php-fpm/www.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
            root /usr/share/nginx/html;
        }
    }
}
EOL

sudo nginx -t

sudo systemctl restart nginx

sudo tee $CUSTOM_INI > /dev/null <<EOL
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
EOL

sudo systemctl restart php-fpm

cd /usr/share/nginx/html
sudo wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
sudo tar -xzf phpMyAdmin-latest-all-languages.tar.gz
sudo mv phpMyAdmin-*-all-languages phpmyadmin
sudo rm phpMyAdmin-latest-all-languages.tar.gz
sudo chown -R nginx:nginx /usr/share/nginx/html/phpmyadmin

sudo cp /usr/share/nginx/html/phpmyadmin/config.sample.inc.php /usr/share/nginx/html/phpmyadmin/config.inc.php
sudo sed -i "s/localhost/$DB_HOST/" /usr/share/nginx/html/phpmyadmin/config.inc.php

sudo systemctl restart nginx
sudo systemctl restart php-fpm
sudo systemctl restart mariadb

echo "Installation completed."