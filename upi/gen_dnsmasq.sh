#!/bin/bash

usage() {
    cat <<EOM
    Usage:
    $(basename "$0") prov|bm interface
   
    prov|bm   -- prov,  generate for the provisioning network.
                 bm, generate for the baremetall network.  
    interface -- Interface for the provisioning network.
EOM
    exit 0
}

gen_config_prov() {
    intf=$1
    
cat <<EOF > ./dnsmasq.conf
# This config file is intended for use with a container instance of dnsmasq

echo "The container should be run as follows with the generated dnsmasq.conf file"
echo "located in ./$DNSMASQ_REPO_DIR/$DNSMASQ_ETC_DIR"
echo ""
echo "# podman run -d --name dnsmasq-prov --net=host -v ./$DNSMASQ_REPO_DIR/$DNSMASQ_RUN_DIR:/var/run/dnsmasq:Z \\"
echo "#  -v ./$DNSMASQ_REPO_DIR/$DNSMASQ_ETC_DIR:/etc/dnsmasq.d:Z \\"
echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"

port=0 # do not activate nameserver
interface=$intf
bind-interfaces

dhcp-range=172.22.0.11,172.22.0.30,30m

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
dhcp-boot=tag:ipxe,http://172.22.0.10:8080/boot.ipxe

# Enable dnsmasq's built-in TFTP server
enable-tftp

# Set the root directory for files available via FTP.
tftp-root=/var/lib/tftpboot

tftp-no-blocksize

dhcp-boot=pxelinux.0

EOF
}

gen_config_bm() {
    intf="$1"

    cat <<EOF > ./dnsmasq.conf
# This config file is intended for use with a container instance of dnsmasq

echo "The container should be run as follows with the generated dnsmasq.conf file"
echo "located in ./$DNSMASQ_REPO_DIR/$DNSMASQ_ETC_DIR"
echo ""
echo "# podman run -d --name dnsmasq-bm --net=host -v ./$DNSMASQ_REPO_DIR/$DNSMASQ_RUN_DIR:/var/run/dnsmasq:Z \\"
echo "#  -v ./$DNSMASQ_REPO_DIR/$DNSMASQ_ETC_DIR:/etc/dnsmasq.d:Z \\"
echo "#  --expose=53 --expose=53/udp --expose=67 --expose=67/udp --expose=69 --expose=69/udp \\"
echo "#  --cap-add=NET_ADMIN quay.io/poseidon/dnsmasq --conf-file=/etc/dnsmasq.d/dnsmasq.conf -u root -d -q"

port=0
interface=$intf
bind-interfaces

strict-order
except-interface=lo

dhcp-range=192.168.111.10,192.168.111.60,30m
#default gateway
dhcp-option=3,192.168.111.1
#dns server
dhcp-option=6,192.168.111.1

log-queries
log-dhcp

dhcp-no-override
dhcp-authoritative
dhcp-hostsfile=/etc/dnsmasq.d/dnsmasq.hostsfile

dhcp-leasefile=/var/run/dnsmasq/dnsmasq.leasefile
log-facility=/var/run/dnsmasq/dnsmasq.log

EOF
}

if [ "$#" -ne 2 ]; then
    usage
fi

COMMAND=$1
shift

DNSMASQ_RUN_DIR="var/run/dnsmasq"
DNSMASQ_ETC_DIR="etc/dnsmasq.d"

case "$COMMAND" in
    prov)
        DNSMASQ_REPO_DIR="dnsmasq/prov"
        gen_config_prov "$1"
    ;;
    bm)
        DNSMASQ_REPO_DIR="dnsmasq/bm"
        gen_config_bm "$1"
    ;;
    *)
        echo "Unknown command: ${COMMAND}"
        usage
    ;;
esac

