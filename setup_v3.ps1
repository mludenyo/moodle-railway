# =============================================
# Moodle 5.2.1 Railway - Setup Script (v3)
# Run this in PowerShell as Administrator
# =============================================

$projectPath = "C:\Projects\moodle-railway"
Set-Location $projectPath

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Moodle 5.2.1 Railway - Setup (v3)" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ── Create folders ────────────────────────────
Write-Host "Creating folder structure..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "scripts" | Out-Null
New-Item -ItemType Directory -Force -Path "mysql\conf.d" | Out-Null
Write-Host "Done." -ForegroundColor Green

# ── .gitattributes ────────────────────────────
Write-Host "Creating .gitattributes..." -ForegroundColor Yellow
$gitattributes = @"
*.sh        text eol=lf
Dockerfile  text eol=lf
*.cnf       text eol=lf
*.php       text eol=lf
*.yml       text eol=lf
*.env*      text eol=lf
*.bat       text eol=crlf
*.cmd       text eol=crlf
"@
[System.IO.File]::WriteAllText("$projectPath\.gitattributes", $gitattributes.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── Dockerfile ────────────────────────────────
Write-Host "Creating Dockerfile..." -ForegroundColor Yellow
$dockerfile = @'
FROM php:8.3-apache

LABEL maintainer="your-email@example.com"
LABEL moodle.version="5.2.1"

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
        ldap \
        sodium

RUN { \
    echo 'max_input_vars = 5000'; \
    echo 'memory_limit = 256M'; \
    echo 'upload_max_filesize = 100M'; \
    echo 'post_max_size = 100M'; \
    echo 'max_execution_time = 300'; \
    echo 'max_input_time = 300'; \
    echo 'default_charset = UTF-8'; \
} > /usr/local/etc/php/conf.d/moodle.ini

RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=60'; \
    echo 'opcache.fast_shutdown=1'; \
} > /usr/local/etc/php/conf.d/opcache.ini

RUN a2enmod rewrite ssl headers

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

COPY moodle-5.2.1.tgz /tmp/moodle.tgz
RUN tar -xzf /tmp/moodle.tgz -C /tmp \
    && cp -r /tmp/moodle/. /var/www/html/ \
    && rm -rf /tmp/moodle.tgz /tmp/moodle

RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

RUN mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/moodledata \
    && chmod -R 770 /var/moodledata

COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/moodle-cron.sh /moodle-cron.sh
RUN chmod +x /entrypoint.sh /moodle-cron.sh

RUN echo "* * * * * www-data php /var/www/html/admin/cron.php >> /var/log/moodlecron.log 2>&1" \
    > /etc/cron.d/moodle-cron \
    && chmod 0644 /etc/cron.d/moodle-cron

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -f http://localhost/login/index.php || exit 1

ENTRYPOINT ["/entrypoint.sh"]
'@
[System.IO.File]::WriteAllText("$projectPath\Dockerfile", $dockerfile.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── docker-compose.yml ────────────────────────
Write-Host "Creating docker-compose.yml..." -ForegroundColor Yellow
$dockercompose = @'
services:

  db:
    image: mysql:8.0.36
    container_name: moodle_db
    restart: unless-stopped
    command:
      - --tls-version=
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --innodb-buffer-pool-size=256M
      - --max-allowed-packet=64M
      - --wait-timeout=600
    environment:
      MYSQL_ROOT_PASSWORD: rootpassword
      MYSQL_DATABASE: moodle
      MYSQL_USER: moodleuser
      MYSQL_PASSWORD: moodlepassword
    volumes:
      - db_data:/var/lib/mysql
    ports:
      - "3306:3306"
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "moodleuser", "-pmoodlepassword"]
      interval: 10s
      timeout: 10s
      retries: 15
      start_period: 30s
    networks:
      - moodle_net

  moodle:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: moodle_app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      MOODLE_DB_HOST: db
      MOODLE_DB_PORT: 3306
      MOODLE_DB_NAME: moodle
      MOODLE_DB_USER: moodleuser
      MOODLE_DB_PASSWORD: moodlepassword
      MOODLE_WWWROOT: http://localhost:8080
      MOODLE_SITE_FULLNAME: My Moodle Site
      MOODLE_SITE_SHORTNAME: moodle
      MOODLE_SITE_SUMMARY: Welcome to Moodle
      MOODLE_ADMIN_USER: admin
      MOODLE_ADMIN_PASSWORD: Admin1234!
      MOODLE_ADMIN_EMAIL: admin@example.com
    volumes:
      - moodledata:/var/moodledata
    ports:
      - "8080:80"
    networks:
      - moodle_net

volumes:
  db_data:
    driver: local
  moodledata:
    driver: local

networks:
  moodle_net:
    driver: bridge
'@
[System.IO.File]::WriteAllText("$projectPath\docker-compose.yml", $dockercompose.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── mysql/conf.d/moodle.cnf ───────────────────
Write-Host "Creating mysql/conf.d/moodle.cnf..." -ForegroundColor Yellow
$mysqlcnf = @'
[mysqld]
character-set-server    = utf8mb4
collation-server        = utf8mb4_unicode_ci
innodb_buffer_pool_size = 256M
max_allowed_packet      = 64M
wait_timeout            = 600
interactive_timeout     = 600

[client]
default-character-set   = utf8mb4
'@
[System.IO.File]::WriteAllText("$projectPath\mysql\conf.d\moodle.cnf", $mysqlcnf.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── scripts/entrypoint.sh ─────────────────────
Write-Host "Creating scripts/entrypoint.sh..." -ForegroundColor Yellow
$entrypoint = @'
#!/bin/bash
set -e

echo "----------------------------------------------"
echo " Moodle 5.2.1 - Starting up..."
echo "----------------------------------------------"

# Check required variables
required_vars=(MOODLE_DB_HOST MOODLE_DB_NAME MOODLE_DB_USER MOODLE_DB_PASSWORD MOODLE_WWWROOT)
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required variable $var is not set."
        exit 1
    fi
done

# Wait for database
echo "Waiting for database at $MOODLE_DB_HOST..."
until mysql -h "$MOODLE_DB_HOST" \
            -u "$MOODLE_DB_USER" \
            -p"$MOODLE_DB_PASSWORD" \
            --ssl-mode=DISABLED \
            --connect-timeout=5 \
            -e "SELECT 1" > /dev/null 2>&1; do
    echo "  Database not ready - retrying in 3s..."
    sleep 3
done
echo "Database is ready!"

# Generate config.php if missing
CONFIG_FILE="/var/www/html/config.php"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Generating config.php..."
    cat > "$CONFIG_FILE" << 'PHPEOF'
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();
PHPEOF

    cat >> "$CONFIG_FILE" << PHPEOF
\$CFG->dbtype    = 'mysqli';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = '${MOODLE_DB_HOST}';
\$CFG->dbname    = '${MOODLE_DB_NAME}';
\$CFG->dbuser    = '${MOODLE_DB_USER}';
\$CFG->dbpass    = '${MOODLE_DB_PASSWORD}';
\$CFG->prefix    = 'mdl_';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport'    => '${MOODLE_DB_PORT:-3306}',
    'dbsocket'  => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
    'ssl_ca'    => '',
    'ssl_verify_server_cert' => false,
);
\$CFG->wwwroot   = '${MOODLE_WWWROOT}';
\$CFG->dataroot  = '/var/moodledata';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 02777;
\$CFG->pathtophp = '/usr/local/bin/php';
require_once(__DIR__ . '/lib/setup.php');
PHPEOF

    chown www-data:www-data "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
    echo "config.php created."
fi

# Install or upgrade Moodle
if ! mysql -h "$MOODLE_DB_HOST" \
           -u "$MOODLE_DB_USER" \
           -p"$MOODLE_DB_PASSWORD" \
           --ssl-mode=DISABLED \
           "$MOODLE_DB_NAME" \
           -e "SELECT COUNT(*) FROM mdl_user;" > /dev/null 2>&1; then
    echo "Running Moodle installation..."
    php /var/www/html/admin/cli/install_database.php \
        --agree-license \
        --fullname="${MOODLE_SITE_FULLNAME:-My Moodle Site}" \
        --shortname="${MOODLE_SITE_SHORTNAME:-moodle}" \
        --adminuser="${MOODLE_ADMIN_USER:-admin}" \
        --adminpass="${MOODLE_ADMIN_PASSWORD:-Admin1234!}" \
        --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}"
    echo "Moodle installation complete!"
else
    echo "Already installed - checking for upgrades..."
    php /var/www/html/admin/cli/upgrade.php --non-interactive || true
fi

# Fix permissions
chown -R www-data:www-data /var/moodledata
chmod -R 770 /var/moodledata

# Start cron
cron

echo "Starting Apache..."
exec apache2-foreground
'@
[System.IO.File]::WriteAllText("$projectPath\scripts\entrypoint.sh", $entrypoint.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── scripts/moodle-cron.sh ────────────────────
Write-Host "Creating scripts/moodle-cron.sh..." -ForegroundColor Yellow
$cron = @'
#!/bin/bash
/usr/local/bin/php /var/www/html/admin/cron.php >> /var/log/moodlecron.log 2>&1
'@
[System.IO.File]::WriteAllText("$projectPath\scripts\moodle-cron.sh", $cron.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── railway.env.example ───────────────────────
Write-Host "Creating railway.env.example..." -ForegroundColor Yellow
$railwayenv = @'
MOODLE_DB_HOST=${{MySQL.MYSQLHOST}}
MOODLE_DB_PORT=${{MySQL.MYSQLPORT}}
MOODLE_DB_NAME=${{MySQL.MYSQLDATABASE}}
MOODLE_DB_USER=${{MySQL.MYSQLUSER}}
MOODLE_DB_PASSWORD=${{MySQL.MYSQLPASSWORD}}
MOODLE_WWWROOT=https://your-app.up.railway.app
MOODLE_SITE_FULLNAME=My Moodle Site
MOODLE_SITE_SHORTNAME=moodle
MOODLE_SITE_SUMMARY=Welcome to Moodle
MOODLE_ADMIN_USER=admin
MOODLE_ADMIN_PASSWORD=YourStrongPassword123!
MOODLE_ADMIN_EMAIL=your-email@example.com
MOODLE_SMTP_HOST=sandbox.smtp.mailtrap.io
MOODLE_SMTP_PORT=587
MOODLE_SMTP_USER=your_mailtrap_user
MOODLE_SMTP_PASSWORD=your_mailtrap_password
MOODLE_SMTP_SECURE=tls
MOODLE_NOREPLY_EMAIL=noreply@yourdomain.com
'@
[System.IO.File]::WriteAllText("$projectPath\railway.env.example", $railwayenv.Replace("`r`n", "`n"), [System.Text.Encoding]::UTF8)
Write-Host "Done." -ForegroundColor Green

# ── Summary ───────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " All files created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host " NEXT STEPS:" -ForegroundColor Yellow
Write-Host " 1. Make sure moodle-5.2.1.tgz is in this folder"
Write-Host " 2. Run: docker-compose down -v"
Write-Host " 3. Run: docker-compose up --build"
Write-Host "=============================================" -ForegroundColor Cyan
