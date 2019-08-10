manifests := cluster/*.yaml cluster/*.src

dnsmasq_dir = ./dnsmasq
terraform_dir = ./terraform
coredns_dir = ./coredns

dnsmasq_prov_conf := $(dnsmasq_dir)/prov/etc/dnsmasq.d/dnsmasq.conf
dnsmasq_bm_conf := dnsmasq/bm/etc/dnsmasq.d/dnsmasq.conf
dnsmasq_conf := $(dnsmasq_bm_conf) $(dnsmasq_prov_conf)
coredns_conf := coredns/Corefile
terraform := terraform/cluster/terraform.tfvars terraform/workers/terraform.tfvars 

all: $(dnsmasq_conf) $(coredns_conf) $(terraform)


dnsmasq_conf: $(dnsmasq_prov_conf) $(dnsmasq_bm_conf) $(coredns_conf)
 
$(dnsmasq_prov_conf): $(manifests)
	./scripts/gen_config_prov.sh

$(dnsmasq_bm_conf): $(manifests)
	./scripts/gen_config_bm.sh bm

$(coredns_conf): $(manifests)
	./scripts/gen_coredns.sh

$(terraform): $(manifests)
	./gen_terraform.sh all

cluster/manifest_vals.sh: $(manifests)
	./scripts/parse_manifests.sh

clean:
	rm -f ./cluster/manifest_vals.sh
	rm -rf $(coredns_dir) $(terraform_dir) $(dnsmasq_dir)
