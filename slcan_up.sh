#!/bin/bash

# $1 will contain the tty device name, e.g., ttyUSB0
TTY_DEVICE="/dev/$1"
CAN_BITRATE_SETTING="s6" # Set the bitrate using the -s option (s6 for 500kbit/s)
CAN_INTERFACE_NAME="mkscan" # Desired CAN interface name

# Check if the tty device exists
if [ ! -c "$TTY_DEVICE" ]; then
    echo "Error: Device $TTY_DEVICE not found." >> /var/log/slcan_udev.log
    exit 1
fi

# Check if slcand is already running for this device with the specified interface name
# The pgrep pattern now includes the desired interface name
if pgrep -f "slcand -o -f -$CAN_BITRATE_SETTING $TTY_DEVICE $CAN_INTERFACE_NAME" > /dev/null; then
    echo "slcand is already running for $TTY_DEVICE as $CAN_INTERFACE_NAME. Skipping." >> /var/log/slcan_udev.log
    exit 0
fi

# Start slcand in the background, specifying the tty device, bitrate, and interface name
# -o: Only open the device, do not exit after one second
# -f: Run in foreground (useful for debugging, but still run in background via &)
# -s6: Set CAN bitrate (s6 for 500kbit/s)
slcand -o -f -$CAN_BITRATE_SETTING "$TTY_DEVICE" "$CAN_INTERFACE_NAME" &> /var/log/slcan_udev.log &
SLCAND_PID=$!
echo "Started slcand for $TTY_DEVICE (PID: $SLCAND_PID) as interface $CAN_INTERFACE_NAME with bitrate setting $CAN_BITRATE_SETTING (500kbit/s)" >> /var/log/slcan_udev.log

# Give some time for slcand to initialize
sleep 1

# Bring up the SocketCAN interface with the desired name (it should be created by now)
# No need to rename, as slcand creates it directly with the specified name
sudo ip link set "$CAN_INTERFACE_NAME" up

if [ $? -eq 0 ]; then
    echo "SocketCAN interface $CAN_INTERFACE_NAME brought up for $TTY_DEVICE" >> /var/log/slcan_udev.log
else
    echo "Error: Failed to bring up SocketCAN interface $CAN_INTERFACE_NAME for $TTY_DEVICE" >> /var/log/slcan_udev.log
    kill $SLCAND_PID # Kill slcand if interface failed to come up
fi
