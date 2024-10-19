#!/bin/bash

# Define the ping addresses
CHECK_ADDRESSES=("8.8.8.8" "1.1.1.1" "9.9.9.9")  # Google DNS, Cloudflare DNS and Quad9

# Check every 60 seconds
CHECK_DELAY="60"

# Define network interfaces
WAN1_INTERFACE="eth0"
WAN2_INTERFACE="eth1"

# Define gateway addresses
WAN1_GATEWAY="192.0.2.1"
WAN2_GATEWAY="203.0.113.1"

# Define public addresses
WAN1_ADDRESS="192.0.2.22"
WAN2_ADDRESS="203.0.113.13"

# Define local network
LOCAL_NETWORKS=("192.168.77.0/24" "192.168.78.0/24")

# Define routing tables
WAN1_TABLE="wan1"
WAN2_TABLE="wan2"

# Define log file
LOG_FILE="/var/log/dualwan_failover.log"

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to check connectivity
check_connectivity() {
    local wan="$1"
    shift
    local addresses=("$@")
    for addr in "${addresses[@]}"; do
        if ping -q -n -W 1 -c 3 -s 1472 -I "$wan" "$addr" &> /dev/null; then
            return 0  # Success
        fi
    done
    return 1  # Failure
}

while true; do
    # Check WAN1
    if check_connectivity "$WAN1_ADDRESS" "${CHECK_ADDRESSES[@]}"; then
        log "WAN1 ($WAN1_INTERFACE) is up"
        # Ensure WAN1 is the active route
        for network in "${LOCAL_NETWORKS[@]}"; do
            if ip rule show | grep -q "$network lookup $WAN2_TABLE"; then
                ip rule del from "$network" lookup "$WAN2_TABLE" 2>/dev/null
            fi
            if ! ip rule show | grep -q "$network lookup $WAN1_TABLE"; then
                ip rule add from "$network" priority 11002 lookup "$WAN1_TABLE"
            fi
        done
        if ! ip route show | grep -q "default via $WAN1_GATEWAY"; then
            ip route change default via "$WAN1_GATEWAY" dev "$WAN1_INTERFACE"
            log "Routing switched to WAN1 via $WAN1_ADDRESS"
        fi
    else
        log "WAN1 ($WAN1_INTERFACE) is down, checking WAN2"
        # Check WAN2
        if check_connectivity "$WAN2_ADDRESS" "${CHECK_ADDRESSES[@]}"; then
            log "WAN2 ($WAN2_INTERFACE) is up"
            # Switch to WAN2
            for network in "${LOCAL_NETWORKS[@]}"; do
                if ip rule show | grep -q "$network lookup $WAN1_TABLE"; then
                    ip rule del from "$network" lookup "$WAN1_TABLE" 2>/dev/null
                fi
                if ! ip rule show | grep -q "$network lookup $WAN2_TABLE"; then
                    ip rule add from "$network" priority 12002 lookup "$WAN2_TABLE"
                fi
            done
            if ! ip route show | grep -q "default via $WAN2_GATEWAY"; then
                ip route change default via "$WAN2_GATEWAY" dev "$WAN2_INTERFACE"
                log "Routing switched to WAN2 via $WAN2_ADDRESS"
            fi
        else
            log "Both WAN1 and WAN2 are down"
        fi
    fi

    sleep "$CHECK_DELAY"
done
