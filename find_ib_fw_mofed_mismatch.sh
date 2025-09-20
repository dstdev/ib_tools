#!/bin/bash
# This script identifies hosts with incorrect firmware versions based on ibdiagnet2 output
output_file=""

show_help() {
    my_name=$(basename "$0")
    echo "Usage: $my_name [options]"
    echo "Options:"
    echo "  -h        Show this help message"
    echo "  -o FILE   Output results to FILE (optional)"
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

# Main logic to find hosts with wrong FW version
result=$(ibdiagnet -o ./ibdiagnet2 &> /dev/null; \
grep NODE_WRONG_FW_VERSION ./ibdiagnet2/ibdiagnet2.db_csv | \
awk -F ',' '{print $2}' | \
sed 's/^0x//' | \
xargs -I {} grep {} ./ibdiagnet2/ibdiagnet2.db_csv | \
grep "^\"" | \
awk -F ',' '{print $1,$9}'| awk '{print $1}'| sed 's/"//g'| sort -u)

if [[ -n "$output_file" ]]; then
    echo "$result" > "$output_file"
else
    echo "$result"
fi
if [[ -z "$result" ]]; then
    echo "No hosts with firmware mismatch version found."
fi