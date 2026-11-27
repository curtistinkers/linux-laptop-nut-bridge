#!/bin/bash
set -euo pipefail

DEBUG=false

# LOW_BATTERY_THRESHOLD=20                # Default: 20
# DEVICE_TYPE='ups'                       # Default: 'ups'
# DEVICE_DESCRIPTION='Internal battery'   # Default: 'Internal battery'
# DEVICE_CONTACT=''                       # Default: ''
# DEVICE_LOCATION=''                      # Default: ''
# DEVICE_PART=''                          # Default: ''
# BATTERY_DATE=''                         # Default: ''
# BATTERY_DATE_MAINTENANCE=''             # Default: ''
# BATTERY_MFR_DATE=''                     # Default: ''

CONFIG_FILE="/etc/linux-laptop-nut-bridge/config.ini"

if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
fi

BAT_DIR=$(find /sys/class/power_supply/ -maxdepth 1 -name "BAT*" -o -name "BATT*" | head -n 1)
AC_DIR=$(find /sys/class/power_supply/ -maxdepth 1 -name "AC*" -o -name "ADP*" -o -name "ACAD*" | head -n 1)

RUN_DIR="/run/linux-laptop-nut-bridge"
STATUS_FILE="${RUN_DIR}/internal_battery_status"

if [[ "${DEBUG}" != "true" ]]; then
    touch "${STATUS_FILE}"
fi

# HELPER FUNCTIONS

convert_microvolts_to_volts() {
    local microvolts=$1
    if [[ ${microvolts} -gt 0 ]]; then
        awk "BEGIN {printf \"%.1f\", ${microvolts} / 1000000}"
        return 0
    fi
    echo "nan"
    return 1
}

convert_energy_to_amps() {
    local energy="${1}"
    local voltage="${2}"
    if [[ "${energy}" -gt 0 && "${voltage}" -gt 0 ]]; then
        awk "BEGIN { printf \"%.3f\", ${energy} / ${voltage} }"
        return 0
    fi
    echo "nan"
    return 1
}

convert_microamps_to_amps() {
    local microamps="${1}"
    if [[ "${microamps}" -gt 1000000 ]]; then
        awk "BEGIN { printf \"%.3f\", ${microamps} / 1000000 }"
        return 0
    fi
    echo "nan"
    return 1
}

is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

is_between_1_and_100() {
    [[ $1 =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 100 ))
}

# 2. Cache permanent hardware metadata variables right at startup
MFR=$(cat "${BAT_DIR}/manufacturer" 2>/dev/null || echo "Generic")
MODEL=$(cat "${BAT_DIR}/model_name" 2>/dev/null || echo "Internal Battery")

# get_device_model() {}

# get_device_mfr() {}

get_device_serial() {
    if [[ -f "${BAT_DIR}/serial_number" ]]; then
        xargs < "${BAT_DIR}/serial_number" 2>/dev/null || echo ""
        return 0
    fi
    echo ""
}

get_device_type() {
    if [[ -v DEVICE_TYPE ]]; then
        echo "${DEVICE_TYPE}"
    else
        echo "ups"
    fi
}

get_device_description() {
    if [[ -v DEVICE_DESCRIPTION ]]; then
        echo "${DEVICE_DESCRIPTION}"
    else
        echo "Internal battery"
    fi
}

get_device_contact() {
    if [[ -v DEVICE_CONTACT ]]; then
        echo "${DEVICE_CONTACT}"
    fi
}

get_device_location() {
    if [[ -v DEVICE_LOCATION ]]; then
        echo "${DEVICE_LOCATION}"
    fi
}

get_device_part() {
    if [[ -v DEVICE_PART ]]; then
        echo "${DEVICE_PART}"
    fi
}

get_device_uptime() {
    awk '{print int($1)}' /proc/uptime
}

# Battery chemistry
get_battery_type() {
    if [[ -f "${BAT_DIR}/technology" ]]; then
        cat "${BAT_DIR}/technology" 2>/dev/null || echo "Unknown"
        return 0
    fi
    echo "Unknown"
}

# Battery charge level (in percent)
get_battery_charge() {
    if [[ -f "${BAT_DIR}/capacity" ]]; then
        cat "${BAT_DIR}/capacity" 2>/dev/null || echo "nan"
        return 0
    fi
    echo "nan"
}

