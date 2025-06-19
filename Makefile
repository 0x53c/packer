.PHONY: init build-coreos build-k3d test-coreos test-k3d clean

init:
	mkdir -p manifests
	[ -f manifests/image_catalog.json ] || echo '[]' > manifests/image_catalog.json
	brew install orbstack jq qemu butane coreutils || true

build-coreos:
	@echo "Building Fedora CoreOS base image"
	chmod +x scripts/build/create_coreos_base.sh
	scripts/build/create_coreos_base.sh
	
	@# Update catalog
	BUILD_ID=$$(ls output-fedora-coreos/*.manifest.json | sort | tail -1 | xargs cat | jq -r '.build_id'); \
	MANIFEST_FILE="output-fedora-coreos/fedora-coreos-$${BUILD_ID}.manifest.json"; \
	jq -s '.[0] + [.[1]]' manifests/image_catalog.json "$$MANIFEST_FILE" > manifests/image_catalog.json.new; \
	mv manifests/image_catalog.json.new manifests/image_catalog.json
	
	@# Create latest symlink
	cd output-fedora-coreos; \
	BUILD_ID=$$(ls *.manifest.json | sort | tail -1 | xargs cat | jq -r '.build_id'); \
	ln -sf "fedora-coreos-$${BUILD_ID}.tar.gz" "fedora-coreos-latest.tar.gz"

build-k3d: 
	@echo "Building K3d cluster image"
	chmod +x scripts/build/create_k3d_cluster.sh
	scripts/build/create_k3d_cluster.sh output-fedora-coreos/fedora-coreos-latest.tar.gz
	
	@# Update catalog
	BUILD_ID=$$(ls output-k3d-cluster/*.manifest.json | sort | tail -1 | xargs cat | jq -r '.build_id'); \
	MANIFEST_FILE="output-k3d-cluster/k3d-cluster-$${BUILD_ID}.manifest.json"; \
	jq -s '.[0] + [.[1]]' manifests/image_catalog.json "$$MANIFEST_FILE" > manifests/image_catalog.json.new; \
	mv manifests/image_catalog.json.new manifests/image_catalog.json
	
	@# Create latest symlink
	cd output-k3d-cluster; \
	BUILD_ID=$$(ls *.manifest.json | sort | tail -1 | xargs cat | jq -r '.build_id'); \
	ln -sf "k3d-cluster-$${BUILD_ID}.tar.gz" "k3d-cluster-latest.tar.gz"

test-coreos:
	@echo "Testing CoreOS base image"
	chmod +x tests/test/validate_coreos.sh
	tests/test/validate_coreos.sh

test-k3d:
	@echo "Testing K3d cluster image"
	chmod +x tests/test/validate_k3d.sh
	tests/test/validate_k3d.sh

deploy-test:
	@echo "Deploying K3d cluster for testing"
	orb machine import output-k3d-cluster/k3d-cluster-latest.tar.gz helios-k3d-test
	orb machine start helios-k3d-test
	@echo "K3d cluster deployed. Access Kubernetes with:"
	@echo "orb machine ssh helios-k3d-test -c 'kubectl get nodes'"

clean:
	@echo "Cleaning up..."
	for vm in $$(orb machine list | grep -E 'fedora-coreos|k3d-cluster'); do \
		echo "Removing VM: $$vm"; \
		orb machine rm -f $$vm; \
	done
