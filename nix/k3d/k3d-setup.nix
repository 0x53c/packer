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
