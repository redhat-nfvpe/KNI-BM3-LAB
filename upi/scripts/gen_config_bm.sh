#!/bin/bash

# Script to generate dnsmasq.conf for the baremetal network
# This script is intended to be called from a master script in the
# base project or to be run from the base project directory
# i.e
#  prep_bm_host.sh calls scripts/gen_config_prov.sh
#  or
#  [basedir]./scripts/gen_config_prov.sh
#

usage() {
    cat <<-EOM
    Generate configuration files for the baremetal interface 
    Files created:
        dnsmasq.conf, dnsmasq.conf
    
    The env var PROJECT_DIR must be defined as the location of the 
    upi project base directory.

    Usage:
        $(basename "$0") [-h] [-s prep_bm_host.src] [-m manfifest_dir] [-o out_dir] 
            Generate config files for the baremetal interface

    Options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to $PROJECT_DIR/cluster/
        -o out_dir -- Where to put the output [defaults to $PROJECT_DIR/dnsmasq/...]
        -s [./../prep_host_setup.src -- Location of the config file for host prep
            Default to $PROJECT_DIR/cluster//prep_host_setup.src
EOM
}
if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/utils.sh"

prep_host_setup_src="$PROJECT_DIR/cluster/prep_bm_host.src"
prep_host_setup_src=$(realpath "$prep_host_setup_src")

# get prep_host_setup.src file info
parse_prep_bm_host_src "$prep_host_setup_src"

# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/network_conf.sh"

gen_hostfile_bm() {
    out_dir=$1

    hostsfile="$out_dir/$BM_ETC_DIR/dnsmasq.hostsfile"

    #list of master manifests

    cid="${FINAL_VALS[cluster_id]}"
    cdomain="${FINAL_VALS[cluster_domain]}"
    echo "${FINAL_VALS[bootstrap_mac_address]},$BM_IP_BOOTSTRAP,$cid-bootstrap-0.$cdomain" | tee "$hostsfile"

    echo "${FINAL_VALS[master-0.spec.bootMACAddress]},$(get_master_bm_ip 0),$cid-master-0.$cdomain" | tee -a "$hostsfile"

    if [ -n "${FINAL_VALS[master-1.spec.bootMACAddress]}" ] && [ -z "${FINAL_VALS[master-2.spec.bootMACAddress]}" ]; then
        echo "Both master-1 and master-2 must be set."
        exit 1
    fi

    if [ -z "${FINAL_VALS[master-1.spec.bootMACAddress]}" ] && [ -n "${FINAL_VALS[master-2.spec.bootMACAddress]}" ]; then
        echo "Both master-1 and master-2 must be set."
        exit 1
    fi

    if [ -n "${FINAL_VALS[master-1.spec.bootMACAddress]}" ] && [ -n "${FINAL_VALS[master-2.spec.bootMACAddress]}" ]; then
        echo "${FINAL_VALS[master-1.spec.bootMACAddress]},$BM_IP_MASTER_1,$cid-master-1.$cdomain" | tee -a "$hostsfile"
        echo "${FINAL_VALS[master-2.spec.bootMACAddress]},$BM_IP_MASTER_2,$cid-master-2.$cdomain" | tee -a "$hostsfile"
    fi

   # generate hostfile entries for workers
   # how?
   #num_masters="${FINAL_VALS[master_count]}"
   # for ((i = 0; i < num_masters; i++)); do
   #     m="master-$i"
   #     printf "    name: \"%s\"\n" "${FINAL_VALS[$m.metadata.name]}" | sudo tee -a "$ofile"
   #     printf "    public_ipv4: \"%s\"\n" "$(get_master_bm_ip $i)" | sudo tee -a "$ofile"
   #     printf "    ipmi_host: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.address]}" | sudo tee -a "$ofile"
   #     printf "    ipmi_user: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.user]}" | sudo tee -a "$ofile"
   #     printf "    ipmi_pass: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.password]}" | sudo tee -a "$ofile"
   #     printf "    mac_address: \"%s\"\n" "${FINAL_VALS[$m.spec.bootMACAddress]}" | sudo tee -a "$ofile"
   # 
   # done
    cat <<EOF >>"$hostsfile"
    192.168.111.50,$cid-worker-0.$cdomain
    192.168.111.51,$cid-worker-1.$cdomain

    # 192.168.111.59,cluster_id-worker-9.cluster_domain
EOF
}

gen_bm_help() {
    echo "# The container should be run as follows with the generated dnsmasq.conf file"
    echo "# located in $etc_dir/"
    echo "# an automatically generated dnsmasq hostsfile should also be present in"
    echo "# $etc_dir/"
    echo "#"
    echo "# podman run -d --name dnsmasq-bm --net=host\\"
    echo "#  -v $var_dir:/var/run/dnsmasq:Z \\"
    echo "#  -v $etc_dir:/etc/dnsmasq.d:Z \\"
    echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
    echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq \\"
    echo "#  --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"
}

gen_config_bm() {
    intf="$1"
    out_dir="$2"

    etc_dir="$out_dir/$BM_ETC_DIR"
    var_dir="$out_dir/$BM_VAR_DIR"

    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"

    cat <<EOF >"$etc_dir/dnsmasq.conf"
# This config file is intended for use with a container instance of dnsmasq

$(gen_bm_help)
port=0
interface=$intf
bind-interfaces

strict-order
except-interface=lo

domain=${ALL_VARS[install - config.baseDomain]},$BM_IP_CIDR

dhcp-range=$BM_IP_RANGE_START,$BM_IP_RANGE_END,30m
#default gateway
dhcp-option=3,$BM_IP_NS
#dns server
dhcp-option=6,$BM_IP_NS

log-queries
log-dhcp

dhcp-no-override
dhcp-authoritative

#dhcp-hostsfile=/etc/dnsmasq.d/dnsmasq.hostsfile
dhcp-leasefile=/var/run/dnsmasq/dnsmasq.leasefile
log-facility=/var/run/dnsmasq/dnsmasq.log

EOF
}

while getopts ":ho:s:m:" opt; do
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

out_dir=${out_dir:-$PROJECT_DIR/dnsmasq}
out_dir=$(realpath "$out_dir")

manifest_dir=${manifest_dir:-$PROJECT_DIR/cluster}
manifest_dir=$(realpath "$manifest_dir")

parse_manifests "$manifest_dir"

map_cluster_vars

gen_config_bm "$PROV_INTF" "$out_dir"
gen_hostfile_bm "$out_dir" 
