#!/bin/sh
##
## check-osds-loop
##
## Run check-osds script in a loop
##
## This runs the check-osd.pl script in a periodic loop, about every minute by default.
##
## The results are displayed on stdout (the screen is cleared before each output).
##
## Finally, if the script ran through without errors, then the results
## are copied via scp to a fixed filename on a remote server.
##
## If a "osds" directory exists, then the script results are also
## written to small timestamped files in that directory.

## Path to the "check-osds" script.
##
## We "install" the script by copying "check-osds.pl" to "check-osds"
## when it has passed trivial testing.  That's why the ".pl" is missing...
##
CHECK_OSDS=./check-osds

## Destination to copy reports to.
##
## This can be used to implement a trivial "Web UI".
##
DST_HOST=xdp-test.leinen.ch
DST_DIR=/var/www/html/ceph/ls

## Actually the "sleep time" between runs.
##
## The effective interval will be larger, because it also includes the
## time that the check-osds script takes to run.  On our cluster, this
## is currently about five seconds when only a few (3-4) OSDs are
## down.  It will be longer when more OSDs are down, in particular
## when these OSDs are on many different server.
##
INTERVAL=60

## If this directory exists, we will write each report from the
## check-osds script to a small file in there.  The filenames are
## (local) timestamps in format YYYYMMDD-hhmmss.  This allows them to
## be replayed using loops such as
##
##    for x in osds/20200601-1*; do clear; cat $x; sleep 0.04; done
##
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
