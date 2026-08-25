#!/bin/bash
set -euo pipefail

: "${TKL_TEST_RESULT:?TKL_TEST_RESULT must name the result file}"
: "${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS must contain the firstboot Observium password}"

APP_ROOT=/opt/observium
SOURCE_FILE=/usr/local/share/turnkey-observium/source
BASE_URL=https://127.0.0.1
FIXTURE_HOST=127.0.0.1
FIXTURE_PORT=1161
FIXTURE_COMMUNITY=turnkey-v19

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

require_contains() {
    local text=$1 expected=$2 context=$3
    [[ $text == *"$expected"* ]] || fail "$context did not contain: $expected"
}

source_value() {
    local key=$1
    sed -n "s/^${key}=//p" "$SOURCE_FILE" | head -n 1
}

[[ -r $SOURCE_FILE ]] || fail "Observium source provenance is missing"
[[ -x /usr/local/bin/turnkey-update-observium ]] \
    || fail "Observium updater is not executable"

version=$(source_value VERSION)
revision=$(source_value REVISION)
archive_sha256=$(source_value ARCHIVE_SHA256)
channel=$(source_value CHANNEL)

[[ $version = 26.1.14545 ]] || fail "unexpected Observium version"
[[ $revision = 14545 ]] || fail "unexpected Observium revision"
[[ $archive_sha256 = 01f4bec0bb01c49afe07e26f2b3f79d4eeeabf412ce5f15193df4ed7fc77d715 ]] \
    || fail "unexpected Observium archive digest"
[[ $channel = ce ]] || fail "unexpected Observium update channel"