get_low_battery_threshold() {
    if [[ -v LOW_BATTERY_THRESHOLD ]] && is_between_1_and_100 "${LOW_BATTERY_THRESHOLD}"; then
        echo "${LOW_BATTERY_THRESHOLD}"
    else
        echo 20
    fi
}

# Battery health percentage (full / design)
calculate_battery_health() {
    local battery_full="0"
    local battery_design="0"

    if [[ -f "${BAT_DIR}/charge_full" && -f "${BAT_DIR}/charge_full_design" ]]; then
        battery_full=$(cat "${BAT_DIR}/charge_full" 2>/dev/null || echo "0")
        battery_design=$(cat "${BAT_DIR}/charge_full_design" 2>/dev/null || echo "0")
    elif [[ -f "${BAT_DIR}/energy_full" &&  -f "${BAT_DIR}/energy_full_design" ]]; then
        battery_full=$(cat "${BAT_DIR}/energy_full" 2>/dev/null || echo "0")
        battery_design=$(cat "${BAT_DIR}/energy_full_design" 2>/dev/null || echo "0")
    fi

    if [[ "${battery_full}" -gt 0 && "${battery_design}" -gt 0 ]]; then
        awk "BEGIN {printf \"%.0f\", (${battery_full} / ${battery_design}) * 100}"
        return 0
    fi
    echo "nan"
}

get_battery_cycle_count() {
    local cycle_count="0"

    if [[ -f "${BAT_DIR}/cycle_count" ]]; then
        cycle_count=$(cat "${BAT_DIR}/cycle_count" 2>/dev/null || echo "0")
    fi

    if [[ "${cycle_count}" -gt 0 ]]; then
        echo "${cycle_count}"
        return 0
    fi

    echo "nan"
}

get_battery_voltage() {
    local microvolts
    if [[ -f "${BAT_DIR}/voltage_now" ]]; then
        microvolts=$(cat "${BAT_DIR}/voltage_now" 2>/dev/null || echo "0")
        convert_microvolts_to_volts "${microvolts}"
        return 0
    fi
    echo "nan"
    return 1
}

get_battery_voltage_nominal() {
    local microvolts
    if [[ -f "${BAT_DIR}/voltage_min_design" ]]; then
        microvolts=$(cat "${BAT_DIR}/voltage_min_design" 2>/dev/null || echo "0")
        convert_microvolts_to_volts "${microvolts}"
        return 0
    fi
    echo "nan"
    return 1
}

# Battery capacity remaining in Amp-hours
get_battery_capacity() {
    local microamps voltage energy

    if [[ -f "${BAT_DIR}/charge_now" ]]; then
        microamps=$(cat "${BAT_DIR}/charge_now" 2>/dev/null || echo "0")
        convert_microamps_to_amps "${microamps}"
        return 0
    elif [[ -f "${BAT_DIR}/energy_now" && -f "${BAT_DIR}/voltage_now" ]]; then
        voltage=$(cat "${BAT_DIR}/voltage_now" 2>/dev/null || echo "0")
        energy=$(cat "${BAT_DIR}/energy_now" 2>/dev/null || echo "0")
        convert_energy_to_amps "${energy}" "${voltage}"
        return 0
    fi

    echo "nan"
    return 1
}

# Battery capacity when fully-charged in Amp-hours
get_battery_capacity_full() {
    local microamps voltage energy

    if [[ -f "${BAT_DIR}/charge_full" ]]; then
        microamps=$(cat "${BAT_DIR}/charge_full" 2>/dev/null || echo "0")
        convert_microamps_to_amps "${microamps}"
        return 0
    elif [[ -f "${BAT_DIR}/energy_full" && -f "${BAT_DIR}/voltage_min_design" ]]; then
        voltage=$(cat "${BAT_DIR}/voltage_min_design" 2>/dev/null || echo "0")
        energy=$(cat "${BAT_DIR}/energy_full" 2>/dev/null || echo "0")
        convert_energy_to_amps "${energy}" "${voltage}"
        return 0
    fi

    echo "nan"
    return 1
}

