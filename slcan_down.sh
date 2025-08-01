#!/bin/bash

# $1 will contain the tty device name, e.g., ttyUSB0
TTY_DEVICE="/dev/$1"
CAN_INTERFACE_NAME="mkscan" # The expected CAN interface name, as set in slcan_up.sh

echo "Attempting to stop slcand and bring down SocketCAN for $TTY_DEVICE" >> /var/log/slcan_udev.log

# Find PID of the slcand process associated with this TTY_DEVICE and the specific interface name.
# The pgrep pattern is updated to match how slcand is now started in slcan_up.sh.
SLCAND_PID=$(pgrep -f "slcand -o -f -s[0-9]+ $TTY_DEVICE $CAN_INTERFACE_NAME")

if [ -n "$SLCAND_PID" ]; then
    kill "$SLCAND_PID"
    echo "slcand (PID: $SLCAND_PID) for $TTY_DEVICE stopped." >> /var/log/slcan_udev.log
    sleep 0.5 # Give some time for termination
else
    echo "slcand not found for $TTY_DEVICE or $CAN_INTERFACE_NAME. Possibly already stopped or not started by udev." >> /var/log/slcan_udev.log
fi

# Explicitly try to bring down and delete the interface if it still exists.
# This is a safeguard, as killing slcand usually cleans up the interface,
# but it ensures the interface is closed if slcand somehow didn't manage it.
if ip link show "$CAN_INTERFACE_NAME" &> /dev/null; then
    sudo ip link set "$CAN_INTERFACE_NAME" down
    echo "SocketCAN interface $CAN_INTERFACE_NAME brought down." >> /var/log/slcan_udev.log
    
    # Optionally, you can uncomment the line below to also delete the interface completely.
    # Typically, it's removed by the kernel when slcand exits, but this provides explicit removal.
    # sudo ip link delete "$CAN_INTERFACE_NAME"
    # echo "SocketCAN interface $CAN_INTERFACE_NAME deleted." >> /var/log/slcan_udev.log
else
    echo "SocketCAN interface $CAN_INTERFACE_NAME not found, likely already removed." >> /var/log/slcan_udev.log
fi
