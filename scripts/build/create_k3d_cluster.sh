#!/bin/bash
# scripts/build/create_k3d_cluster.sh

set -e

VM_NAME="nixos-k3d"
BASE_IMAGE_PATH=$1  # Path to NixOS base image
BUILD_ID=$(date +%Y%m%d%H%M%S)

# Log functions
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

log_info "Starting K3d cluster image build using base image $BASE_IMAGE_PATH"

# Check if VM already exists and remove it
if orb list 2>/dev/null | grep -q "$VM_NAME"; then
  log_info "Removing existing VM: $VM_NAME"
  orb rm -f "$VM_NAME"
fi

# Create output directory
mkdir -p "output-$VM_NAME"

# Import base image
log_info "Importing base NixOS image"
orb import "$BASE_IMAGE_PATH" "$VM_NAME"

# Start VM
log_info "Starting VM"
orb start "$VM_NAME"

# Wait for VM to be ready
log_info "Waiting for VM to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if orb ssh "$VM_NAME" "echo 'VM is ready'" &>/dev/null; then
    log_success "VM $VM_NAME is ready"
    break
  fi
  
  ATTEMPT=$((ATTEMPT + 1))
  log_info "Still waiting... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
  sleep 5
  
  if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    log_error "Timed out waiting for VM to be ready"
    exit 1
  fi
done

# Copy K3d NixOS configurations
log_info "Copying K3d NixOS configurations"
mkdir -p nix/k3d
cat > nix/k3d/k3d-setup.nix <<EOF
$(cat nix/k3d/k3d-setup.nix 2>/dev/null || cat <<'INNEREOF'
# nix/k3d/k3d-setup.nix
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.k3d;
in {
  options.services.k3d = {
    enable = mkEnableOption "k3d Kubernetes cluster";
    
    clusterName = mkOption {
      type = types.str;
      default = "helios-cluster";
      description = "Name of the k3d cluster";
    };
    
    servers = mkOption {
      type = types.int;
      default = 1;
      description = "Number of server nodes";
    };
    
    agents = mkOption {
      type = types.int;
      default = 2;
      description = "Number of agent nodes";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.k3d-cluster = {
      description = "K3d Kubernetes Cluster";
      wantedBy = [ "multi-user.target" ];
      requires = [ "docker.service" ];
      after = [ "docker.service" "network.target" ];
      
      path = [ pkgs.k3d pkgs.docker pkgs.kubectl ];
      
      script = ''
        # Check if cluster exists
        if ! k3d cluster list | grep -q "${cfg.clusterName}"; then
          echo "Creating k3d cluster ${cfg.clusterName}"
          k3d cluster create ${cfg.clusterName} \
            --servers ${toString cfg.servers} \
            --agents ${toString cfg.agents} \
            --port "80:80@loadbalancer" \
            --port "443:443@loadbalancer" \
            --k3s-arg "--disable=traefik@server:0"
        else
          echo "Starting existing cluster ${cfg.clusterName}"
          k3d cluster start ${cfg.clusterName}
        fi
        
        # Wait for the cluster to be ready
        echo "Waiting for cluster to be ready..."
        until kubectl get nodes | grep -q " Ready "; do
          sleep 5
        done
        
        # Set up kubeconfig for the nixos user
        mkdir -p /home/nixos/.kube
        k3d kubeconfig get ${cfg.clusterName} > /home/nixos/.kube/config
        chmod 600 /home/nixos/.kube/config
        chown nixos:users /home/nixos/.kube/config
        
        # Install MetalLB if not already installed
        if ! kubectl get namespace metallb-system >/dev/null 2>&1; then
          echo "Installing MetalLB"
          kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml
          
          # Wait for MetalLB to be ready
          until kubectl get pods -n metallb-system | grep -q "Running"; do
            sleep 5
          done
          
          # Create a MetalLB address pool
          cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.240-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
EOF
        fi
        
        echo "K3d cluster is ready"
      '';
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
INNEREOF
)
EOF

cat > nix/k3d/configuration.nix <<EOF
$(cat nix/k3d/configuration.nix 2>/dev/null || cat <<'INNEREOF'
# nix/k3d/configuration.nix
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./k3d-setup.nix
  ];

  # Base configuration from nixos-base
  networking.hostName = "helios-k3d";
  networking.networkmanager.enable = true;

  # Set your time zone
  time.timeZone = "America/Chicago";

  # User account
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here if needed
    ];
  };

  # Allow sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Enable Docker
  virtualisation.docker.enable = true;

  # Enable K3d dependencies
  boot.kernelModules = [ "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  # Expanded packages for K3d
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    jq
    htop
    docker-compose
    kubectl
    k3d
    kubernetes-helm
    k9s
  ];

  # Enable OpenSSH
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";

  # Enable K3d service
  services.k3d = {
    enable = true;
    clusterName = "helios-cluster";
    servers = 1;
    agents = 2;
  };

  # This value determines the NixOS release with which your system is to be compatible
  system.stateVersion = "23.11";
}
INNEREOF
)
EOF

