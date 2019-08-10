#!/bin/bash

# shellcheck disable=SC1091
source "common.sh"

DNSMASQ_CONTAINER_NAME="dnsmasq-prov"
DNSMASQ_CONTAINER_IMAGE="quay.io/poseidon/dnsmasq"

# Script to generate dnsmasq.conf for the provisioning network
# This script is intended to be called from a master script in the
# base project or to be run from the base project directory
# i.e
#  prep_bm_host.sh calls scripts/gen_config_prov.sh
#  or
#  [basedir]./scripts/gen_config_prov.sh
#

usage() {
    cat <<-EOM
    Generate configuration files for the provisioning interface 
    Files created:
        provisioning: dnsmasq.conf
        baremetal: dnsmasq.conf, dnsmasq.conf
    
    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-s prep_bm_host.src] [-m manfifest_dir] [-o out_dir] 
            Generate config files for the provisioning interface

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
        -s [./../prep_host_setup.src -- Location of the config file for host prep
            Default to $PROJECT_DIR/cluster//prep_host_setup.src
EOM
}

gen_config_prov() {
    local intf=$1
    local out_dir=$2

    local etc_dir="$out_dir/$PROV_ETC_DIR"
    local var_dir="$out_dir/$PROV_VAR_DIR"

    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"

    local out_file="$etc_dir/dnsmasq.conf"

    printf "Generating %s...\n" "$out_file"

    [[ "$VERBOSE" =~ true ]] && printf "Generating %s\n" "$out_file"
    
    cat <<EOF >"$out_file"
# This config file is intended for use with a container instance of dnsmasq

# The container should be run as follows with the generated dnsmasq.conf file"
# placed in $etc_dir/"
# log and leasefiles will be located in $var_dir/"
# podman run -d --name dnsmasq-prov --net=host -v $var_dir:/var/run/dnsmasq:Z \\"
#  -v $etc_dir:/etc/dnsmasq.d:Z \\"
#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq \\
#  --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"

port=0 # do not activate nameserver
interface=$intf
bind-interfaces

dhcp-range=$PROV_IP_RANGE_START,$PROV_IP_RANGE_END,30m

# do not send default gateway
dhcp-option=3
# do not send dns server
dhcp-option=6

# Legacy PXE
dhcp-match=set:bios,option:client-arch,0
dhcp-boot=tag:bios,undionly.kpxe

# UEFI
dhcp-match=set:efi32,option:client-arch,6
dhcp-boot=tag:efi32,ipxe.efi
dhcp-match=set:efibc,option:client-arch,7
dhcp-boot=tag:efibc,ipxe.efi
dhcp-match=set:efi64,option:client-arch,9
dhcp-boot=tag:efi64,ipxe.efi

# verbose
log-queries
log-dhcp

dhcp-leasefile=/var/run/dnsmasq/dnsmasq.leasefile
log-facility=/var/run/dnsmasq/dnsmasq.log

# iPXE - chainload to matchbox ipxe boot script
dhcp-userclass=set:ipxe,iPXE
dhcp-boot=tag:ipxe,http://$PROV_IP_IPXE_URL/boot.ipxe

# Enable dnsmasq's built-in TFTP server
enable-tftp

# Set the root directory for files available via FTP.
tftp-root=/var/lib/tftpboot

tftp-no-blocksize

dhcp-boot=pxelinux.0

EOF
}

gen_config() {
    local out_dir="$1"

    gen_config_prov "$PROV_BRIDGE" "$out_dir"
}


VERBOSE="false"
export VERBOSE

while getopts ":ho:s:m:v" opt; do
    case ${opt} in
    o)
        out_dir=$OPTARG
        ;;
    s)
        prep_host_setup_src=$OPTARG
        ;;
    m)
        manifest_dir=$OPTARG
        ;;
    v)
        VERBOSE="true"
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
    esac
done

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
else
    COMMAND="prov"
fi

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"

prep_host_setup_src="$PROJECT_DIR/cluster/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

out_dir=${out_dir:-$PROJECT_DIR/dnsmasq}
out_dir=$(realpath "$out_dir")

manifest_dir=${manifest_dir:-$PROJECT_DIR/cluster}
manifest_dir=$(realpath "$manifest_dir")

case "$COMMAND" in
prov)
    gen_config "$out_dir"
    ;;
start)
    gen_config "$out_dir"
    if podman ps --all | grep "$DNSMASQ_CONTAINER_NAME" >/dev/null; then
        printf "%s already exists, removing and starting...\n" "$DNSMASQ_CONTAINER_NAME"
        podman stop "$DNSMASQ_CONTAINER_NAME" >/dev/null 2>&1
        if ! podman rm "$DNSMASQ_CONTAINER_NAME" >/dev/null; then
            printf "Could not remove \"%s\"" "$DNSMASQ_CONTAINER_NAME"
            exit 1
        fi
    fi
    if ! cid=$(podman run -d --name "$DNSMASQ_CONTAINER_NAME" --net=host \
        -v "$PROJECT_DIR/dnsmasq/bm/var/run:/var/run/dnsmasq:Z" \
        -v "$PROJECT_DIR/dnsmasq/bm/etc/dnsmasq.d:/etc/dnsmasq.d:Z" \
        --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 \
        --expose=69/udp --cap-add=NET_ADMIN "$DNSMASQ_CONTAINER_IMAGE" \
        --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q); then
        printf "Could not start %s container!\n" "$DNSMASQ_CONTAINER_NAME"
        exit 1
    fi
    run_status=$(podman inspect $DNSMASQ_CONTAINER_NAME | jq .[0].State.Running)
    if [[ "$run_status" =~ false ]]; then
        printf "Failed to start container...\n"
        podman logs "$DNSMASQ_CONTAINER_NAME"
    else
        printf "Started %s as id %s\n" "$DNSMASQ_CONTAINER_NAME" "$cid"
    fi
    ;;
stop)
    cid=$(podman stop "$DNSMASQ_CONTAINER_NAME") && printf "Stopped %s\n" "$cid"
    ;;
remove)
    podman stop "$DNSMASQ_CONTAINER_NAME" 2>/dev/null && podman rm "$DNSMASQ_CONTAINER_NAME" >/dev/null
    ;;

*)
    echo "Unknown command: ${COMMAND}"
    usage
    ;;
esac