runtime_version=$(php -r '
    require $argv[1];
    echo OBSERVIUM_EDITION . "|" . OBSERVIUM_TRAIN . "|" .
         OBSERVIUM_VERSION . "|" . OBSERVIUM_REV;
' "$APP_ROOT/includes/definitions/version.inc.php")
[[ $runtime_version = "community|ce|$version|$revision" ]] \
    || fail "runtime identity differs from source provenance"

[[ $(stat -c '%U:%G:%a' "$APP_ROOT/config.php") = root:www-data:440 ]] \
    || fail "Observium configuration permissions are incorrect"
systemctl is-active --quiet apache2 || fail "Apache is not active"
systemctl is-active --quiet mariadb || fail "MariaDB is not active"
systemctl is-active --quiet cron || fail "cron is not active"
apache2ctl configtest 2>&1 | grep -q 'Syntax OK' \
    || fail "Apache configuration is invalid"

login_page=$(curl --insecure -fsSL --max-time 30 "$BASE_URL/")
require_contains "$login_page" "Please log in" "Observium HTTPS login page"
adminer_page=$(curl --insecure -fsSL --max-time 30 https://127.0.0.1:12322/)
require_contains "$adminer_page" "Adminer" "Adminer HTTPS endpoint"

temporary=$(mktemp -d)
cookie=$temporary/cookie
pass_file=$temporary/password
snmp_conf=$temporary/snmpd.conf
snmp_pid_file=$temporary/snmpd.pid
snmp_log=$temporary/snmpd.log
snmp_process=
device_added=0

cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM
    if [ "$device_added" -eq 1 ]; then
        "$APP_ROOT/delete_device.php" "$FIXTURE_HOST" rrd >/dev/null 2>&1 || true
    fi
    if [ -n "$snmp_process" ]; then
        kill "$snmp_process" >/dev/null 2>&1 || true
        wait "$snmp_process" >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary"
    exit "$status"
}
trap cleanup EXIT HUP INT TERM

chmod 0700 "$temporary"
touch "$cookie" "$pass_file"
chmod 0600 "$cookie" "$pass_file"
printf '%s' "$TKL_TEST_APP_PASS" > "$pass_file"
curl_args=(--insecure -fsS --max-time 30 -c "$cookie" -b "$cookie")

curl "${curl_args[@]}" "$BASE_URL/" -o /dev/null
curl "${curl_args[@]}" -L "$BASE_URL/" \
    -H "Referer: $BASE_URL/" \
    --data-urlencode 'username=admin' \
    --data-urlencode "password@$pass_file" \
    -o /dev/null
dashboard=$(curl "${curl_args[@]}" "$BASE_URL/")
require_contains "$dashboard" "Logout" "authenticated Observium dashboard"
require_contains "$dashboard" "Dashboard" "authenticated Observium dashboard"

cat > "$snmp_conf" <<EOF
agentaddress udp:127.0.0.1:$FIXTURE_PORT
rocommunity $FIXTURE_COMMUNITY 127.0.0.1
sysLocation TurnKey v19 acceptance
sysContact admin@example.invalid
sysName observium-v19-fixture
EOF

snmpd -f -Lo -C -c "$snmp_conf" -p "$snmp_pid_file" \
    > "$snmp_log" 2>&1 &
snmp_process=$!
for _ in $(seq 1 20); do
    if snmpget -v2c -c "$FIXTURE_COMMUNITY" -On \
            "$FIXTURE_HOST:$FIXTURE_PORT" 1.3.6.1.2.1.1.5.0 \
            >/dev/null 2>&1; then
        break
    fi
    kill -0 "$snmp_process" >/dev/null 2>&1 \
        || fail "local SNMP fixture exited: $(tail -n 5 "$snmp_log")"
    sleep 1
done
snmp_name=$(snmpget -v2c -c "$FIXTURE_COMMUNITY" -Oqv \
    "$FIXTURE_HOST:$FIXTURE_PORT" 1.3.6.1.2.1.1.5.0)
[[ $snmp_name = observium-v19-fixture ]] \
    || fail "local SNMP fixture returned an unexpected sysName"

add_output=$("$APP_ROOT/add_device.php" -p "$FIXTURE_HOST" \
    "$FIXTURE_COMMUNITY" v2c "$FIXTURE_PORT" udp)
require_contains "$add_output" "Added device $FIXTURE_HOST" "Observium device add"
device_added=1

discovery_output=$("$APP_ROOT/discovery.php" -h "$FIXTURE_HOST")
require_contains "$discovery_output" "$FIXTURE_HOST" "Observium discovery"
poller_output=$("$APP_ROOT/poller.php" -h "$FIXTURE_HOST")
require_contains "$poller_output" "$FIXTURE_HOST" "Observium poller"

db_device=$(mysql --batch --skip-column-names observium --execute="
    SELECT CONCAT(hostname, '|', snmpver, '|', port, '|',
                  last_discovered IS NOT NULL, '|', last_polled IS NOT NULL)
    FROM devices WHERE hostname='$FIXTURE_HOST';")
[[ $db_device = "$FIXTURE_HOST|v2c|$FIXTURE_PORT|1|1" ]] \
    || fail "MariaDB did not retain the discovered and polled SNMP fixture"

grep -Eq '^33[[:space:]]+\*/6.*discovery\.php -h all' /etc/cron.d/observium \
    || fail "full discovery cron entry is missing"
grep -Eq 'poller-wrapper\.py 1' /etc/cron.d/observium \
    || fail "poller cron entry is missing"
grep -Eq 'housekeeping\.php -sel' /etc/cron.d/observium \
    || fail "housekeeping cron entry is missing"

source_before=$(sha256sum "$SOURCE_FILE" | awk '{print $1}')
check_output=$(turnkey-update-observium --check)
require_contains "$check_output" "installed_version=$version" "Observium updater check"
require_contains "$check_output" "eligible_channel=ce" "Observium updater check"
require_contains "$check_output" "candidate=official-community-latest" "Observium updater check"
require_contains "$check_output" "integrity=https-official-metadata-and-internal-community-identity" \
    "Observium updater check"
updater_status=$(awk -F= '$1 == "status" {print $2}' <<< "$check_output")
[[ $updater_status = current || $updater_status = update-available ]] \
    || fail "Observium updater returned an invalid status"

dry_run_output=$(turnkey-update-observium --apply --dry-run)
require_contains "$dry_run_output" "installed_version=$version" "Observium updater dry run"
require_contains "$dry_run_output" "eligible_channel=ce" "Observium updater dry run"
source_after=$(sha256sum "$SOURCE_FILE" | awk '{print $1}')
[[ $source_after = "$source_before" ]] \
    || fail "Observium updater check or dry run changed source provenance"

echo "PASS: Observium login, local SNMP discovery/polling, MariaDB, cron and updater"
echo "version=$version revision=$revision updater_status=$updater_status"
cat > "$TKL_TEST_RESULT" <<EOF
package_source=official Observium Community Edition archive
installed_version=Observium CE $version revision $revision
runtime_checks=HTTPS firstboot admin login, local SNMP device add discovery poll, MariaDB, cron and Adminer passed
updater_command=turnkey-update-observium --check; turnkey-update-observium --apply --dry-run
updater_result=official CE archive metadata returned $updater_status without changing installed provenance
updater_channel=official Observium Community Edition archive
integrity_evidence=build archive SHA256 $archive_sha256 plus HTTPS metadata and internal CE identity validation
EOF
