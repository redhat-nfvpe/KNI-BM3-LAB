#!/bin/bash

DEFAULT_INITRD="assets/rhcos-4.1.0-x86_64-installer-initramfs.img"
DEFAULT_KERNEL="assets/rhcos-4.1.0-x86_64-installer-kernel"

declare -A CLUSTER_MAP=(
    [bootstrap_ign_file]="./ocp/bootstrap.ign"
    [master_ign_file]="./ocp/master.ign"
    [matchbox_client_cert]="./matchbox/scripts/tls/client.crt"
    [matchbox_client_key]="./matchbox/scripts/tls/client.key"
    [matchbox_trusted_ca_cert]="./matchbox/scripts/tls/ca.crt"
    [matchbox_http_endpoint]="http://${PROV_IP_ADDR}:8080"
    [matchbox_rpc_endpoint]="${PROV_IP_ADDR}:8081"
#  Should add & to indicate that the following field is relative to the current manifest / object
#  Also, | is used as a default value if the annotation is not set
#    [pxe_initrd_url]="&metadata.annotations.kni.io/kernel|$DEFAULT_INITRD"
    [pxe_initrd_url]="$DEFAULT_INITRD"
    [pxe_kernel_url]="$DEFAULT_KERNEL"
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

    [master-0.metadata.name]="%master-0.metadata.name"
    [master-0.spec.bmc.address]="%master-0.spec.bmc.address"
    [master-0.spec.bmc.address]="%master-0.spec.bmc.address"
    [master-0.spec.bmc.user]="%master-0.spec.bmc.[credentialsName].stringdata.username@"
    [master-0.spec.bmc.password]="%master-0.spec.bmc.[credentialsName].stringdata.password@"
    [master-0.spec.bootMACAddress]="%master-0.spec.bootMACAddress"
)

export CLUSTER_MAP