# Copy configurations to VM
log_info "Copying NixOS configurations to VM"
orb cp nix/k3d/k3d-setup.nix "$VM_NAME:/tmp/k3d-setup.nix"
orb cp nix/k3d/configuration.nix "$VM_NAME:/tmp/configuration.nix"
orb ssh "$VM_NAME" "sudo cp /tmp/k3d-setup.nix /etc/nixos/k3d-setup.nix && sudo cp /tmp/configuration.nix /etc/nixos/configuration.nix"

# Apply configuration
log_info "Applying NixOS configuration with K3d setup"
orb ssh "$VM_NAME" "sudo nixos-rebuild switch"

# Get NixOS version
NIXOS_VERSION=$(orb ssh "$VM_NAME" "nixos-version")
log_info "Detected NixOS version: $NIXOS_VERSION"

# Update image metadata
log_info "Updating image metadata"
BASE_METADATA=$(orb ssh "$VM_NAME" "cat /etc/helios-image-metadata.json" 2>/dev/null || echo "{}")
BASE_BUILD_ID=$(echo "$BASE_METADATA" | jq -r '.build_id // "unknown"')

cat > "output-$VM_NAME/metadata-$VM_NAME.json" <<EOF
{
  "name": "$VM_NAME",
  "base_distro": "nixos",
  "type": "application",
  "app_type": "k3d",
  "version": "$NIXOS_VERSION",
  "build_id": "$BUILD_ID",
  "parent_build_id": "$BASE_BUILD_ID",
  "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "build_by": "$(whoami)@$(hostname)"
}
EOF

# Copy metadata into VM
log_info "Copying updated metadata to VM"
orb cp "output-$VM_NAME/metadata-$VM_NAME.json" "$VM_NAME:/tmp/helios-image-metadata.json"
orb ssh "$VM_NAME" "sudo mkdir -p /etc && sudo mv /tmp/helios-image-metadata.json /etc/helios-image-metadata.json"

# Run validation
log_info "Validating K3d cluster"
orb ssh "$VM_NAME" "systemctl status services.k3d-cluster"
if [ $? -ne 0 ]; then
  log_error "K3d cluster service not running properly"
  exit 1
fi

# Stop VM and export image
log_info "Exporting VM image"
orb stop "$VM_NAME"
orb export "$VM_NAME" "output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz"

log_info "K3d cluster image created: output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz"

# Create image manifest entry
jq -n \
  --arg name "$VM_NAME" \
  --arg type "application" \
  --arg app_type "k3d" \
  --arg path "output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz" \
  --arg build_id "$BUILD_ID" \
  --arg version "$NIXOS_VERSION" \
  --arg parent_build_id "$BASE_BUILD_ID" \
  --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{name: $name, type: $type, app_type: $app_type, path: $path, build_id: $build_id, version: $version, parent_build_id: $parent_build_id, created: $created}' \
  > "output-$VM_NAME/$VM_NAME-$BUILD_ID.manifest.json"

# Create latest symlink
cd "output-$VM_NAME" && ln -sf "$VM_NAME-$BUILD_ID.tar.gz" "$VM_NAME-latest.tar.gz" && cd -

log_success "Build completed successfully"