# Battery capacity when new in Amp-hours
get_battery_capacity_nominal() {
    local microamps voltage energy

    if [[ -f "${BAT_DIR}/charge_full_design" ]]; then
        microamps=$(cat "${BAT_DIR}/charge_full_design" 2>/dev/null || echo "0")
        convert_microamps_to_amps "${microamps}"
        return 0
    elif [[ -f "${BAT_DIR}/energy_full_design" && -f "${BAT_DIR}/voltage_min_design" ]]; then
        voltage=$(cat "${BAT_DIR}/voltage_min_design" 2>/dev/null || echo "0")
        energy=$(cat "${BAT_DIR}/energy_full_design" 2>/dev/null || echo "0")
        convert_energy_to_amps "${energy}" "${voltage}"
        return 0
    fi

    echo "nan"
    return 1
}

get_ups_status() {
    # OL = Online (mains present)
    # OB = On battery
    # LB = Low battery
    # RB = Replace battery
    local line_status health_pct ac_online battery_charge_pct low_battery_threshold

    if [[ -f "${AC_DIR}/online" ]]; then
        ac_online=$(cat "${AC_DIR}/online" 2>/dev/null)
        if [[ "${ac_online}" -eq 1 ]]; then
            line_status=OL
        elif [[ "${ac_online}" -eq 0 ]]; then
            line_status=OB
        else
            echo "ERROR"
            return 0
        fi
    else
        echo "ERROR"
        return 0
    fi

    battery_charge_pct=$(get_battery_charge)
    low_battery_threshold=$(get_low_battery_threshold)
    if [[ -n "${battery_charge_pct}" && "${battery_charge_pct}" != "nan" ]] && awk "BEGIN { exit !(${battery_charge_pct} < ${low_battery_threshold}) }"; then
        line_status="${line_status} LB"
    fi

    health_pct=$(calculate_battery_health)
    if [[ -n "${health_pct}" && "${health_pct}" != "nan" ]] && awk "BEGIN { exit !(${health_pct} < 60) }"; then
        line_status="${line_status} RB"
    fi

    echo "${line_status}"
}

get_battery_charger_status() {
    local status
    if [[ -f "${BAT_DIR}/status" ]]; then
        status=$(cat "${BAT_DIR}/status")
    else
        echo "unavailable"
        return 0
    fi

    if [[ "${status}" == "Full" || "${status}" == "Not charging" ]]; then
        echo "resting"
        return 0
    elif [[ "${status}" == "Charging" ]]; then
        echo "charging"
        return 0
    elif [[ "${status}" == "Discharging" ]]; then
        echo "discharging"
        return 0
    fi

    echo "${status}"
}

get_battery_current() {
    local microamps microvolts microwatts

    if [[ -f "${BAT_DIR}/current_now" ]]; then

        microamps=$(cat "${BAT_DIR}/current_now" 2>/dev/null || echo "0")

        if [[ "${microamps}" -gt 0 ]]; then
            awk "BEGIN { printf \"%.3f\", ${microamps} / 1000000 }"
            return 0
        fi

    elif [[ -f "${BAT_DIR}/power_now" ]]; then

        microwatts=$(cat "${BAT_DIR}/power_now" 2>/dev/null || echo "0")

        if [[ -f "${BAT_DIR}/voltage_now" ]]; then
            microvolts=$(cat "${BAT_DIR}/voltage_now" 2>/dev/null || echo "0")
        elif [[ -f "${BAT_DIR}/voltage_min_design" ]]; then
            microvolts=$(cat "${BAT_DIR}/voltage_min_design" 2>/dev/null || echo "0")
        else
            microvolts="0"
        fi

        if [[ "${microvolts}" -gt 0 && "${microwatts}" -gt 0 ]]; then
            awk "BEGIN { printf \"%.3f\", ${microwatts} / ${microvolts} }"
            return 0
        fi

    fi

    echo 'nan'
}

