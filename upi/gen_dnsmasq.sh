#!/bin/bash

# This script generates dnsmasq configuration files for the UPI install project.
# The UPI install project employs two instances of dnsmasq.  One instance provides
# dhcp/pxe boot for the provisioning network.  The second instance provides dhcp
# and DNS for the baremetal network.  Dnsmasq is run as a container using podman.
# The configuration files for both dnsmasqs are located as should below.
#
#── /root_path/
#│   ├── bm
#│   │   ├── etc
#│   │   │   └── dnsmasq.d
#│   │   │       ├── dnsmasq.conf
#│   │   │       └── dnsmasq.hostsfile
#│   │   └── var
#│   │       └── run
#│   │           ├── dnsmasq.leasefile
#│   │           └── dnsmasq.log
#│   └── prov
#│       ├── etc
#│       │   └── dnsmasq.conf
#│       └── var
#│           └── run
#│               ├── dnsmasq.leasefile
#│               └── dnsmasq.log
#
# This script requires a /root_path/ argument in order to set the proper locations
# in the generated config files.  For the provisioning network, only the dnsmasq.conf
# is generated.  The dnsmasq.leasefile and dnsmasq.logfile are created when dnsmasq
# is started.  For the the baremetal network, dnsmasq.conf and dnsmasq.hostsfiles are
# generated.
#
# The script also requires a path to one or three MASTER manifest files.
# The name: attribute should be master-0[, master-1, master-2].
#
# An example manifest file is show below.
#
# apiVersion: metalkube.org/v1alpha1
#
# kind: BareMetalHost
# metadata:
#   name: master-0
# spec:
#   externallyProvisioned: true
#   online: true # Must be set to true for provisioing
#   hardwareProfile: ""
#   bmc:
#     address: ipmi://10.19.110.16
#     credentialsName: ha-lab-ipmi-secret
#   bootMACAddress: 0c:c4:7a:8e:ee:0c

nthhost()
{
    address="$1"
    nth="$2"
    
    mapfile -t ips < <(nmap -n -sL "$address" 2>&1 | awk '/Nmap scan report/{print $NF}')
    #ips=($(nmap -n -sL "$address" 2>&1 | awk '/Nmap scan report/{print $NF}'))
    ips_len="${#ips[@]}"
    
    if [ "$ips_len" -eq 0 ] || [ "$nth" -gt "$ips_len" ]; then
        echo "Invalid address: $address or offset $nth"
        exit 1
    fi
    
    echo "${ips[$nth]}"
}

PROV_IP_CIDR="172.22.0.0/24"
PROV_IP_IPXE_URL="$(nthost $PROV_IP_CIDR 10): 8080" # 172.22.0.10
PROV_IP_RANGE_START=$(nthhost "$PROV_IP_CIDR" 11)   # 172.22.0.11
PROV_IP_RANGE_END=$(nthhost "$PROV_IP_CIDR" 30)     # 172.22.0.30
PROV_ETC_DIR="bm/etc/dnsmasq.d"
PROV_VAR_DIR="bm/var/run/dnsmasq"

BM_IP_CIDR="192.168.111.0/24"
BM_IP_RANGE_START=$(nthhost "$BM_IP_CIDR" 10)     # 192.168.111.10
BM_IP_RANGE_END=$(nthhost "$BM_IP_CIDR" 60)       # 192.168.111.60
BM_IP_BOOTSTRAP=$(nthhost "$BM_IP_CIDR" 10)       # 192.168.111.10
BM_IP_MASTER_0=$(nthhost "$BM_IP_CIDR" 11)        # 192.168.111.11
BM_IP_MASTER_1=$(nthhost "$BM_IP_CIDR" 12)        # 192.168.111.12
BM_IP_MASTER_2=$(nthhost "$BM_IP_CIDR" 13)        # 192.168.111.13
BM_IP_NS=$(nthhost "$BM_IP_CIDR" 1)               # 192.168.111.1
BM_IP_WORKER_START=$(nthhost "$BM_IP_CIDR" 20)    # 192.168.111.20

BM_ETC_DIR="bm/etc/dnsmasq.d"
BM_VAR_DIR="bm/var/run/dnsmasq"

# Global variables
unset cluster_id
unset cluster_domain
unset prov_interface
unset bm_terface
unset ext_interface

check_var()
{
    
    if [ "$#" -ne 2 ]; then
        echo "${FUNCNAME[0]} requires 2 arguements, varname and config_file...($(caller))"
        exit 1
    fi
    
    local varname=$1
    local config_file=$2
    
    if [ -z "${!varname}" ]; then
        echo "$varname not set in ${config_file}, must define $varname"
        exit 1
    fi
}

