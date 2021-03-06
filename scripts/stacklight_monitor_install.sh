#!/bin/bash -x
exec > >(tee -i /tmp/$(basename $0 .sh)_$(date '+%Y-%m-%d_%H-%M-%S').log) 2>&1

# Start by flusing Salt Mine to make sure it is clean
salt "*" mine.flush

# Install StackLight services, and gather the Collectd and Heka metadata
salt "*" state.sls collectd
salt "*" state.sls heka

# Gather the Grafana metadata as grains
salt -C 'I@grafana:collector' state.sls grafana.collector

# Update Salt Mine
salt "*" state.sls salt.minion.grains
salt "*" saltutil.refresh_modules
salt "*" mine.update

sleep 5

# Update Heka
salt -C 'I@heka:aggregator:enabled:True or I@heka:remote_collector:enabled:True' state.sls heka

# Update Collectd
salt -C 'I@collectd:remote_client:enabled:True' state.sls collectd

# Update Nagios
salt -C 'I@nagios:server' state.sls nagios

# Finalize the configuration of Grafana (add the dashboards...)
salt -C 'I@grafana:client' state.sls grafana.client.service
salt -C 'I@grafana:client' --async service.restart salt-minion; sleep 10
salt -C 'I@grafana:client' state.sls grafana.client

# The following is only applied when StackLight is deployed in cluster
# Get the StackLight VIP
vip=$(salt-call pillar.data _param:stacklight_monitor_address --out key|grep _param: |awk '{print $2}')
vip=${vip:=172.16.10.253}

# Start manually the services that are bound to the monitoring VIP
salt -G "ipv4:$vip" service.start remote_collectd
salt -G "ipv4:$vip" service.start remote_collector
salt -G "ipv4:$vip" service.start aggregator

# Stop Nagios on monitoring nodes (b/c package starts it by default), then
# start Nagios where the VIP is running.
salt -C 'I@nagios:server:automatic_starting:False' service.stop nagios3
salt -G "ipv4:$vip" service.start nagios3
