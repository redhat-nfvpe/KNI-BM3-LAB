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

nthhost() {
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

regex_filename="^([-_A-Za-z0-9]+)$"
regex_pos_int="^([0-9]+$)"
regex_mac_address="^(([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}$)"

declare -A all_vars

# must have at least on optional parameter for a kind
#
declare -A manifest_check=(
    [BareMetalHost.req.metadata.name]="^(master-[012]{1}$|worker-[012]{1}$)|^(bootstrap$)"
    [BareMetalHost.opt.metadata.annotations.kni.io / sdnNetworkMac]="$regex_mac_address"
    [BareMetalHost.req.spec.bootMACAddress]="$regex_mac_address"
    [BareMetalHost.req.spec.bmc.address]="ipmi://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
    [BareMetalHost.req.spec.bmc.credentialsName]="$regex_filename"
    [Secret.req.metadata.name]="$regex_filename"
    [Secret.req.stringdata.username]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
    [Secret.req.stringdata.password]="^(([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$)"
    [install - config.req.baseDomain]="^([-_A-Za-z0-9.]+)$"
    [install - config.req.compute.0.replicas]="$regex_pos_int"
    [install - config.req.controlPlane.replicas]="$regex_pos_int"
    [install - config.req.metadata.name]="$regex_filename"
    #   [install-config.req.platform.none]="\s*\{\s*\}\s*"
    [install - config.req.pullSecret]="(.*)"
    [install - config.req.sshKey]="(.*)"
)

PROV_IP_CIDR="172.22.0.0/24"
PROV_IP_ADDR="$(nthhost $PROV_IP_CIDR 1)"
PROV_IP_IPXE_URL="$(nthhost $PROV_IP_CIDR 10): 8080" # 172.22.0.10
PROV_IP_RANGE_START=$(nthhost "$PROV_IP_CIDR" 11)    # 172.22.0.11
PROV_IP_RANGE_END=$(nthhost "$PROV_IP_CIDR" 30)      # 172.22.0.30
PROV_ETC_DIR="bm/etc/dnsmasq.d"
PROV_VAR_DIR="bm/var/run/dnsmasq"

BM_IP_CIDR="192.168.111.0/24"
BM_IP_RANGE_START=$(nthhost "$BM_IP_CIDR" 10)  # 192.168.111.10
BM_IP_RANGE_END=$(nthhost "$BM_IP_CIDR" 60)    # 192.168.111.60
BM_IP_BOOTSTRAP=$(nthhost "$BM_IP_CIDR" 10)    # 192.168.111.10
BM_IP_MASTER_0=$(nthhost "$BM_IP_CIDR" 11)     # 192.168.111.11
BM_IP_MASTER_1=$(nthhost "$BM_IP_CIDR" 12)     # 192.168.111.12
BM_IP_MASTER_2=$(nthhost "$BM_IP_CIDR" 13)     # 192.168.111.13
BM_IP_NS=$(nthhost "$BM_IP_CIDR" 1)            # 192.168.111.1
BM_IP_WORKER_START=$(nthhost "$BM_IP_CIDR" 20) # 192.168.111.20

BM_ETC_DIR="bm/etc/dnsmasq.d"
BM_VAR_DIR="bm/var/run/dnsmasq"

# Global variables
unset cluster_id
unset cluster_domain
unset prov_interface
unset bm_terface
unset ext_interface

join_by() {
    local IFS="$1"
    shift
    echo "$*"
}

check_var() {

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

    cat <<EOF >"$etc_dir/dnsmasq.conf"
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
    cid="$3"

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

parse_install_config_yaml() {
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

    printf "Parsing manifest files in %s\n" "$manifest_dir"
    for file in "$manifest_dir"/*.yaml; do
        printf "\nParsing %s\n" "$file"

        # Parse the yaml file using yq
        # The end result is an associative array, manifest_vars
        # The keys are the fields in the yaml file
        # and the values are the values in the yaml file
        # shellcheck disable=SC2016
        values=$(yq 'paths(scalars) as $p | [ ( [ $p[] | tostring ] | join(".") ) , ( getpath($p) | tojson ) ] | join(" ")' "$file")
        if [ $? -ne 0 ]; then
            printf "Error during parsing..."
            exit 1
        fi
        mapfile -t lines < <(echo "$values" | sed -e 's/^"//' -e 's/"$//' -e 's/\\"//g')
        unset manifest_vars
        declare -A manifest_vars
        for line in "${lines[@]}"; do
            # shellcheck disable=SC2206
            l=($line)
            # create the associative array
            manifest_vars[${l[0]}]=${l[1]}
            #echo "manifest_vars[${l[0]}] == ${l[1]}"
        done

        name=""
        if [[ $file =~ install-config.yaml ]]; then
            # the install-config file is not really a manifest and
            # does not have a kind: tag.
            kind="install-config"
            name="install-config"
        elif [[ ${manifest_vars[kind]} ]]; then
            # All the manifest types must have at least one entry
            # in manifest_check.  The entry can just be an optional
            # field.
            kind=${manifest_vars[kind]}
            name=${manifest_vars[metadata.name]}
        else
            printf "kind parameter missing OR of unrecognized type in file %s" "$file"
            exit 1
        fi

        recognized=false
        printf "Kind: %s\n" "$kind"
        # Loop through all entries in manifest_check
        for v in "${!manifest_check[@]}"; do
            # Split the path (i.e. bootstrap.spec.hardwareProfile ) into array
            IFS='.' read -r -a split <<<"$v"
            # manifest_check has the kind as the first component
            # do we recognize this kind?
            if [[ ${split[0]} =~ $kind ]]; then
                recognized=true
                required=false
                # manifest_check has req/opt as second component
                [[ ${split[1]} =~ req ]] && required=true
                # Reform path removing kind.req/opt
                v_vars=$(join_by "." "${split[@]:2}")
                # Now check if there is a value for this manifest_check entry
                # in the parsed manifest
                if [[ ${manifest_vars[$v_vars]} ]]; then
                    if [[ ! "${manifest_vars[$v_vars]}" =~ ${manifest_check[$v]} ]]; then
                        printf "Invalid value for \"%s\" : \"%s\" does not match %s in %s\n" "$v" "${manifest_vars[$v_vars]}" "${manifest_check[$v]}" "$file"
                        exit 1
                    fi
                    # echo " ${manifest_vars[$v_vars]} ===== ${BASH_REMATCH[1]} === ${manifest_check[$v]}"
                    # The regex contains a capture group that retrieves the value to use
                    # from the field in the yaml file
                    # Update manifest_var with the captured value.
                    manifest_vars[$v_vars]="${BASH_REMATCH[1]}"
                elif [[ "$required" =~ true ]]; then
                    # There was no value found in the manifest and the value
                    # was required.
                    printf "Missing value, %s, in %s...\n" "$v" "$file"
                    exit 1
                fi
            fi
        done

        if [[ $recognized =~ false ]]; then
            printf "File: %s contains an unrecognized kind:\n" "$file"
        fi

        # Finished the parse
        # Take all final values and place them in the all_vars
        # array for use by gen_terraform
        for v in "${!manifest_vars[@]}"; do
            # Make entries unique by prepending with manifest object name
            # Should have a uniqueness check here!
            val="$name.$v"
            if [[ ${all_vars[$val]} ]]; then
                printf "Duplicate Manifest value...\"%s\"\n" "$val"
                printf "This usually occurs when two manifests have the same metadata.name...\n"
                exit 1
            fi
            all_vars[$val]=${manifest_vars[$v]}
            printf "\tall_vars[%s] == \"%s\"\n" "$val" "${manifest_vars[$v]}"
        done
    done

    for v in "${!all_vars[@]}"; do
        echo "$v : ${all_vars[$v]}"
    done
}

gen_terraform_cluster() {

    # The keys in the following associative array 
    # specify varies to be emitted in the terraform vars file.
    # the associated value contains
    #  1. A static string value
    #  2. A string with ENV vars that have been previously defined
    #  3. A string prepended with '%' to indicate the final value is
    #     located in the all_vars array
    #  4. all_vars references may contain path.[field].field
    #     i.e. bootstrap.spec.bmc.[credentialsName].password
    #     in this instance [name].field references another manifest file
    #
    declare -A cluster_map=(
        [bootstrap_ign_file]="./ocp/bootstrap.ign"
        [master_ign_file]="./ocp/master.ign"
        [matchbox_client_cert]="./matchbox/scripts/tls/client.crt"
        [matchbox_client_key]="./matchbox/scripts/tls/client.key"
        [matchbox_trusted_ca_cert]="./matchbox/scripts/tls/ca.crt"
        [matchbox_http_endpoint]="http://${PROV_IP_ADDR}:8080"
        [matchbox_rpc_endpoint]="${PROV_IP_ADDR}:8081"
        [pxe_initrd_url]="assets/rhcos-4.1.0-x86_64-installer-initramfs.img"
        [pxe_kernel_url]="assets/rhcos-4.1.0-x86_64-installer-kernel"
        [pxe_os_image_url]="http://${PROV_IP_ADDR}:8080/assets/rhcos-4.1.0-x86_64-metal-bios.raw.gz"
        [bootstrap_public_ipv4]="${BM_IP_BOOTSTRAP}"
        [bootstrap_ipmi_host]="%bootstrap.spec.bmc.address"
        [bootstrap_ipmi_user]="%bootstrap.spec.bmc.[credentialsName].stringdata.username@"
        [bootstrap_ipmi_pass]="%bootstrap.spec.bmc.[credentialsName].stringdata.password@"
        [bootstrap_mac_address]="%bootstrap.spec.bootMACAddress"
        [nameserver]="${BM_IP_NS}"
        [cluster_id]="%install-config.metadata.name"
        [cluster_domain]="%install-config.baseDomain"
        [provisioning_interface]="${PROV_INTF}"
        [baremetal_interface]="${BM_INTF}"
        [master_count]="%install-config.controlPlane.replicas"
    )

    # Generate the cluster terraform values for the fixed
    # variables
    #
    for v in "${!cluster_map[@]}"; do
        rule=${cluster_map[$v]}
        printf "Apply map-rule: \"%s\"\n" "$rule"
        # Map rules that start with % indicate that the value for the
        mapped_val="unknown"
        if [[ $rule =~ ^\% ]]; then
            rule=${rule/#%/}
            if [[ $rule =~ \[([-_A-Za-z0-9]+)\] ]]; then
                ref_field="${BASH_REMATCH[1]}"
                [[ $rule =~ ([^\[]+).*$ ]] && ref="${BASH_REMATCH[1]}$ref_field"
                if [[ ! ${all_vars[$ref]} ]]; then
                    printf "Indirect ref in rule \"%s\" failed...\n" "$rule"
                    printf "\"%s\" does not exist...\n" "$ref"
                    exit 1
                fi
                ref="${all_vars[$ref]}"
                [[ $rule =~ [^\]]+\]([^@]+) ]] && ref_path="$ref${BASH_REMATCH[1]}"
                if [[ ! ${all_vars[$ref_path]} ]]; then
                    printf "Indirect ref in rule \"%s\" failed...\n" "$rule"
                    printf "\"%s\" does not exist...\n" "$ref_path"
                    exit 1
                fi

                if [[ $rule =~ .*@$ ]]; then
                    mapped_val=$( echo "${all_vars[$ref_path]}" | base64 -d)
                else
                    mapped_val="${all_vars[$ref_path]}"
                fi
            else
                mapped_val="${all_vars[$rule]}"
            fi
        else    
            mapped_val="$rule"
        fi
        printf "\t%s = \"%s\"\n" "$v" "$mapped_val"
    done

    # Generate the cluster terraform values for the variable number
    # of masters


    #master_nodes = [
    #  {
    #    name: "${MASTER0_NAME}",
    #    public_ipv4: "${MASTER0_IP}",
    #    ipmi_host: "${MASTER0_IPMI_HOST}",
    #    ipmi_user: "${MASTER0_IPMI_USER}",
    #    ipmi_pass: "${MASTER0_IPMI_PASS}",
    #    mac_address: "${MASTER0_MAC}"
    #  }
    #]

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

if [ "$#" -lt 1 ]; then
    usage
fi

while getopts ":hm:b:s:" opt; do
    case ${opt} in
    m)
        manifest_dir=$OPTARG
        ;;
    b)
        base_dir=$OPTARG
        ;;
    s)
        prep_host_setup_src=$OPTARG
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
shift $((OPTIND - 1))

manifest_dir=${manifest_dir:-./cluster}
check_directory_exists "$manifest_dir"
manifest_dir=$(realpath "$manifest_dir")

base_dir=${base_dir:-./dnsmasq}
check_directory_exists "$base_dir"
base_dir=$(realpath "$base_dir")

# get prep_host_setup.src file info
prep_host_setup_src=${prep_host_setup_src:-$manifest_dir/prep_bm_host.src}
parse_prep_bm_host_src "$prep_host_setup_src"

command=$1
shift # Remove 'prov|bm' from the argument list
case "$command" in
# Parse options to the install sub command
prov)
    # Process package options
    while getopts ":t:" opt; do
        case ${opt} in
        t)
            target=$OPTARG
            ;;
        \?)
            echo "Invalid Option: -$OPTARG" 1>&2
            exit 1
            ;;
            #        : )
            #          echo "Invalid Option: -$OPTARG requires an argument" 1>&2
            #          exit 1
            #          ;;
        esac
    done
    shift $((OPTIND - 1))

    gen_config_prov "$prov_interface" "$base_dir"
    ;;
bm)
    # Need to get cluster_id and cluster_domain from install-config.yaml
    parse_install_config_yaml "$manifest_dir/install-config.yaml"

    gen_config_bm "$bm_interface" "$base_dir" "$cluster_id" "$cluster_domain"
    ;;
manifests)
    parse_install_config_yaml "$manifest_dir/install-config.yaml"
    parse_manifests "$manifest_dir"
    echo "====="
    gen_terraform_cluster
    ;;
*)
    echo "Unknown command: $command"
    usage
    ;;
esac
