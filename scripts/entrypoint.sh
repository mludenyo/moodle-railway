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