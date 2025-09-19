ibdiagnet -o ./ibdiagnet2 &> /dev/null; \
grep NODE_WRONG_FW_VERSION ./ibdiagnet2/ibdiagnet2.db_csv | \
awk -F ',' '{print $2}' | \
sed 's/^0x//' | \
xargs -I {} grep {} ./ibdiagnet2/ibdiagnet2.db_csv | \
grep "^\"" | \
awk -F ',' '{print $1,$9}'| awk '{print $1}'| sed 's/"//g'| sort -u