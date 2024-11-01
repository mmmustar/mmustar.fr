FROM php:7.4-fpm-alpine

RUN apk add --no-cache \
    freetype \
    libjpeg-turbo \
    libpng \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    icu-dev \
    oniguruma-dev \
    libzip-dev \
    linux-headers \
    $PHPIZE_DEPS \
    openssl \
    openssl-dev

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    gd \
    intl \
    mbstring \
    mysqli \
    pdo \
    pdo_mysql \
    zip \
    opcache

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && composer require aws/aws-sdk-php

RUN mkdir -p /var/www/html /run/php-fpm /var/log/php-fpm /var/lib/php/session \
    && chown -R www-data:www-data /var/www/html /run/php-fpm /var/log/php-fpm /var/lib/php/session

COPY php/www.conf /usr/local/etc/php-fpm.d/www.conf

WORKDIR /var/www/html
RUN curl -O https://wordpress.org/latest.tar.gz \
    && tar -xzf latest.tar.gz \
    && mv wordpress/* . \
    && rm -rf wordpress latest.tar.gz

COPY wordpress/wp-config.php /var/www/html/wp-config.php

USER www-data

EXPOSE 9000

CMD ["php-fpm", "-F"]