update_nut_status() {
    # NUT device variables
    local device_model device_mfr device_serial device_type device_description
    local device_contact device_location device_part device_uptime

    device_model="${MODEL}"
    device_mfr="${MFR}"
    device_serial=$(get_device_serial)
    device_type=$(get_device_type)
    device_description=$(get_device_description)
    device_contact=$(get_device_contact)
    device_location=$(get_device_location)
    device_part=$(get_device_part)
    device_uptime=$(get_device_uptime)

    # Standard NUT UPS variables
    local ups_status ups_date ups_time ups_mode

    ups_status=$(get_ups_status)
    ups_date=$(date -u +%F)
    ups_time=$(date -u +%T)
    ups_mode="line-interactive"

    # Standard NUT battery variables
    local battery_charge battery_charge_low
    local battery_charger_status
    local battery_voltage battery_voltage_nominal
    local battery_capacity battery_capacity_nominal
    local battery_current
    local battery_type

    battery_charge=$(get_battery_charge)
    battery_charge_low=$(get_low_battery_threshold)
    battery_charger_status=$(get_battery_charger_status)
    battery_voltage=$(get_battery_voltage)
    battery_voltage_nominal=$(get_battery_voltage_nominal)
    battery_capacity=$(get_battery_capacity)
    battery_capacity_nominal=$(get_battery_capacity_nominal)
    battery_current=$(get_battery_current)
    battery_type=$(get_battery_type)

    # Non-standard battery variables
    local battery_capacity_full battery_cycles battery_health

    battery_capacity_full=$(get_battery_capacity_full)
    battery_cycles=$(get_battery_cycle_count)
    battery_health=$(calculate_battery_health)

    OUTPUT=$(
        # NUT device variables
        printf 'device.model: %s\n' "${device_model}"
        printf 'device.mfr: %s\n' "${device_mfr}"
        if [[ "${device_serial}" != '' ]]; then printf 'device.serial: %s\n' "${device_serial}"; fi
        if [[ "${device_type}" != '' ]]; then printf 'device.type: %s\n' "${device_type}"; fi
        if [[ "${device_description}" != '' ]]; then printf 'device.description: %s\n' "${device_description}"; fi
        if [[ "${device_contact}" != '' ]]; then printf 'device.contact: %s\n' "${device_contact}"; fi
        if [[ "${device_location}" != '' ]]; then printf 'device.location: %s\n' "${device_location}"; fi
        if [[ "${device_part}" != '' ]]; then printf 'device.part: %s\n' "${device_part}"; fi
        printf 'device.uptime: %u\n' "${device_uptime}"

        # Standard NUT UPS variables
        printf 'ups.model: %s\n' "${device_model}"
        printf 'ups.mfr: %s\n' "${device_mfr}"
        if [[ "${device_serial}" != '' ]]; then printf 'ups.serial: %s\n' "${device_serial}"; fi
        printf 'ups.status: %s\n' "${ups_status}"
        printf 'ups.date: %s\n' "${ups_date}"
        printf 'ups.time: %s\n' "${ups_time}"
        printf 'ups.mode: %s\n' "${ups_mode}"

        # Standard NUT battery variables
        if [[ "${battery_charge}" != 'nan' ]]; then printf 'battery.charge: %u\n' "${battery_charge}"; fi
        printf 'battery.charge.low: %u\n' "${battery_charge_low}"
        printf 'battery.charger.status: %s\n' "${battery_charger_status}"
        if [[ "${battery_voltage}" != "nan" ]]; then printf 'battery.voltage: %.1f\n' "${battery_voltage}"; fi
        if [[ "${battery_voltage_nominal}" != "nan" ]]; then printf 'battery.voltage.nominal: %.1f\n' "${battery_voltage_nominal}"; fi
        if [[ "${battery_capacity}" != "nan" ]]; then printf 'battery.capacity: %.3f\n' "${battery_capacity}"; fi
        if [[ "${battery_capacity_nominal}" != "nan" ]]; then printf 'battery.capacity.nominal: %.3f\n' "${battery_capacity_nominal}"; fi
        if [[ "${battery_current}" != "nan" ]]; then printf 'battery.current: %.2f\n' "${battery_current}"; fi
        printf 'battery.type: %s\n' "${battery_type}"

        # Non-standard battery variables
        if [[ "${battery_capacity_full}" != "nan" ]]; then printf 'battery.capacity.full: %.3f\n' "${battery_capacity_full}"; fi
        if [[ "${battery_cycles}" != "nan" ]]; then printf 'battery.cycles: %u\n' "${battery_cycles}"; fi
        if [[ "${battery_health}" != "nan" ]]; then printf 'battery.health: %u%%\n' "${battery_health}"; fi
    )

    if [[ "${DEBUG}" != "true" ]]; then
        echo "${OUTPUT}" > "${STATUS_FILE}.tmp"
        mv "${STATUS_FILE}.tmp" "${STATUS_FILE}"
    else
        echo "${OUTPUT}"
    fi
}

echo "Starting Laptop Battery to NUT Sync Handler"

update_nut_status
