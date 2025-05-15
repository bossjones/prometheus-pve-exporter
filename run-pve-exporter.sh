#!/bin/bash

# Configuration
EXPORTER_PORT=9221
PVE_CONFIG="/etc/prometheus/pve.yml"
LOG_FILE="/var/log/pve-exporter.log"

# Check if config exists
if [ ! -f "$PVE_CONFIG" ]; then
    echo "Error: Configuration file $PVE_CONFIG not found!"
    exit 1
fi

# Run the exporter
exec uvx run prometheus-pve-exporter \
    --config.file="$PVE_CONFIG" \
    --web.listen-address=":$EXPORTER_PORT" \
    --collector.status \
    --collector.version \
    --collector.node \
    --collector.cluster \
    --collector.resources \
    2>&1 | tee -a "$LOG_FILE"
