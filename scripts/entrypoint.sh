#!/bin/bash
# ─────────────────────────────────────────────
# Moodle Docker Entrypoint
# Runs on every container start
# ─────────────────────────────────────────────
set -e

echo "──────────────────────────────────────"
echo " Moodle 5.2.1 - Starting up..."
echo "──────────────────────────────────────"

# ── Required environment variable check ──────
required_vars=(
    "MOODLE_DB_HOST"
    "MOODLE_DB_NAME"
    "MOODLE_DB_USER"
    "MOODLE_DB_PASSWORD"
    "MOODLE_WWWROOT"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Required environment variable $var is not set."
        exit 1
    fi
done

# ── Wait for database to be ready ─────────────
echo "Waiting for database at $MOODLE_DB_HOST..."
until mysql -h "$MOODLE_DB_HOST" -u "$MOODLE_DB_USER" -p"$MOODLE_DB_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; do
    echo "  Database not ready yet — retrying in 3 seconds..."
    sleep 3
done
echo "Database is ready!"

# ── Generate Moodle config.php if not exists ──
CONFIG_FILE="/var/www/html/config.php"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Generating config.php..."
    cat > "$CONFIG_FILE" << EOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

// ── Database ──────────────────────────────
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
);

// ── Site URL ──────────────────────────────
\$CFG->wwwroot   = '${MOODLE_WWWROOT}';
\$CFG->dataroot  = '/var/moodledata';
\$CFG->admin     = 'admin';

// ── Security & Performance ────────────────
\$CFG->directorypermissions = 02777;
\$CFG->pathtophp = '/usr/local/bin/php';

// ── SMTP Mail (set via environment) ──────
if (!empty('${MOODLE_SMTP_HOST}')) {
    \$CFG->smtphosts   = '${MOODLE_SMTP_HOST}';
    \$CFG->smtpport    = '${MOODLE_SMTP_PORT:-587}';
    \$CFG->smtpuser    = '${MOODLE_SMTP_USER}';
    \$CFG->smtppass    = '${MOODLE_SMTP_PASSWORD}';
    \$CFG->smtpsecure  = '${MOODLE_SMTP_SECURE:-tls}';
    \$CFG->noreplyaddress = '${MOODLE_NOREPLY_EMAIL:-noreply@example.com}';
}

// ── Session handling ──────────────────────
\$CFG->session_handler_class = '\core\session\database';
\$CFG->session_database_acquire_lock_timeout = 120;

require_once(__DIR__ . '/lib/setup.php');
EOF
    chown www-data:www-data "$CONFIG_FILE"
    chmod 640 "$CONFIG_FILE"
    echo "config.php created."
else
    echo "config.php already exists — skipping generation."
fi

# ── Run Moodle install if not yet installed ───
if ! mysql -h "$MOODLE_DB_HOST" -u "$MOODLE_DB_USER" -p"$MOODLE_DB_PASSWORD" "$MOODLE_DB_NAME" \
    -e "SELECT COUNT(*) FROM mdl_user;" > /dev/null 2>&1; then

    echo "Running Moodle first-time installation..."
    php /var/www/html/admin/cli/install_database.php \
        --agree-license \
        --fullname="${MOODLE_SITE_FULLNAME:-My Moodle Site}" \
        --shortname="${MOODLE_SITE_SHORTNAME:-moodle}" \
        --summary="${MOODLE_SITE_SUMMARY:-Welcome to Moodle}" \
        --adminuser="${MOODLE_ADMIN_USER:-admin}" \
        --adminpass="${MOODLE_ADMIN_PASSWORD:-Admin1234!}" \
        --adminemail="${MOODLE_ADMIN_EMAIL:-admin@example.com}"
    echo "Moodle installation complete!"

else
    echo "Moodle already installed — checking for upgrades..."
    php /var/www/html/admin/cli/upgrade.php --non-interactive || true
    echo "Upgrade check complete."
fi

# ── Fix permissions on moodledata ─────────────
chown -R www-data:www-data /var/moodledata
chmod -R 770 /var/moodledata

# ── Start cron in background ──────────────────
echo "Starting cron..."
cron

# ── Start Apache ──────────────────────────────
echo "──────────────────────────────────────"
echo " Moodle is ready! Starting Apache..."
echo "──────────────────────────────────────"
exec apache2-foreground