FROM wordpress:6.4-php8.2-fpm

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY ./wordpress/wp-config.php /var/www/html/
COPY ./php/www.conf /usr/local/etc/php-fpm.d/

EXPOSE 9000