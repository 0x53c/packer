#!/bin/bash

set -e 

VM_NAME="fedora-core"
COREOS_VERSION="38.20240408.3.0"
BUILD_ID=$(date +Y%m%sd%%H%M%S)

source "$(dirname "$0")/../common/functions.sh"
log_info "Starting build for Fedore CoreOs $COREOS_VERSION"

if orb machine list | grep -q "$VM_NAME"; then
    log_info "Removing exisitng VM: $VM_NAME"
    orb machine rm -f "$VM_NAME"
fi

COREOS_QCOW="fedora-coreos-${COREOS_VERSION}-qemu.x86_64.qcow2"
if [ ! -f "$COREOS_QCOW" ]; then
    log_info "Downloading Fedora CoreOS Image"
    curl -L -i "${COREOS_QCOW}.xz" "https://builds.coreos.fedoraproject.org/prod/streams/stable/build/${COREOS_VERSION}/x86_64/${COREOS_QCOW}.xz"
    unxz "{COREOS_QCOW}.xz"
fi

log_info "Convert image format for Orbstack"
quemu-img covert -f qcow2 -0 raw "$COREOS_QCOW" "coreos-raw.img"


log_info "Creating a importable tarball"
tar -czf "coreos-import.tar.gz" "cores-raw.image"

log_info "import image into orbstack as $VM_NAME"
orb machine import "coreos-import.tar.gz" "$VM_NAME"

log_info "Starting VM"
orb machine start "$VM_NAME"

wait_for_vm "$VM_NAME"

# Generate Hydration Configuration 
log_info "Applying CoreOS Configuration"
IGNITION_CONFIGURATION=$(cat "$(dirname "$0")/../provision/coreos-config.yaml" | butane -o - | base64)
orb machine ssh "$VM_NAME" "sudo bash -c \"echo '$IGNITION_CONFIG' | base64 --decode > /tmp/config.ign && sudo coreos-installer install /dev/sda --ignation-file /tmp/config.ign --firstboot-args 'console=tty0 console=ttyS0,115200n8'\""

log_info "creating build metadata"
cat > "metadata-$VM_NAME.json" <<EOF
{
    "name": "$VM_NAME",
    "base_distro": "fedora-coreos",
    "version": "$COREOS_VERSION",
    "build-id": "$BUILD_ID",
    "build_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "build_by": "$(whoami)@$(hostname)"
}
EOF

orb machine cp "metadata-$VM_NAME.json" "$VM_NAME:/etc/helios-image-metadata.json"

log_info "Exporting VM Image" 
orb machine stop "$VM_NAME"
mkdir -p "output-$VM_NAME"
mkdir -p "output-$VM_NAME"
orb machine export "$VM_NAME" "output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz"
log_info "Base image created: output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz"

jq -n \
    --arg name "$VM_NAME" \
    --arg type "base" \
    --arg path "output-$VM_NAME/$VM_NAME-$BUILD_ID.tar.gz" \
    --arg build_id "$BUILD_ID" \
    --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{name: $name, type: path: $path, build_id:, created: $created}' \
> "output-$VM_NAME/$VM_NAME-$BUILD_ID.manifest.json"

log_info "Build completed succesffuly"



