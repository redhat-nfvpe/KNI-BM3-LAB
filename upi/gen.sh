#!/bin/bash

# This script generates configuration files for the UPI install project.
# The first set of scripts are related to dns and haproxy.  The second
# set of files are for terraform
#
# The UPI install project employs two instances of dnsmasq.  One instance provides
# dhcp/pxe boot for the provisioning network.  The second instance provides dhcp
# and DNS for the baremetal network.  Dnsmasq is run as a container using podman.
# The configuration files for both dnsmasqs are located as should below.
#
#── /root_path/
#|
#├── dnsmasq
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
#|
#├── terraform
#|   ├── cluster
#|   │   └── terraform.tfvars
#|   └── workers
#|       └── terraform.tfvars
#|
#├── cluster
#│   ├── bootstrap-creds.yaml
#│   ├── bootstrap.yaml
#│   ├── ha-lab-ipmi-creds.yaml
#│   ├── install-config.yaml
#│   ├── master-0.yaml
#│   ├── prep_bm_host.src
#│   ├── worker-0.yaml
#│   └── worker-1.yaml

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

     $(basename "$0") [common_options] manifests
        Generate config files for terraform

    common_options
        -m manifest_dir -- Location of manifest files that describe the deployment.
            Requires: install-config.yaml, bootstrap.yaml, master-0.yaml, [masters/workers...]
            Defaults to ./cluster/
        -b base_dir -- Where to put the output [defaults to ./dnsmasq/...]
        -s [path/]prep_host_setup.src -- Location of the config file for host prep
            Default to ./prep_host_setup.src
        -t terraform_dir -- Location to place terraform output.  Defaults to ./terraform
EOM
    exit 0
}

gen_terraform_cluster() {
    local out_dir="$1"

    local cluster_dir="$out_dir/cluster"
    mkdir -p "$cluster_dir"
    local ofile="$out_dir/cluster/terraform.tfvars"

    mapfile -d '' sorted < <(printf '%s\0' "${!CLUSTER_MAP[@]}" | sort -z)

    printf "Generating...%s]\n" "$ofile"

    printf "// AUTOMATICALLY GENERATED -- Do not edit\n" | sudo tee "$ofile"
    
    for key in "${sorted[@]}"; do
        printf "%s = \"%s\"\n" "$key" "${FINAL_VALS[$key]}" | sudo tee -a "$ofile"
        #printf '%s matches with %s\n' "$key" "${CLUSTER_MAP[$key]}"
    done
    # Generate the cluster terraform values for the variable number
    # of masters

    # TODO ... generate the following

    printf "master_nodes = [\n" | sudo tee -a "$ofile"
    printf "  {\n" | sudo tee -a "$ofile"

    num_masters="${FINAL_VALS[master_count]}"
    for ((i = 0; i < num_masters; i++)); do
        m="master-$i"
        printf "    name: \"%s\"\n" "${FINAL_VALS[$m.metadata.name]}" | sudo tee -a "$ofile"
        printf "    public_ipv4: \"%s\"\n" "$(get_master_bm_ip $i)" | sudo tee -a "$ofile"
        printf "    ipmi_host: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.address]}" | sudo tee -a "$ofile"
        printf "    ipmi_user: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.user]}" | sudo tee -a "$ofile"
        printf "    ipmi_pass: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.password]}" | sudo tee -a "$ofile"
        printf "    mac_address: \"%s\"\n" "${FINAL_VALS[$m.spec.bootMACAddress]}" | sudo tee -a "$ofile"

    done

    printf "  }\n" | sudo tee -a "$ofile"
    printf "]\n" | sudo tee -a "$ofile"

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

gen_terraform_workers() {
    local out_dir="$1"

    local cluster_dir="$out_dir/cluster"
    mkdir -p "$cluster_dir"
    local ofile="$out_dir/workers/terraform.tfvars"

    mapfile -d '' sorted < <(printf '%s\0' "${!CLUSTER_MAP[@]}" | sort -z)

    printf "Generating...%s]\n" "$ofile"

    printf "// AUTOMATICALLY GENERATED -- Do not edit\n" | sudo tee "$ofile"

    for key in "${sorted[@]}"; do
        printf "%s = \"%s\"\n" "$key" "${FINAL_VALS[$key]}" | sudo tee -a "$ofile"
        #printf '%s matches with %s\n' "$key" "${CLUSTER_MAP[$key]}"
    done
    # Generate the cluster terraform values for the variable number
    # of masters

    # TODO ... generate the following

    printf "master_nodes = [\n" | sudo tee -a "$ofile"
    printf "  {\n" | sudo tee -a "$ofile"

    num_masters="${FINAL_VALS[master_count]}"
    for ((i = 0; i < num_masters; i++)); do
        m="master-$i"
        printf "    name: \"%s\"\n" "${FINAL_VALS[$m.metadata.name]}" | sudo tee -a "$ofile"
        printf "    public_ipv4: \"%s\"\n" "$(get_master_bm_ip $i)" | sudo tee -a "$ofile"
        printf "    ipmi_host: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.address]}" | sudo tee -a "$ofile"
        printf "    ipmi_user: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.user]}" | sudo tee -a "$ofile"
        printf "    ipmi_pass: \"%s\"\n" "${FINAL_VALS[$m.spec.bmc.password]}" | sudo tee -a "$ofile"
        printf "    mac_address: \"%s\"\n" "${FINAL_VALS[$m.spec.bootMACAddress]}" | sudo tee -a "$ofile"

    done

    printf "  }\n" | sudo tee -a "$ofile"
    printf "]\n" | sudo tee -a "$ofile"

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

if [ "$#" -lt 1 ]; then
    usage
fi

VERBOSE="false"
export VERBOSE

while getopts ":hm:b:s:t:v" opt; do
    echo "getopts"
    case ${opt} in
    m)
        manifest_dir=$OPTARG
        ;;
    t)
        terraform_dir=$OPTARG
        ;;
    b)
        base_dir=$OPTARG
        ;;
    s)
        prep_host_setup_src=$OPTARG
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
shift $((OPTIND - 1))

# shellcheck disable=SC1091
source "common.sh"

# shellcheck disable=SC1091
source "scripts/network_conf.sh"

# shellcheck disable=SC1091
source "scripts/manifest_check.sh"
# shellcheck disable=SC1091
source "scripts/utils.sh"

if [[ -z "$PROJECT_DIR" ]]; then
    usage
    exit 1
fi
# shellcheck disable=SC1090
source "$PROJECT_DIR/scripts/cluster_map.sh"

manifest_dir=${manifest_dir:-$PROJECT_DIR/cluster}
check_directory_exists "$manifest_dir"
manifest_dir=$(realpath "$manifest_dir")

terraform_dir=${terraform_dir:-$PROJECT_DIR/terraform}
terraform_dir=$(realpath "$terraform_dir")

base_dir=${base_dir:-$PROJECT_DIR/dnsmasq}
check_directory_exists "$base_dir"
base_dir=$(realpath "$base_dir")

# get prep_host_setup.src file info
prep_host_setup_src=${prep_host_setup_src:-$manifest_dir/prep_bm_host.src}
parse_prep_bm_host_src "$prep_host_setup_src"

parse_manifests "$manifest_dir"

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

    "$PROJECT_DIR"/scripts/gen_config_prov.sh
    ;;
bm)
    "$PROJECT_DIR"/scripts/gen_config_bm.sh
    ;;

manifests)
    map_cluster_vars
    gen_terraform_cluster "$terraform_dir"
    ;;
*)
    echo "Unknown command: $command"
    usage
    ;;
esac