#!/bin/sh
##
## check-osds-loop
##
## Run check-osd script in a loop
##
## This runs the check-osd.pl script in a periodic loop, about every minute by default.
##
## The results are displayed on stdout (the screen is cleared before each output).
##
## Finally, if the script ran through without errors, then the results
## are copied via scp to a fixed filename on a remote server.  This
## can be used to publish them via a Web server.
##
## If a "osds" directory exists, then the script results are also
## written to small timestamped files in that directory.  This allows
## replaying them using loops such as
##
##    for x in osds/20200601-1*; do clear; cat $x; sleep 0.04; done
##
DST_HOST=xdp-test.leinen.ch
DST_DIR=/var/www/html/ceph/ls

INTERVAL=60

LOG_DIR=osds

while true
do
  clear
  d=`date +%Y%m%d-%H%M%S`
  if test -d ${LOG_DIR}
  then
    f=${LOG_DIR}/$d
  else
    f=check-osds.out
  fi
  if ./check-osds | tee $f
  then
    if [ "z${DST_HOST}" != z ]
    then
      scp -q $f ${DST_HOST}:${DST_DIR}/osd-status
    fi
  fi
  sleep ${INTERVAL}
done
