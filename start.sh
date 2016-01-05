#!/bin/bash
set -o errexit

sudo chown -R senlin:senlin /etc/senlin /var/log/senlin /var/cache/senlin

echo "run command: $@"
exec $@ 
