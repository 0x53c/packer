#!/bin/bash

set -e

echo "Validating K3d cluster..."

if ! command -v k3d &> /dev/null; then
  echo "ERROR: k3d not found"
  exit 1
fi

if ! k3d cluster list | grep -q "helios-cluster"; then
  echo "ERROR: helios-cluster not found"
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo "ERROR: kubectl not found"
  exit 1
fi

if ! kubectl get nodes | grep -q " Ready "; then
  echo "ERROR: Nodes not ready"
  exit 1
fi

for ns in kube-system metallb-system kubernetes-dashboard; do
  if ! kubectl get pods -n $ns | grep -q "Running"; then
    echo "ERROR: Pods in $ns namespace not running"
    exit 1
  fi
done

if ! systemctl is-enabled k3d-cluster.service &> /dev/null; then
  echo "ERROR: k3d-cluster service not enabled"
  exit 1
fi

echo "K3d cluster validation passed"
exit 0
