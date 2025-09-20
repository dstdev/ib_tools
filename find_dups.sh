#!/bin/bash

# Flag to track if we are in the START_NODES section
inside_nodes=false

# Arrays to track unique and duplicate hostnames
declare -A seen_hostnames
declare -A duplicate_hostnames
declare -A unique_ids

# Create the output files for unique and duplicate entries
output_file="output.csv"
duplicate_file="duplicates.csv"
duplicate_count_file="duplicate_counts.csv"
file_path="/var/tmp/ibdiagnet2/ibdiagnet2.db_csv"

# Output file where results will be stored
my_name=$(basename "$0" | awk -F. '{print $1}')
output_file="${my_name}.csv"

# Function to show help message
show_help() {
    echo "Usage: ${my_name}.sh [options]"
    echo "Options:"
    echo "  -h, --help        Show this help message and exit"
    echo "  -f, --file FILE   Specify the path to the ibdiagnet.db_csv file"
    echo "                    default: /var/tmp/ibdiagnet2/ibdiagnet2.db_csv"
    echo ""
    echo "This script processes the specified ibdiagnet.db_csv file to extract hostnames and their associated vendor card IDs."
    echo "It identifies unique hostnames and tracks duplicate hostnames along with their unique IDs."
    echo "Output is saved in three files:"
    echo "  - output.csv: Contains unique hostnames and their vendor card IDs."
    echo "  - duplicates.csv: Contains duplicate hostnames and their unique IDs."
    echo "  - duplicate_counts.csv: Contains duplicate hostnames, the count of duplicates, and their unique IDs."
    echo ""
    exit 0
}
# Parse command-line options using getopts
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--file)
            file_path="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if the file exists
if [ ! -f "$file_path" ]; then
    echo "Error: File does not exist. Exiting."
    exit 1
fi

# Clear the previous output files if they exist
> "$output_file"
> "$duplicate_file"
> "$duplicate_count_file"

# Write headers for the CSV files
echo "Hostname,Vendor Card ID" > "$output_file"
echo "Hostname,Unique ID" > "$duplicate_file"
echo "Hostname,Duplicate Count,Unique IDs" > "$duplicate_count_file"

# Process the file
while IFS=, read -r node_desc col2 col3 col4 col5 col6 col7 col8 col9 col10 col11 col12 col13; do
    # Check for START_NODES
    if [[ "$node_desc" == "START_NODES"* ]]; then
        inside_nodes=true
        continue
    fi

    # Check for END_NODES and stop processing when found
    if [[ "$node_desc" == "END_NODES"* ]]; then
        inside_nodes=false
        break  # Exit the loop after END_NODES is encountered
    fi

    # Skip the NodeDesc line after START_NODES
    if $inside_nodes && [[ "$node_desc" == NodeDesc* ]]; then
        continue
    fi

    # Process lines inside the START_NODES and END_NODES block
    if $inside_nodes; then
        # Extract the hostname by stripping the 'mlx_' part of the first column (node_desc)
        hostname=$(echo "$node_desc" | sed 's/mlx_//g')

        # Extract the vendor card ID from column 9 (index 8)
        vendor_card_id="$col9"

        # Extract the unique ID from column 6 (strip '0x')
        unique_id=$(echo "$col6" | sed 's/^0x//')

        # Check if this hostname has already been seen
        if [[ -z "${seen_hostnames[$hostname]}" ]]; then
            # If it's the first time we see this hostname, add it to the main file
            echo "$hostname,$vendor_card_id" >> "$output_file"
            seen_hostnames["$hostname"]=1
        else
            # If it's a duplicate, add it to the duplicates file
            echo "$hostname,$unique_id" >> "$duplicate_file"
            duplicate_hostnames["$hostname"]=1

            # Store unique IDs associated with the duplicate hostname
            unique_ids["$hostname"]="${unique_ids[$hostname]},$unique_id"
        fi
    fi
done < "$file_path"

# Report the number of unique and duplicate hostnames
echo "Processing complete."
echo "Unique hostnames saved to: $output_file"
echo "Duplicate hostnames saved to: $duplicate_file"