manifests := cluster/*.yaml cluster/*.src

dnsmasq_dir = ./dnsmasq
terraform_dir = ./terraform
coredns_dir = ./coredns
haproxy_dir = ./haproxy_dir
openshift_dir = ./ocp

dnsmasq_prov_conf := $(dnsmasq_dir)/prov/etc/dnsmasq.d/dnsmasq.conf
dnsmasq_bm_conf := $(dnsmasq_dir)/bm/etc/dnsmasq.d/dnsmasq.conf
haproxy_conf := $(haproxy_dir)/haproxy.conf
dnsmasq_conf := $(dnsmasq_bm_conf) $(dnsmasq_prov_conf)
coredns_conf := $(coredns_dir)/Corefile
terraform := $(terraform_dir)/cluster/terraform.tfvars $(terraform_dir)/workers/terraform.tfvars 

all: $(dnsmasq_conf) $(coredns_conf) $(terraform) $(haproxy_conf)

dnsmasq_conf: $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)
 
$(dnsmasq_prov_conf): $(manifests)
	./scripts/gen_config_prov.sh

$(dnsmasq_bm_conf): $(manifests)
	./scripts/gen_config_bm.sh bm

$(haproxy_conf): $(manifests)
	./scripts/gen_haproxy.sh build

$(coredns_conf): $(manifests)
	./scripts/gen_coredns.sh

terraform: $(terraform)

$(terraform): $(manifests) ./scripts/cluster_map.sh ./scripts/network_conf.sh
	./gen_terraform.sh all

cluster/manifest_vals.sh: $(manifests)
	./scripts/parse_manifests.sh

clean:
	rm -f ./cluster/manifest_vals.sh
	rm -rf $(coredns_dir) $(terraform_dir) $(dnsmasq_dir) $(haproxy_dir) $(openshift_dir)
