#!/bin/bash

export PRO_IF="eno2" 
export MANAGE_PRO_BRIDGE=y
export INT_IF="ens1f0"
export MANAGE_INT_BRIDGE=n 
export ROOT_DISK="/dev/sda" 
export CLUSTER_NAME="test1"
export BASE_DOMAIN="kni.home"
export MANAGE_BR_BRIDGE=n
export NODES_PLATFORM=BM

#export NUM_MASTERS="1"
export NODES_FILE="$HOME/dev/kni-lab/ironic_hosts_3.json"
