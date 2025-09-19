#!/bin/bash
## 
# Path to the generated file
file_path="/var/tmp/ibdiagnet2/ibdiagnet2.db_csv"
lookup_file="/var/tmp/ibdiagnet2/ibdiagnet2.db_csv"

# Output file where results will be stored
output_file="fw_check_output.csv"

# Check if the file exists
if [ ! -f "$file_path" ]; then
    echo "Error: $file_path does not exist. Exiting."
    exit 1
fi

# Write CSV header
echo "column_2,column_6" > "$output_file"

# Flag to track when we are between START_WARNINGS_FW_CHECK and END_WARNINGS_FW_CHECK
processing=false

# Read the lookup file into a hash table (associative array) for fast lookups
declare -A lookup_table

# Flag to process nodes from START_NODES to END_NODES
in_nodes_section=false

# Read the lookup file line by line and populate the lookup table
while IFS= read -r line; do
    # Skip lines until we find the START_NODES section
    if [[ "$line" == *"START_NODES"* ]]; then
        in_nodes_section=true
        continue
    fi

    # Stop processing when we reach END_NODES
    if [[ "$line" == *"END_NODES"* ]]; then
        in_nodes_section=false
        continue
    fi

    # If we are in the node section, process the line
    if $in_nodes_section; then
        # Extract column 1 (Node name) and column 6 (GUID)
        column_1=$(echo "$line" | cut -d',' -f1)
        column_6=$(echo "$line" | cut -d',' -f6)

        # Add the GUID (column 6) as the key and node name (column 1) as the value to the lookup table
        lookup_table["$column_6"]=$column_1
    fi
done < "$lookup_file"

# Flag to track when we are between START_WARNINGS_FW_CHECK and END_WARNINGS_FW_CHECK
processing=false

# Read the target file line by line``
while IFS= read -r line; do
    # Check if we are starting to process
    if [[ "$line" == *"START_WARNINGS_FW_CHECK"* ]]; then
        processing=true
        continue
    fi

    # Check if we have reached the end of the processing section
    if [[ "$line" == *"END_WARNINGS_FW_CHECK"* ]]; then
        processing=false
        continue
    fi

    # If we are between the start and end markers
    if $processing; then
        # Split the line by commas and extract column 2 (GUID) and column 6 (summary)
        column_2=$(echo "$line" | cut -d',' -f2)
        column_6=$(echo "$line" | cut -d',' -f6)

        # Remove the '0x' prefix from column 2 (if it exists)
        column_2=$(echo "$column_2" | sed 's/^0x//')

        # Look up the column_2 value (GUID) in the lookup table and replace with column_1 (Node name)
        if [[ -n "${lookup_table[$column_2]}" ]]; then
            column_2="${lookup_table[$column_2]}"
        fi

        # Write the extracted and modified information to the output file
        echo "$column_2,$column_6" >> "$output_file"
    fi
done < "$file_path"

# Display the results
cat "$output_file"
