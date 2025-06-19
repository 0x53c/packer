#!/bin/bash

set -e

VM_NAME="nixos"
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

log_info "Starting build for NixOS base image"

if orb list 2>/dev/null | grep -q "$VM_NAME"; then
  log_info "Removing existing VM: $VM_NAME"
  orb rm -f "$VM_NAME"
fi

mkdir -p "output-$VM_NAME"

log_info "Creating NixOS VM in OrbStack"
orb create "$VM_NAME" nixos

log_info "Starting VM"
orb start "$VM_NAME"

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

NIXOS_VERSION=$(orb ssh "$VM_NAME" "nixos-version")
log_info "Detected NixOS version: $NIXOS_VERSION"
log_info "Copying NixOS configuration"
mkdir -p nix/base
cat > nix/base/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "helios-nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "America/Chicago";
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    initialPassword = "nixos";
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here if needed
    ];
  };

  security.sudo.wheelNeedsPassword = false;
  virtualisation.docker.enable = true;

  boot.kernelModules = [ "br_netfilter" ];
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward" = 1;
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    jq
    htop
    docker-compose
    kubectl
  ];

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "no";
  system.autoUpgrade.enable = false;
  system.stateVersion = "23.11"; # Don't change this!
}
EOF

orb cp nix/base/configuration.nix "$VM_NAME:/tmp/configuration.nix"
orb ssh "$VM_NAME" "sudo cp /tmp/configuration.nix /etc/nixos/configuration.nix"

log_info "Applying NixOS configuration"
orb ssh "$VM_NAME" "sudo nixos-rebuild switch"

log_info "Creating build metadata"
cat > "output-$VM_NAME/metadata-$VM_NAME.json" <<EOF
{
  "name": "$VM_NAME",
  "base_distro": "nixos",
  "version": "$NIXOS_VERSION",
  "build_id": "$BUILD_ID",
  "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "build_by": "$(whoami)@$(hostname)"
}
EOF

log_info "Copying metadata to VM"
orb cp "output-$VM_NAME/metadata-$VM_NAME.json" "$VM_NAME:/tmp/helios-image-metadata.json"
orb ssh "$VM_NAME" "sudo mkdir -p /etc && sudo mv /tmp/helios-image-metadata.json /etc/helios-image-metadata.json"

log_info "Exporting VM image"
orb stop "$VM_NAME"
orb export "$VM_NAME" "output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz"

log_info "Base image created: output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz"

jq -n \
  --arg name "$VM_NAME" \
  --arg type "base" \
  --arg path "output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz" \
  --arg build_id "$BUILD_ID" \
  --arg version "$NIXOS_VERSION" \
  --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{name: $name, type: $type, path: $path, build_id: $build_id, version: $version, created: $created}' \
  > "output-$VM_NAME/$VM_NAME-$BUILD_ID.manifest.json"

cd "output-$VM_NAME" && ln -sf "$VM_NAME-$BUILD_ID.tar.gz" "$VM_NAME-latest.tar.gz" && cd -

log_success "Build completed successfully"