check_regular_file_exists() {
    cfile="$1"
    
    if [ ! -f "$cfile" ]; then
        echo "file does not exist: $cfile"
        exit 1
    fi
}

check_directory_exists() {
    dir="$1"
    
    if [ ! -d "$dir" ]; then
        echo "directory does not exist: $dir"
        exit 1
    fi
}


usage() {
    cat <<EOM
    Generate configuration files for either the provisioning interface or the
    baremetal interface. Files created:
       provisioning: dnsmasq.conf
       baremetal: dnsmasq.conf, dnsmasq.conf

    Usage:
     $(basename "$0") [common_options] prov
        Generate config files for the provisioning interface

     $(basename "$0") [common_options] bm
        Generate config files for the baremetal interface

    common_options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to ./cluster/
        -b base_dir -- Where to put the output [defaults to ./dnsmasq/...]
        -s [path/]prep_host_setup.src -- Location of the config file for host prep
            Default to ./prep_host_setup.src
EOM
    exit 0
}

gen_config_prov() {
    local intf=$1
    local out_dir=$2
    
    local etc_dir="$out_dir/$PROV_ETC_DIR"
    local var_dir="$out_dir/$PROV_VAR_DIR"
    
    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"
    
cat <<EOF > "$etc_dir/dnsmasq.conf"
# This config file is intended for use with a container instance of dnsmasq

echo "The container should be run as follows with the generated dnsmasq.conf file"
echo "placed in $etc_dir/"
echo "log and leasefiles will be located in $var_dir/"
echo "# podman run -d --name dnsmasq-prov --net=host -v $var_dir:/var/run/dnsmasq:Z \\"
echo "#  -v $etc_dir:/etc/dnsmasq.d:Z \\"
echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq \\
echo "#  --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"

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

gen_hostfile_bm() {
    out_dir=$1
    cid=$2
    cdomain=$3
    prep_src=$4
    
    hostsfile="$out_dir/$BM_ETC_DIR/dnsmasq.hostsfile"
    
    # cluster_id.cluster_domain
    
    #list of master manifests
    
    # shellcheck source=/dev/null
    source "$prep_src"
    
    if [ -z "${BSTRAP_BM_MAC}" ]; then
        echo "BSTRAP_BM_MAC not set in ${prep_src}, must define BSTRAP_BM_MAC"
        exit 1
    fi
    echo "$BSTRAP_BM_MAC,$BM_IP_BOOTSTRAP,$cid-bootstrap-0.$cdomain" | sudo tee "$hostsfile"
    
    if [ -z "${MASTER_0_BM_MAC}" ]; then
        echo "MASTER_0_BM_MAC not set in ${prep_src}, must define MASTER_0_BM_MAC"
        exit 1
    fi
    echo "$MASTER_0_BM_MAC,$BM_IP_MASTER_0,$cid-master-0.$cdomain" | sudo tee -a "$hostsfile"
    
    if [ -n "${MASTER_1_BM_MAC}" ] && [ -z "${MASTER_2_BM_MAC}" ]; then
        echo "Both MASTER_1_BM_MAC and MASTER_2_BM_MAC must be set."
        exit 1
    fi
    
    if [ -z "${MASTER_1_BM_MAC}" ] && [ -n "${MASTER_2_BM_MAC}" ]; then
        echo "Both MASTER_1_BM_MAC and MASTER_2_BM_MAC must be set."
        exit 1
    fi
    
    if [ -n "${MASTER_1_BM_MAC}" ] && [ -n "${MASTER_2_BM_MAC}" ]; then
        echo "$MASTER_1_BM_MAC,$BM_IP_MASTER_1,$cid-master-1.$cdomain" | sudo tee -a "$hostsfile"
        echo "$MASTER_2_BM_MAC,$BM_IP_MASTER_2,$cid-master-2.$cdomain" | sudo tee -a "$hostsfile"
        
        echo "Both MASTER_1_BM_MAC and MASTER_2_BM_MAC must be set."
        exit 1
    fi
    
    # loop through list
    # make sure there is a master-0[, master-1, master-2]
    #
    # 52:54:00:82:68:3f,192.168.111.10,cluster_id-bootstrap.cluster_domain
    # 52:54:00:82:68:3f,192.168.111.11,cluster_id-master-0.cluster_domain
    # 52:54:00:82:68:3f,192.168.111.12,cluster_id-master-1.cluster_domain
    # 52:54:00:82:68:3f,192.168.111.13,cluster_id-master-2.cluster_domain
    #
     cat <<EOF >> "$hostsfile"
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
    cid="$3"
    
    etc_dir="$out_dir/$BM_ETC_DIR"
    var_dir="$out_dir/$BM_VAR_DIR"
    
    mkdir -p "$etc_dir"
    mkdir -p "$var_dir"
    
    cat <<EOF > "$etc_dir/dnsmasq.conf"
# This config file is intended for use with a container instance of dnsmasq

$(gen_bm_help)
port=0
interface=$intf
bind-interfaces

strict-order
except-interface=lo

domain=$cid,$BM_IP_CIDR

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

parse_install_config_yaml()
{
    ifile=$1
    
    check_regular_file_exists "$ifile"
    
    cluster_id=$(yq .metadata.name "$ifile")
    if [ -z "$cluster_id" ]; then
        echo "Missing cluster name!"
        exit 1
    fi
    
    cluster_domain=$(yq .baseDomain "$ifile")
    if [ -z "$cluster_domain" ]; then
        echo "Missing domain!"
        exit 1
    fi
}

parse_manifests() {
    local manifest_dir=$1
    
    for file in "$manifest_dir"/*.yaml; do
        unset sdnMac
        echo "check $file"
        ret=$(yq '.kind == "BareMetalHost"' "$file");
        if [ "$ret" == "true" ];then
            sdnMac=$(yq '.metadata.annotations."kni.io/sdnNetworkMac"' "$file")
            echo "$sdnMac"
        fi
    done
}
#
# The prep_bm_host.src file contains information
# about the provisioning interface, baremetal interface
# and external (internet facing) interface of the
# provisioning host
#
parse_prep_bm_host_src() {
    prep_src=$1
    
    check_regular_file_exists "$prep_src"
    
    # shellcheck source=/dev/null
    source "$prep_src"
    
    if [ -z "${PROV_INTF}" ]; then
        echo "PROV_INTF not set in ${prep_src}, must define PROV_INTF"
        exit 1
    fi
    prov_interface=$PROV_INTF
    
    if [ -z "${BM_INTF}" ]; then
        echo "BM_INTF not set in ${prep_src}, must define BM_INTF"
        exit 1
    fi
    bm_interface=$BM_INTF
}

if [ "$#" -lt 3 ]; then
    usage
fi

while getopts ":hm:b:s:" opt; do
    case ${opt} in
        m )
            manifest_dir=$OPTARG
        ;;
        b )
            base_dir=$OPTARG
        ;;
        s )
            prep_host_setup_src=$OPTARG
        ;;
        h )
            usage
            exit 0
        ;;
        \? )
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
        ;;
    esac
done
shift $((OPTIND -1))

manifest_dir=${manifest_dir:-./cluster}
check_directory_exists "$manifest_dir"
manifest_dir=$(realpath "$manifest_dir")

base_dir=${base_dir:-./dnsmasq}
check_directory_exists "$base_dir"
base_dir=$(realpath "$base_dir")

# get prep_host_setup.src file info
prep_host_setup_src=${prep_host_setup_src:-./prep_bm_host.src}
parse_prep_bm_host_src "$prep_host_setup_src"

subcommand=$1; shift  # Remove 'prov|bm' from the argument list
case "$subcommand" in
    # Parse options to the install sub command
    prov )
        # Process package options
        while getopts ":t:" opt; do
            case ${opt} in
                t )
                    target=$OPTARG
                ;;
                \? )
                    echo "Invalid Option: -$OPTARG" 1>&2
                    exit 1
                ;;
                #        : )
                #          echo "Invalid Option: -$OPTARG requires an argument" 1>&2
                #          exit 1
                #          ;;
            esac
        done
        shift $((OPTIND -1))
        
        gen_config_prov "$prov_interface" "$base_dir"
    ;;
    bm )
        # Need to get cluster_id and cluster_domain from install-config.yaml
        parse_install_config_yaml "$manifest_dir/install-config.yaml"
        
        gen_config_bm "$bm_interface" "$base_dir" "$cluster_id" "$cluster_domain"
    ;;
    *)
        echo "Unknown command: $command"
        usage
    ;;
esac

outdir=$(realpath "$1")
shift

command=$1
shift

case "$command" in
    prov)
        if [ "$#" -ne 1 ]; then
            usage
        fi
        
        intf="$1"
        gen_config_prov "$intf" "$outdir"
    ;;
    bm)
        if [ "$#" -ne 3 ]; then
            usage
        fi
        
        intf="$1"
        cluster_id="$2"
        cluster_domain="$3"
        gen_config_bm "$intf" "$outdir" "$cluster_id" "$cluster_domain"
    ;;
    *)
        echo "Unknown command: $command"
        usage
    ;;
esac

