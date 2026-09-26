#!/bin/sh

set -u

FW_SETENV="/usr/bin/fw_setenv"
FW_PRINTENV="/usr/bin/fw_printenv"

HEALTH_TIMEOUT_SEC=120
HEALTH_POLL_SEC=5

UI_UNIT="sensornode-ui.service"
UI_STABLE_SEC=30

I2C_BUS=1
SHT30_ADDR=0x44
BH1750_ADDR=0x23

DATA_DIR="/data"

reason=""

log() {
    echo "OTA: $*"
}

uptime_sec() {
    cut -d. -f1 /proc/uptime
}

sht3x_crc8() {
    crc=255
    for byte in "$@"; do
        crc=$(( crc ^ byte ))
        bit=0
        while [ "${bit}" -lt 8 ]; do
            if [ $(( crc & 128 )) -ne 0 ]; then
                crc=$(( ((crc << 1) ^ 49) & 255 ))
            else
                crc=$(( (crc << 1) & 255 ))
            fi
            bit=$(( bit + 1 ))
        done
    done
    echo "${crc}"
}

check_ui() {
    load_state=$(systemctl show -p LoadState --value "${UI_UNIT}")
    [ "${load_state}" = "loaded" ] || return 0

    state=$(systemctl is-active "${UI_UNIT}")
    if [ "${state}" != "active" ]; then
        reason="${UI_UNIT} is ${state}"
        return 1
    fi

    enter_usec=$(systemctl show -p ActiveEnterTimestampMonotonic --value "${UI_UNIT}")
    active_sec=$(( $(uptime_sec) - enter_usec / 1000000 ))
    if [ "${active_sec}" -lt "${UI_STABLE_SEC}" ]; then
        reason="${UI_UNIT} active for ${active_sec}s < ${UI_STABLE_SEC}s"
        return 1
    fi
}

check_sht30() {
    if ! i2ctransfer -y "${I2C_BUS}" w2@"${SHT30_ADDR}" 0x24 0x00 >/dev/null 2>&1; then
        reason="SHT30 (${SHT30_ADDR}) does not ACK the measure command"
        return 1
    fi
    usleep 50000

    data=$(i2ctransfer -y "${I2C_BUS}" r6@"${SHT30_ADDR}" 2>/dev/null) || data=""
    set -- ${data}
    if [ $# -ne 6 ]; then
        reason="SHT30 (${SHT30_ADDR}) read failed"
        return 1
    fi

    if [ "$(sht3x_crc8 "$1" "$2")" -ne $(( $3 )) ] || \
       [ "$(sht3x_crc8 "$4" "$5")" -ne $(( $6 )) ]; then
        reason="SHT30 (${SHT30_ADDR}) CRC mismatch: ${data}"
        return 1
    fi
}

check_bh1750() {
    if ! i2ctransfer -y "${I2C_BUS}" w1@"${BH1750_ADDR}" 0x20 >/dev/null 2>&1; then
        reason="BH1750 (${BH1750_ADDR}) does not ACK the measure command"
        return 1
    fi
    usleep 180000

    data=$(i2ctransfer -y "${I2C_BUS}" r2@"${BH1750_ADDR}" 2>/dev/null) || data=""
    set -- ${data}
    if [ $# -ne 2 ]; then
        reason="BH1750 (${BH1750_ADDR}) read failed"
        return 1
    fi
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
    check_data && check_ui && check_sht30 && check_bh1750
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
