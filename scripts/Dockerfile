# ─────────────────────────────────────────────
# Moodle 5.2.1 on PHP 8.3 + Apache
# Optimised for Railway deployment
# ─────────────────────────────────────────────
FROM php:8.3-apache

LABEL maintainer="your-email@example.com"
LABEL moodle.version="5.2.1"

# ── System dependencies ───────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libxml2-dev \
    libicu-dev \
    libpq-dev \
    libldap2-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libxslt1-dev \
    git \
    unzip \
    curl \
    cron \
    ghostscript \
    aspell \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ── PHP extensions required by Moodle ─────────
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j$(nproc) \
        gd \
        zip \
        xml \
        intl \
        pdo \
        pdo_mysql \
        mysqli \
        opcache \
        soap \
        mbstring \
        curl \
        exif \
        xsl \
        ldap

# ── PHP configuration for Moodle ──────────────
RUN { \
    echo 'max_input_vars = 5000'; \
    echo 'memory_limit = 256M'; \
    echo 'upload_max_filesize = 100M'; \
    echo 'post_max_size = 100M'; \
    echo 'max_execution_time = 300'; \
    echo 'max_input_time = 300'; \
    echo 'default_charset = UTF-8'; \
    echo 'session.cookie_secure = 1'; \
} > /usr/local/etc/php/conf.d/moodle.ini

# ── OPcache configuration ─────────────────────
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=60'; \
    echo 'opcache.fast_shutdown=1'; \
} > /usr/local/etc/php/conf.d/opcache.ini

# ── Apache configuration ──────────────────────
RUN a2enmod rewrite ssl headers

# Apache virtual host config
RUN { \
    echo '<VirtualHost *:80>'; \
    echo '    DocumentRoot /var/www/html'; \
    echo '    <Directory /var/www/html>'; \
    echo '        Options -Indexes +FollowSymLinks'; \
    echo '        AllowOverride All'; \
    echo '        Require all granted'; \
    echo '    </Directory>'; \
    echo '    ErrorLog ${APACHE_LOG_DIR}/error.log'; \
    echo '    CustomLog ${APACHE_LOG_DIR}/access.log combined'; \
    echo '</VirtualHost>'; \
} > /etc/apache2/sites-available/000-default.conf

# ── Download and install Moodle 5.2.1 ─────────
RUN curl -L https://download.moodle.org/download.php/direct/stable52/moodle-latest-52.tgz \
    -o /tmp/moodle.tgz \
    && tar -xzf /tmp/moodle.tgz -C /tmp \
    && cp -r /tmp/moodle/. /var/www/html/ \
    && rm -rf /tmp/moodle.tgz /tmp/moodle

# ── Set correct permissions ───────────────────
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# ── Create moodledata directory ───────────────
RUN mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/moodledata \
    && chmod -R 770 /var/moodledata

# ── Copy entrypoint and cron scripts ──────────
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/moodle-cron.sh /moodle-cron.sh
RUN chmod +x /entrypoint.sh /moodle-cron.sh

# ── Set up Moodle cron (runs every minute) ────
RUN echo "* * * * * www-data php /var/www/html/admin/cron.php >> /var/log/moodlecron.log 2>&1" \
    > /etc/cron.d/moodle-cron \
    && chmod 0644 /etc/cron.d/moodle-cron

# ── Expose port ───────────────────────────────
EXPOSE 80

# ── Healthcheck ───────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/login/index.php || exit 1

ENTRYPOINT ["/entrypoint.sh"]