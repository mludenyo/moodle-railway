#!/bin/bash
# Moodle cron runner — called by system cron every minute
/usr/local/bin/php /var/www/html/admin/cron.php >> /var/log/moodlecron.log 2>&1