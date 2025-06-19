#!/bin/bash

log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $1"
}

log_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

wait_for_vm() {
    local VM_NAME=$1
    local MAX_ATTEMPTS=30
    local ATTEMPT=0
    
    log_info "Waiting for VM $VM_NAME to be ready..."
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if orb machine ssh "$VM_NAME" "echo 'VM is ready'" &>/dev/null; then
            log_success "VM $VM_NAME is ready"
            return 0
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        log_info "Still waiting... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
        sleep 5
    done
    
    log_error "Timed out waiting for VM $VM_NAME to be ready"
    return 1
}

command_exists() {
    command -v "$1" &> /dev/null
}

ensure_dir() {
    [ -d "$1" ] || mkdir -p "$1"
}

get_latest_build_id() {
    local IMAGE_NAME=$1
    if [ -d "output-$IMAGE_NAME" ]; then
        ls "output-$IMAGE_NAME"/*.manifest.json 2>/dev/null | sort | tail -1 | xargs cat 2>/dev/null | jq -r '.build_id' 2>/dev/null || echo ""
    else
        echo ""
    fi
}
