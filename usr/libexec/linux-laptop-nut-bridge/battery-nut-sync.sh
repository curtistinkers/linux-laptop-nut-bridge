#!/bin/sh

# Dynamically locate whichever battery and AC folder exists on the host machine
BAT_DIR=$(find /sys/class/power_supply/ -maxdepth 1 -name "BAT*" -o -name "BATT*" | head -n 1)
AC_DIR=$(find /sys/class/power_supply/ -maxdepth 1 -name "AC*" -o -name "ADP*" -o -name "ACAD*" | head -n 1)

RUN_DIR="/run/linux-laptop-nut-bridge"
STATUS_FILE="$RUN_DIR/internal_battery_sync.status"

# 1. Instantly generate a placeholder so the NUT daemon never encounters a missing file
touch "$STATUS_FILE"

# 2. Cache permanent hardware metadata variables right at startup
MFR=$(cat "$BAT_DIR/manufacturer" 2>/dev/null | xargs || echo "Generic")
MODEL=$(cat "$BAT_DIR/model_name" 2>/dev/null | xargs || echo "Battery")
SERIAL=$(cat "$BAT_DIR/serial_number" 2>/dev/null | xargs || echo "Unknown")
TECH=$(cat "$BAT_DIR/technology" 2>/dev/null | xargs || echo "Unknown")

echo "Initializing Universal Battery-to-NUT Sync Handler. Serial: $SERIAL"

update_nut_status() {
    # Core States
    LINE_STATUS=$(cat "$AC_DIR/online" 2>/dev/null || echo "1")
    CHARGE_PCT=$(cat "$BAT_DIR/capacity" 2>/dev/null || echo "100")
    BAT_STATUS=$(cat "$BAT_DIR/status" 2>/dev/null || echo "Unknown")

    # Raw Maths Telemetry Values
    V_RAW=$(cat "$BAT_DIR/voltage_now" 2>/dev/null || echo "0")
    V_NOM_RAW=$(cat "$BAT_DIR/voltage_min_design" 2>/dev/null || echo "0")
    I_RAW=$(cat "$BAT_DIR/current_now" 2>/dev/null || echo "0")
    CYCLES=$(cat "$BAT_DIR/cycle_count" 2>/dev/null || echo "0")

    # Charge Energy Blocks
    C_NOW=$(cat "$BAT_DIR/charge_now" 2>/dev/null || echo "0")
    C_FULL=$(cat "$BAT_DIR/charge_full" 2>/dev/null || echo "0")
    C_DESIGN=$(cat "$BAT_DIR/charge_full_design" 2>/dev/null || echo "0")

    # Charge Threshold Settings
    TH_START=$(cat "$BAT_DIR/charge_control_start_threshold" 2>/dev/null || echo "0")
    TH_END=$(cat "$BAT_DIR/charge_control_end_threshold" 2>/dev/null || echo "100")

    # Standard Unit Processing (Micro-units to base Floats via awk)
    VOLT=$(awk "BEGIN {print $V_RAW / 1000000}")
    VOLT_NOM=$(awk "BEGIN {print $V_NOM_RAW / 1000000}")
    CURRENT=$(awk "BEGIN {print $I_RAW / 1000000}")

    # Scale charge microampere-hours (uAh) to standard Ampere-hours (Ah)
    AMP_NOW=$(awk "BEGIN {print $C_NOW / 1000000}")
    AMP_FULL=$(awk "BEGIN {print $C_FULL / 1000000}")
    AMP_DESIGN=$(awk "BEGIN {print $C_DESIGN / 1000000}")

    # Calculate Battery Health percentage based on wear drop (Full / Design)
    if [ "$C_DESIGN" -gt 0 ]; then
        HEALTH=$(awk "BEGIN {printf \"%.1f\", ($C_FULL / $C_DESIGN) * 100}")
    else
        HEALTH="100.0"
    fi

    # Map AC Status to NUT flags
    if [ "$LINE_STATUS" = "1" ]; then
        UPS_STATUS="OL"
        [ "$BAT_STATUS" = "Charging" ] && UPS_STATUS="OL CHRG"
    else
        UPS_STATUS="OB"
        [ "$BAT_STATUS" = "Discharging" ] && UPS_STATUS="OB DISCHRG"
    fi

    if [ "$CHARGE_PCT" -le 15 ]; then
        UPS_STATUS="$UPS_STATUS LB"
    fi

    # Formulate the final output block with proper standard Ah units
    printf "ups.status: %s\n\
battery.charge: %s\n\
battery.voltage: %s\n\
battery.voltage.nominal: %s\n\
battery.current: %s\n\
battery.cycles: %s\n\
battery.charge.now: %s\n\
battery.charge.full: %s\n\
battery.charge.full.design: %s\n\
battery.health: %s%%\n\
battery.type: %s\n\
battery.protection.low: %s\n\
battery.protection.high: %s\n\
ups.model: %s\n\
ups.mfr: %s\n\
ups.serial: %s\n" \
        "$UPS_STATUS" "$CHARGE_PCT" "$VOLT" "$VOLT_NOM" "$CURRENT" "$CYCLES" \
        "$AMP_NOW" "$AMP_FULL" "$AMP_DESIGN" "$HEALTH" "$TECH" "$TH_START" "$TH_END" \
        "$MODEL" "$MFR" "$SERIAL" > "$STATUS_FILE.tmp"

    mv "$STATUS_FILE.tmp" "$STATUS_FILE"
    chmod 644 "$STATUS_FILE"
}

update_nut_status
