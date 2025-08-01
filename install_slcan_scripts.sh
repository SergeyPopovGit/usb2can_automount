#!/bin/bash

echo "Starting SocketCAN script installation..."

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
   echo "This script must be run with superuser (root) privileges."
   echo "Use: sudo ./install_slcan_scripts.sh"
   exit 1
fi

# Determine the directory where the current script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Temporary file for udev rules before final copy
TEMP_UDEV_RULES_FILE="/tmp/99-slcan.rules.tmp"

# Check for the presence of required files in the script directory
if [ ! -f "$SCRIPT_DIR/slcan_up.sh" ]; then
    echo "Error: slcan_up.sh not found in the script directory ($SCRIPT_DIR)."
    echo "Please ensure slcan_up.sh is in the same directory as install_slcan_scripts.sh."
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/slcan_down.sh" ]; then
    echo "Error: slcan_down.sh not found in the script directory ($SCRIPT_DIR)."
    echo "Please ensure slcan_down.sh is in the same directory as install_slcan_scripts.sh."
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/99-slcan.rules" ]; then
    echo "Error: 99-slcan.rules (template) not found in the script directory ($SCRIPT_DIR)."
    echo "Please ensure 99-slcan.rules with placeholders is in the same directory as install_slcan_scripts.sh."
    exit 1
fi

