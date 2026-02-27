#!/bin/bash
set -euo pipefail

# This script identifies hosts with incorrect firmware versions based on ibdiagnet2 output
my_name=$(basename "$0" | awk -F. '{print $1}')
output_file="${my_name}.out"

show_help() {
    echo "Usage: ${my_name}.sh [options]"
    echo "Options:"
    echo "  -h        Show this help message"
    echo "  -o FILE   Output results to FILE (default: ${my_name}.out)"
    echo ""
    echo "This script will output which hosts have Firmware mismatch"
    echo "relative to what the switch MOFED expects."
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -o)
            output_file="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run ibdiagnet and check for errors
if ! ibdiagnet -o ./ibdiagnet2 > /dev/null 2>&1; then
    echo "Error: ibdiagnet failed. Exiting."
    exit 1
fi

db_csv="./ibdiagnet2/ibdiagnet2.db_csv"
if [ ! -f "$db_csv" ]; then
    echo "Error: $db_csv not found. Exiting."
    exit 1
fi

# Find hosts with wrong FW version
result=$(grep NODE_WRONG_FW_VERSION "$db_csv" | \
awk -F ',' '{print $2}' | \
sed 's/^0x//' | \
xargs -I {} grep {} "$db_csv" | \
grep "^\"" | \
awk -F ',' '{print $1,$9}'| awk '{print $1}'| sed 's/"//g'| sort -u) || true

if [[ -z "$result" ]]; then
    echo "No hosts with firmware mismatch version found."
    exit 0
fi

echo "$result" > "$output_file"
echo "Wrote: $output_file"
