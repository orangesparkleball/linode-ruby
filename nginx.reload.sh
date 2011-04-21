#!/bin/bash
#
# This script will check for /tmp/restart.nginx
# If found, it will restart the nginx server

if [ -f /tmp/restart.nginx ] ; then
  /opt/nginx/sbin/nginx -s reload
  rm /tmp/restart.nginx
fi

