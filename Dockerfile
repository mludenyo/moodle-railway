FROM php:8.3-apache

# Cache bust - force rebuild
ARG CACHEBUST=2

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
    libsodium-dev \
    git \
    unzip \
    curl \
    cron \
    ghostscript \
    aspell \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# ── PHP extensions ────────────────────────────
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap \
    && docker-php-ext-install -j$(nproc) \
        gd zip xml intl pdo pdo_mysql mysqli \
        opcache soap mbstring curl exif xsl ldap sodium

# ── PHP config ────────────────────────────────
RUN { \
    echo 'max_input_vars = 5000'; \
    echo 'memory_limit = 256M'; \
    echo 'upload_max_filesize = 100M'; \
    echo 'post_max_size = 100M'; \
    echo 'max_execution_time = 300'; \
    echo 'max_input_time = 300'; \
} > /usr/local/etc/php/conf.d/moodle.ini

RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=60'; \
} > /usr/local/etc/php/conf.d/opcache.ini

# ── Apache config ─────────────────────────────
# Fix MPM conflict - only do this once
RUN a2dismod mpm_event mpm_worker mpm_itk 2>/dev/null || true \
    && a2enmod mpm_prefork rewrite headers

# Apache virtual host
RUN { \
    echo '<VirtualHost *:APACHE_PORT_PLACEHOLDER>'; \
    echo '    ServerName localhost'; \
    echo '    DocumentRoot /var/www/html/public'; \
    echo '    <Directory /var/www/html/public>'; \
    echo '        Options -Indexes +FollowSymLinks'; \
    echo '        AllowOverride All'; \
    echo '        Require all granted'; \
    echo '    </Directory>'; \
    echo '    SetEnvIf X-Forwarded-Proto https HTTPS=on'; \
    echo '    ErrorLog ${APACHE_LOG_DIR}/error.log'; \
    echo '    CustomLog ${APACHE_LOG_DIR}/access.log combined'; \
    echo '</VirtualHost>'; \
} > /etc/apache2/sites-available/000-default.conf

# Enable Apache env variable expansion
RUN echo 'ServerName localhost' >> /etc/apache2/apache2.conf

# ── config.php template ───────────────────────
RUN cat > /config-template.php << 'CONFIGEOF'
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();
$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'DB_HOST';
$CFG->dbname    = 'DB_NAME';
$CFG->dbuser    = 'DB_USER';
$CFG->dbpass    = 'DB_PASS';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport'    => 'DB_PORT',
    'dbsocket'  => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
    'ssl_verify_server_cert' => false,
);
$CFG->wwwroot      = 'DB_WWWROOT';
$CFG->dataroot     = '/var/moodledata';
$CFG->admin        = 'admin';
// $CFG->sslproxy     = true;   // Disabled for Railway
// $CFG->reverseproxy = true;   // Disabled for Railway
$CFG->directorypermissions = 02777;
$CFG->pathtophp    = '/usr/local/bin/php';
require_once(__DIR__ . '/lib/setup.php');
CONFIGEOF

# ── Install Moodle ────────────────────────────
COPY moodle-5.2.1.tgz /tmp/moodle.tgz
RUN tar -xzf /tmp/moodle.tgz -C /tmp \
    && cp -r /tmp/moodle/. /var/www/html/ \
    && rm -rf /tmp/moodle.tgz /tmp/moodle

RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

RUN mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/moodledata \
    && chmod -R 770 /var/moodledata

RUN echo "* * * * * www-data php /var/www/html/admin/cron.php >> /var/log/moodlecron.log 2>&1" \
    > /etc/cron.d/moodle-cron \
    && chmod 0644 /etc/cron.d/moodle-cron

# ── Entrypoint ────────────────────────────────
RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    'echo "--- Moodle 5.2.1 Starting ---"' \
    '' \
    '# ── FIX MPM CONFLICT (Railway environment fix) ──' \
    'echo "Fixing MPM conflict..."' \
    '# Forcefully remove ALL MPM module symlinks' \
    'rm -f /etc/apache2/mods-enabled/mpm_*.load 2>/dev/null || true' \
    'rm -f /etc/apache2/mods-enabled/mpm_*.conf 2>/dev/null || true' \
    '# Enable only mpm_prefork' \
    'a2enmod mpm_prefork' \
    'echo "MPM fix complete. Enabled modules:"' \
    'ls -la /etc/apache2/mods-enabled/mpm_*.load 2>/dev/null || echo "ERROR: No MPM enabled"' \
    '' \
    'echo "Waiting for database at $MOODLE_DB_HOST..."' \
    'until mysql -h "$MOODLE_DB_HOST" -u "$MOODLE_DB_USER" -p"$MOODLE_DB_PASSWORD" --ssl=0 --connect-timeout=5 -e "SELECT 1" > /dev/null 2>&1; do' \
    '    echo "  DB not ready - retrying in 3s..."' \
    '    sleep 3' \
    'done' \
    'echo "Database is ready!"' \
    'CONFIG_FILE="/var/www/html/config.php"' \
    'if [ ! -f "$CONFIG_FILE" ]; then' \
    '    echo "Writing config.php..."' \
    '    sed -e "s|DB_HOST|${MOODLE_DB_HOST}|g" -e "s|DB_NAME|${MOODLE_DB_NAME}|g" -e "s|DB_USER|${MOODLE_DB_USER}|g" -e "s|DB_PASS|${MOODLE_DB_PASSWORD}|g" -e "s|DB_PORT|${MOODLE_DB_PORT:-3306}|g" -e "s|DB_WWWROOT|${MOODLE_WWWROOT}|g" /config-template.php > "$CONFIG_FILE"' \
    '    chown www-data:www-data "$CONFIG_FILE"' \
    '    chmod 640 "$CONFIG_FILE"' \
    '    echo "config.php written."' \
    'fi' \
    'if ! mysql -h "$MOODLE_DB_HOST" -u "$MOODLE_DB_USER" -p"$MOODLE_DB_PASSWORD" --ssl=0 "$MOODLE_DB_NAME" -e "SELECT COUNT(*) FROM mdl_user;" > /dev/null 2>&1; then' \
    '    echo "Installing Moodle..."' \
    '    php /var/www/html/admin/cli/install_database.php \' \
    '        --agree-license \' \
    '        --fullname="${MOODLE_SITE_FULLNAME:-My Moodle Site}" \' \
    '        --shortname="${MOODLE_SITE_SHORTNAME:-moodle}" \' \
    '        --adminuser="${MOODLE_ADMIN_USER:-admin}" \' \
    '        --adminpass="${MOODLE_ADMIN_PASSWORD:-Admin1234!}" \' \
    '        --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}"' \
    '    echo "Installation complete!"' \
    'else' \
    '    echo "Moodle already installed - checking upgrades..."' \
    '    php /var/www/html/admin/cli/upgrade.php --non-interactive || true' \
    'fi' \
    'chown -R www-data:www-data /var/moodledata' \
    'cron' \
    'echo "Starting Apache..."' \
    'APACHE_PORT=${PORT:-80}' \
    'sed -i "s/Listen 80/Listen $APACHE_PORT/" /etc/apache2/ports.conf' \
    'sed -i "s/APACHE_PORT_PLACEHOLDER/$APACHE_PORT/" /etc/apache2/sites-available/000-default.conf' \
    'exec apache2-foreground' \
    > /entrypoint.sh \
    && chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]