# Function to list and select USB serial devices
select_usb_device() {
    echo ""
    echo "Searching for USB serial devices (ttyUSBx or ttyACMx)..."
    declare -A devices # Associative array to store device details

    # Get a list of ttyUSB and ttyACM devices and their parent USB device paths
    local -a tty_usb_paths
    mapfile -t tty_usb_paths < <(find /dev/ -maxdepth 1 -regex '.*/ttyU[S]B[0-9]+' -o -regex '.*/ttyACM[0-9]+' -exec readlink -f {} \;)

    if [ ${#tty_usb_paths[@]} -eq 0 ]; then
        echo "No USB serial devices found (ttyUSBx or ttyACMx)."
        echo "Please connect your slcan device and try again."
        exit 1
    fi

    echo ""
    echo "Available USB serial devices:"
    local i=1 # Index for displaying and selecting devices
    for tty_path in "${tty_usb_paths[@]}"; do
        local dev_name=$(basename "$tty_path")
        # Get the /sys path of the tty device, then walk up to find the parent USB device path
        local usb_device_path=/dev/"$dev_name"

        if [ -z "$usb_device_path" ]; then
            echo "    (Could not find parent USB device path for /dev/$dev_name, skipping)"
            continue # Skip if parent USB path is not found
        fi

        # Extract attributes from the parent USB device
        local vendor_id=$(udevadm info -a "$usb_device_path" | grep -m1 'ATTRS{idVendor}==' | sed -e 's/.*==\"//' -e 's/\"//')
        local product_id=$(udevadm info -a "$usb_device_path" | grep -m1 'ATTRS{idProduct}==' | sed -e 's/.*==\"//' -e 's/\"//')
        local serial_num=$(udevadm info -a "$usb_device_path" | grep -m1 'ATTRS{serial}==' | sed -e 's/.*==\"//' -e 's/\"//')
        local manufacturer=$(udevadm info -a "$usb_device_path" | grep -m1 'ATTRS{manufacturer}==' | sed -e 's/.*==\"//' -e 's/\"//')
        local product_str=$(udevadm info -a "$usb_device_path" | grep -m1 'ATTRS{product}==' | sed -e 's/.*==\"//' -e 's/\"//')

        # Only consider and list devices for which we can extract critical attributes
        if [ -n "$vendor_id" ] && [ -n "$product_id" ]; then
            devices[$i,dev_name]="$dev_name"
            devices[$i,vendor_id]="$vendor_id"
            devices[$i,product_id]="$product_id"
            devices[$i,serial_num]="${serial_num:-N/A}" # Assign N/A if serial is empty
            devices[$i,manufacturer]="${manufacturer:-N/A}"
            devices[$i,product_str]="${product_str:-N/A}"

            echo "  [$i] Device: /dev/$dev_name"
            echo "      Vendor ID: $vendor_id"
            echo "      Product ID: $product_id"
            echo "      Serial Number: ${serial_num:-N/A}"
            echo "      Manufacturer: ${manufacturer:-N/A}"
            echo "      Product: ${product_str:-N/A}"
            echo ""
            ((i++)) # Increment index only for successfully processed devices
        else
            echo "    (Could not extract complete USB attributes for /dev/$dev_name, skipping)"
        fi
    done

    # Check if any valid devices were added to the list for selection
    if [ "$i" -eq 1 ]; then # If i is still 1, no valid devices were found
        echo "No valid USB serial devices with complete attributes found."
        echo "Please ensure your slcan device is properly connected and recognized by udev."
        exit 1
    fi

    local choice
    while true; do
        read -p "Enter the number of the device you want to configure: " choice
        # Validate choice: must be a number, within the valid range of displayed devices
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            SELECTED_DEV_NAME="${devices[$choice,dev_name]}"
            SELECTED_VENDOR_ID="${devices[$choice,vendor_id]}"
            SELECTED_PRODUCT_ID="${devices[$choice,product_id]}"
            SELECTED_SERIAL_NUM="${devices[$choice,serial_num]}"
            break
        else
            echo "Invalid choice. Please enter a valid number."
        fi
    done

    echo ""
    echo "You selected device: /dev/$SELECTED_DEV_NAME"
    echo "  Vendor ID: $SELECTED_VENDOR_ID"
    echo "  Product ID: $SELECTED_PRODUCT_ID"
    echo "  Serial Number: ${SELECTED_SERIAL_NUM:-N/A}"
    echo ""
}

# Call the function to select a USB device
select_usb_device

# Read the template 99-slcan.rules
UDEV_RULES_TEMPLATE=$(cat "$SCRIPT_DIR/99-slcan.rules")

# Substitute the placeholders with selected values
# Using sed for substitution. Escaping potential special characters in serial number for sed.
# Vendor ID and Product ID also escaped for consistency, though less likely to have special chars.
ESCAPED_SERIAL=$(echo "$SELECTED_SERIAL_NUM" | sed 's/[\/&]/\\&/g') # Escape / and &
ESCAPED_VENDOR=$(echo "$SELECTED_VENDOR_ID" | sed 's/[\/&]/\\&/g')
ESCAPED_PRODUCT=$(echo "$SELECTED_PRODUCT_ID" | sed 's/[\/&]/\\&/g')


MODIFIED_RULES=$(echo "$UDEV_RULES_TEMPLATE" | \
    sed "s|<VendorID>|$ESCAPED_VENDOR|g" | \
    sed "s|<ProductID>|$ESCAPED_PRODUCT|g" | \
    sed "s|<Serial_Number>|$ESCAPED_SERIAL|g")

# Write the modified rules to a temporary file
echo "$MODIFIED_RULES" > "$TEMP_UDEV_RULES_FILE"

# Copying and configuring slcan_up.sh
cp "$SCRIPT_DIR/slcan_up.sh" /usr/local/bin/slcan_up.sh
chmod +x /usr/local/bin/slcan_up.sh
echo "Copied and made executable: /usr/local/bin/slcan_up.sh"

# Copying and configuring slcan_down.sh
cp "$SCRIPT_DIR/slcan_down.sh" /usr/local/bin/slcan_down.sh
chmod +x /usr/local/bin/slcan_down.sh
echo "Copied and made executable: /usr/local/bin/slcan_down.sh"

# Copying the modified 99-slcan.rules from the temporary file to its final destination
cp "$TEMP_UDEV_RULES_FILE" /etc/udev/rules.d/99-slcan.rules
echo "Copied: /etc/udev/rules.d/99-slcan.rules (configured for selected device)"

# Clean up temporary file
rm -f "$TEMP_UDEV_RULES_FILE"

# Reloading udev rules
echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger
echo "Udev rules reloaded."

echo "Installation complete. The udev rule has been configured for the selected device."
