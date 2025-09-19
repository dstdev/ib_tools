# ib_tools

On one node on the fabric - download and run `ib_check.sh` 
`ib_check.sh` creates /var/tmp/ibdiagnet2/ibdiagnet2.db_csv 

Next - run 'IB_INFO2.sh' - this script creates `output.csv` 

===========================================================================
IB_INFO.sh - needs to run from a common location on each node in the fabric 
output is one line per run:  
```
# ./IB_INFO.sh
head01,S285358X7528059,SSG-6028R-LUSTRE-MDS1,CentOS 7.9.2009,3.10.0-1160.119.1.el7.x86_64,MT27800,MOFED,MLNX_OFED_LINUX-23.10-4.0.9.1:,16.35.4030
#
Format for line above:
"$host,$serial,$model,$os,$kernel,$cardmodel,$drivertype,$driverversion,$cardfirmware"
``` 
