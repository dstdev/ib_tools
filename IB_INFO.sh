#!/bin/bash

# Helper function to check command success
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed. Exiting."
        exit 1
    fi
}

# Get Hostname
host=$(hostname)
check_command "hostname"

# Get InfiniBand link name
linkinfo=$(ip link | grep ib | grep UP | awk '{print $2}' | sed 's/://')
check_command "ip link"
link=$(echo $linkinfo | awk '{print $1}')
check_command "awk to extract link name"

if [ -z "$link" ]; then
    echo "Error: InfiniBand interface not found. Exiting."
    exit 1
fi

# Get system details using dmidecode
serial=$(dmidecode -t1 | grep "Serial Number" | awk '{print $NF}')
check_command "dmidecode for Serial Number"
model=$(dmidecode -t1 | grep "Product Name" | awk '{print $NF}')
check_command "dmidecode for Product Name"

# Get OS details using lsb_release
os=$(lsb_release -a 2>/dev/null | grep Description | awk '{print $(NF-4)" "$(NF-1)}')
check_command "lsb_release"

# If lsb_release fails, try to fetch from /etc/os-release as a fallback
if [ -z "$os" ]; then
    os=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | awk -F= '{print $2}' | sed 's/"//g')
    check_command "fallback: /etc/os-release"
fi

# Get Kernel version
kernel=$(uname -r)
check_command "uname -r"

# Get Mellanox card model info (filter out Ethernet cards and strip out "0000:")
cardmodels=$(lspci | grep Mellanox | grep -v "Ethernet controller" | awk '{print $1}' | sed 's/^0000://g' | cut -d: -f1 | sort -u)
check_command "lspci for Mellanox"

# If no Mellanox card is found, exit with a message
if [ -z "$cardmodels" ]; then
    echo "Error: No Mellanox cards found. Exiting."
    exit 1
fi

# Get driver information
driver=$(rpm -qa | grep -i infiniband)
check_command "rpm -qa for infiniband driver"

if [[ $driver =~ "mlnx" ]]; then
    drivertype="MOFED"
else
    drivertype="Linux OFED"
fi

# Get driver version and firmware information for the first interface
#driverversion=$(ethtool -i $link | grep -E "^version" | awk '{print $NF}')
check_command "ethtool for driver version"
driverversion=$(ofed_info -s)
check_command "ethtool for driver version"

# Create an associative array to store unique card identifiers
declare -A unique_cards

# Iterate over unique Mellanox card PCI IDs and output their information
for cardid in $cardmodels; do
    # Identify the unique PCI ID by stripping off .0 or .1
    base_cardid=$(echo $cardid | sed 's/\.[01]$//')

    # If this base ID hasn't been seen before, it's a new unique card
    if [[ -z "${unique_cards[$base_cardid]}" ]]; then
        # Store this unique card
        unique_cards[$base_cardid]=1

        # Get card model and firmware version for each unique card
        cardmodel=$(lspci -s $cardid:00.0 | awk '{print  $6}')
        check_command "lspci for card model"

        # Get firmware version
        cardfirmware=$(ethtool -i $link | grep -E "^firmware-version" | awk '{print $(NF-1)}')
        check_command "ethtool for firmware version"

        # Output collected information in CSV format for each unique card
        echo "$host,$serial,$model,$os,$kernel,$cardmodel,$drivertype,$driverversion,$cardfirmware"
    fi
done