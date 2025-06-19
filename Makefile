.PHONY: init build-nixos build-k3d test-nixos test-k3d clean

init:
	mkdir -p manifests nix/{base,k3d} scripts/{build,provision,test} output-nixos-base output-nixos-k3d
	[ -f manifests/image_catalog.json ] || echo '[]' > manifests/image_catalog.json
build-nixos:
	@echo "Building NixOS base image"
	chmod +x scripts/build/create_nixos_base.sh
	scripts/build/create_nixos_base.sh
	
	@# Update catalog
	BUILD_ID=$$(ls output-nixos-base/*.manifest.json 2>/dev/null | sort | tail -1 | xargs cat 2>/dev/null | jq -r '.build_id' 2>/dev/null || echo "$$(date +%Y%m%d%H%M%S)"); \
	if [ -f "output-nixos-base/nixos-base-$${BUILD_ID}.manifest.json" ]; then \
		jq -s '.[0] + [.[1]]' manifests/image_catalog.json "output-nixos-base/nixos-base-$${BUILD_ID}.manifest.json" > manifests/image_catalog.json.new; \
		mv manifests/image_catalog.json.new manifests/image_catalog.json; \
	fi

build-k3d: 
	@echo "Building K3d cluster image"
	chmod +x scripts/build/create_k3d_cluster.sh
	scripts/build/create_k3d_cluster.sh output-nixos-base/nixos-base-latest.tar.gz
	
	@# Update catalog
	BUILD_ID=$$(ls output-nixos-k3d/*.manifest.json 2>/dev/null | sort | tail -1 | xargs cat 2>/dev/null | jq -r '.build_id' 2>/dev/null || echo "$$(date +%Y%m%d%H%M%S)"); \
	if [ -f "output-nixos-k3d/nixos-k3d-$${BUILD_ID}.manifest.json" ]; then \
		jq -s '.[0] + [.[1]]' manifests/image_catalog.json "output-nixos-k3d/nixos-k3d-$${BUILD_ID}.manifest.json" > manifests/image_catalog.json.new; \
		mv manifests/image_catalog.json.new manifests/image_catalog.json; \
	fi
test-nixos:
	@echo "Testing NixOS base image"
	orb import output-nixos-base/nixos-base-latest.tar.gz test-nixos
	orb start test-nixos
	@echo "Waiting for VM to be ready..."
	@sleep 10
	orb ssh test-nixos "nixos-version && echo 'NixOS test passed!'"
	orb stop test-nixos
	orb rm -f test-nixos

test-k3d:
	@echo "Testing K3d cluster image"
	orb import output-nixos-k3d/nixos-k3d-latest.tar.gz test-k3d
	orb start test-k3d
	@echo "Waiting for VM to be ready..."
	@sleep 30
	orb ssh test-k3d "systemctl status services.k3d-cluster && kubectl get nodes && echo 'K3d test passed!'"
	orb stop test-k3d
	orb rm -f test-k3d

deploy-test:
	@echo "Deploying K3d cluster for testing"
	orb import output-nixos-k3d/nixos-k3d-latest.tar.gz helios-k3d-test
	orb start helios-k3d-test
	@echo "K3d cluster deployed. Access Kubernetes with:"
	@echo "orb ssh helios-k3d-test -c 'kubectl get nodes'"

clean:
	@echo "Cleaning up..."
	for vm in $$(orb list 2>/dev/null | grep -E 'nixos-|test-|helios-'); do \
		echo "Removing VM: $$vm"; \
		orb rm -f "$$vm"; \
	done
