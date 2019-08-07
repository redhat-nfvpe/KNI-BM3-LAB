#!/bin/bash

###------------------------------------------------###
### Need interface input from user via environment ###
###------------------------------------------------###

source cluster/prep_bm_host.src

printf "\nChecking parameters...\n\n"

for i in PROV_INTF PROV_BRIDGE BM_INTF BM_BRIDGE; do
    if [[ -z "${!i}" ]]; then
        echo "You must set PROV_INTF, PROV_BRIDGE, BM_INTF and BM_BRIDGE as environment variables!"
        echo "Edit prep_bm_host.src to set these values."
        exit 1
    else
        echo $i": "${!i}
    fi
done

###------------------------------###
### Source helper scripts first! ###
###------------------------------###

# shellcheck disable=SC1091
source "common.sh"
# shellcheck disable=SC1091
source "scripts/network_conf.sh"
# shellcheck disable=SC1091
source "scripts/utils.sh"

###--------------------------------------------------------------------###
### Bring down interfaces and bridges, and delete their network config ###
###--------------------------------------------------------------------###

printf "\nRemoving interface and bridges, and deleting network config...\n\n"

sudo ifdown $PROV_INTF
sudo ifdown $PROV_BRIDGE
sudo ifdown $BM_INTF
sudo ifdown $BM_BRIDGE

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$PROV_INTF" ]]; then
    sudo rm /etc/sysconfig/network-scripts/ifcfg-$PROV_INTF
fi

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$PROV_BRIDGE" ]]; then
    sudo rm /etc/sysconfig/network-scripts/ifcfg-$PROV_BRIDGE
fi

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$BM_INTF" ]]; then
    sudo rm /etc/sysconfig/network-scripts/ifcfg-$BM_INTF
fi

if [[ -f "/etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE" ]]; then
    sudo rm /etc/sysconfig/network-scripts/ifcfg-$BM_BRIDGE
fi

###------------------------------------###
### Remove HAProxy container and image ###
###------------------------------------###

printf "\nRemoving HAProxy container and image...\n\n"

./scripts/gen_haproxy.sh remove

###---------------------------------------###
### Remove provisioning dnsmasq container ###
###---------------------------------------###

printf "\nRemoving provisioning dnsmasq container...\n\n"

DNSMASQ_PROV_CONTAINER=`podman ps -a | grep dnsmasq-prov`

if [[ ! -z "$DNSMASQ_PROV_CONTAINER" ]]; then
    podman rm -f dnsmasq-prov
fi

###------------------------------------###
### Remove baremetal dnsmasq container ###
###------------------------------------###

printf "\nRemoving baremetal dnsmasq container...\n\n"

DNSMASQ_BM_CONTAINER=`podman ps -a | grep dnsmasq-bm`

if [[ ! -z "$DNSMASQ_BM_CONTAINER" ]]; then
    podman rm -f dnsmasq-bm
fi

###--------------------------------------###
### Remove matchbox container and assets ###
###--------------------------------------###

printf "\nRemoving matchbox container and assets...\n\n"

MATCHBOX_CONTAINER=`podman ps -a | grep matchbox`

if [[ ! -z "$MATCHBOX_CONTAINER" ]]; then
    podman rm -f matchbox
fi

if [[ -d "/var/lib/matchbox/assets" ]]; then
    sudo rm -rf /var/lib/matchbox/assets
fi

###--------------------------###
### Remove coredns container ###
###--------------------------###

printf "\nRemoving coredns container...\n\n"

COREDNS_CONTAINER=`podman ps -a | grep coredns`

if [[ ! -z "$COREDNS_CONTAINER" ]]; then
    podman rm -f coredns
fi

###-----------------------------------###
### Remove NetworkManager DNS overlay ###
###-----------------------------------###

printf "\nRemoving NetworkManager DNS overlay...\n\n"

if [[ -f "/etc/NetworkManager/conf.d/openshift.conf" ]]; then
    sudo rm /etc/NetworkManager/conf.d/openshift.conf
fi

if [[ -f "/etc/NetworkManager/dnsmasq.d/openshift.conf" ]]; then
    sudo rm /etc/NetworkManager/dnsmasq.d/openshift.conf
fi

sudo systemctl restart NetworkManager

###-----------------###
### Remove tftpboot ###
###-----------------###

printf "\nRemoving tftpboot...\n\n"

if [[ -d "/var/lib/tftpboot" ]]; then
    sudo rm -rf /var/lib/tftpboot
fi

###---------------###
### Remove golang ###
###---------------###

printf "\nRemoving golang...\n\n"

if [[ ! -d "/usr/local/go" ]]; then
    sudo rm -rf /usr/local/go
    sed -i '/GOPATH/d' ~/.bash_profile
    sed -i '/GOROOT/d' ~/.bash_profile
fi

###---------------------------###
### Remove OpenShift binaries ###
###---------------------------###

printf "\nRemoving OpenShift binaries...\n\n"

if [[ -f "/usr/local/bin/openshift-install" ]]; then
    sudo rm -f /usr/local/bin/openshift-install
fi

if [[ -f "/usr/local/bin/oc" ]]; then
    sudo rm -f /usr/local/bin/oc
fi

###------------------###
### Remove terraform ###
###------------------###

printf "\nRemoving Terraform...\n\n"

if [[ -f "/usr/bin/terraform" ]]; then
    sudo rm -f /usr/bin/terraform
fi

if [[ -f "~/.terraform.d" ]]; then
    sudo rm -rf ~/.terraform.d
fi

###------------------------------------------------------------------------------###
### Remove Git, Podman, Unzip, Ipmitool, Dnsmasq, Bridge-Utils, Epel, Pip and Jq ###
###------------------------------------------------------------------------------###

printf "\nRemoving dependencies via yum...\n\n"

sudo yum remove -y git podman unzip ipmitool dnsmasq bridge-utils epel-release python-pip jq

printf "\nDONE\n"