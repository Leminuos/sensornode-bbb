#!/bin/sh

set -u

FW_SETENV="/usr/bin/fw_setenv"
FW_PRINTENV="/usr/bin/fw_printenv"

HEALTH_TIMEOUT_SEC=120
HEALTH_POLL_SEC=5

UI_UNIT="sensornode-ui.service"
TELEMETRY_UNIT="sensornode-telemetryd.service"
OTA_UNIT="sensornode-otad.service"
STABLE_SEC=30

DATA_DIR="/data"

reason=""

log() {
    echo "OTA: $*"
}

uptime_sec() {
    cut -d. -f1 /proc/uptime
}

check_unit() {
    unit="$1"

    state=$(systemctl is-active "${unit}")
    if [ "${state}" != "active" ]; then
        reason="${unit} is ${state}"
        return 1
    fi

    enter_usec=$(systemctl show -p ActiveEnterTimestampMonotonic --value "${unit}")
    active_sec=$(( $(uptime_sec) - enter_usec / 1000000 ))
    if [ "${active_sec}" -lt "${STABLE_SEC}" ]; then
        reason="${unit} active for ${active_sec}s < ${STABLE_SEC}s"
        return 1
    fi
}

check_ui() {
    load_state=$(systemctl show -p LoadState --value "${UI_UNIT}")
    [ "${load_state}" = "loaded" ] || return 0

    check_unit "${UI_UNIT}"
}

# telemetryd giữ bus I2C và DB, script chỉ đọc kết quả qua STATUS= của daemon.
check_telemetry() {
    check_unit "${TELEMETRY_UNIT}" || return 1

    status=$(systemctl show -p StatusText --value "${TELEMETRY_UNIT}")
    case "${status}" in
        *sensors=ok*) ;;
        *)
            reason="${TELEMETRY_UNIT} sensors not ok: ${status}"
            return 1
            ;;
    esac
    case "${status}" in
        *db=ok*) ;;
        *)
            reason="${TELEMETRY_UNIT} database not ok: ${status}"
            return 1
            ;;
    esac
}

check_ota() {
    check_unit "${OTA_UNIT}"
}

check_data() {
    if ! mountpoint -q "${DATA_DIR}"; then
        reason="${DATA_DIR} is not mounted"
        return 1
    fi

    probe="${DATA_DIR}/.ota-health-probe"
    if ! { echo ok > "${probe}" && rm -f "${probe}"; } 2>/dev/null; then
        reason="${DATA_DIR} is not writable"
        return 1
    fi
}

check_health() {
    check_data && check_telemetry && check_ota && check_ui
}

ustate=$("${FW_PRINTENV}" -n ustate 2>/dev/null || echo "0")
[ "${ustate}" = "1" ] || exit 0

slot=$("${FW_PRINTENV}" -n active_slot 2>/dev/null || echo "?")
log "Trial boot of slot ${slot}, health check for up to ${HEALTH_TIMEOUT_SEC}s"

deadline=$(( $(uptime_sec) + HEALTH_TIMEOUT_SEC ))
while :; do
    if check_health; then
        if "${FW_SETENV}" boot_count "0" && "${FW_SETENV}" ustate "0"; then
            log "Health check passed, slot ${slot} committed"
            exit 0
        fi
        log "Health check passed but committing slot ${slot} failed"
        exit 1
    fi

    [ "$(uptime_sec)" -lt "${deadline}" ] || break
    log "Waiting: ${reason}"
    sleep "${HEALTH_POLL_SEC}"
done

log "Health check failed: ${reason}. Slot ${slot} not committed, rebooting"
systemctl --no-block reboot
exit 1
