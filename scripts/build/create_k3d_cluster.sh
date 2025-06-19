#!/bin/bash

set -e

K3D_VM_NAME="k3d-cluster"
BASE_IMAGE_PATH=$1
BUILD_ID=$(date +%Y%m%d%H%M%S)
K3D_VERSION="5.6.0"

source "$(dirname "$0")/../common/functions.sh"

log_info "Starting K3d cluster image build using base image $BASE_IMAGE_PATH"

if orb machine list | grep -q "$K3D_VM_NAME"; then
  log_info "Removing existing VM: $K3D_VM_NAME"
  orb machine rm -f "$K3D_VM_NAME"
fi

log_info "Importing base CoreOS image"
orb machine import "$BASE_IMAGE_PATH" "$K3D_VM_NAME"

log_info "Starting VM"
orb machine start "$K3D_VM_NAME"

wait_for_vm "$K3D_VM_NAME"

log_info "Installing K3d and bootstrapping cluster"
orb machine ssh "$K3D_VM_NAME" "$(cat $(dirname "$0")/../provision/k3d_bootstrap.sh)"

log_info "Updating image metadata"
orb machine ssh "$K3D_VM_NAME" "sudo sed -i 's/\"name\": \"fedora-coreos\"/\"name\": \"k3d-cluster\"/' /etc/helios-image-metadata.json"
orb machine ssh "$K3D_VM_NAME" "sudo sed -i 's/\"type\": \"base\"/\"type\": \"application\"/' /etc/helios-image-metadata.json"
orb machine ssh "$K3D_VM_NAME" "sudo jq '.app_type = \"k3d\" | .app_build_id = \"$BUILD_ID\" | .k3d_version = \"$K3D_VERSION\"' /etc/helios-image-metadata.json > /tmp/metadata.json && sudo mv /tmp/metadata.json /etc/helios-image-metadata.json"

log_info "Validating K3d cluster"
orb machine ssh "$K3D_VM_NAME" "$(cat $(dirname "$0")/../test/validate_k3d.sh)"
if [ $? -ne 0 ]; then
  log_error "K3d cluster validation failed"
  exit 1
fi

log_info "Exporting K3d cluster VM image"
orb machine stop "$K3D_VM_NAME"
mkdir -p "output-$K3D_VM_NAME"
orb machine export "$K3D_VM_NAME" "output-$K3D_VM_NAME/$K3D_VM_NAME-$BUILD_ID.tar.gz"

log_info "K3d cluster image created: output-$K3D_VM_NAME/$K3D_VM_NAME-$BUILD_ID.tar.gz"

jq -n \
  --arg name "$K3D_VM_NAME" \
  --arg type "application" \
  --arg app_type "k3d" \
  --arg path "output-$K3D_VM_NAME/$K3D_VM_NAME-$BUILD_ID.tar.gz" \
  --arg build_id "$BUILD_ID" \
  --arg k3d_version "$K3D_VERSION" \
  --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '{name: $name, type: $type, app_type: $app_type, path: $path, build_id: $build_id, k3d_version: $k3d_version, created: $created}' \
  > "output-$K3D_VM_NAME/$K3D_VM_NAME-$BUILD_ID.manifest.json"

log_info "Build completed successfully"
