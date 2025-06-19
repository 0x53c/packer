#!/bin/bash

set -e

sudo rpm-ostree install -y jq kubectl
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

if ! command -v docker &> /dev/null; then
  echo "Docker not found, installing..."
  sudo rpm-ostree install docker-ce docker-ce-cli containerd.io
  sudo systemctl enable --now docker
fi

sudo usermod -aG docker core
k3d cluster create helios-cluster \
  --api-port 6443 \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"

echo "Waiting for cluster to be ready..."
timeout 300 bash -c 'until kubectl get nodes | grep -q " Ready "; do sleep 5; done'

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

mkdir -p /home/core/.kube
k3d kubeconfig get helios-cluster > /home/core/.kube/config
chmod 600 /home/core/.kube/config
chown core:core /home/core/.kube/config

kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml

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

cat <<EOF > /home/core/start-cluster.sh
#!/bin/bash
k3d cluster start helios-cluster
EOF
chmod +x /home/core/start-cluster.sh

cat <<EOF | sudo tee /etc/systemd/system/k3d-cluster.service
[Unit]
Description=Start K3d Kubernetes Cluster
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=core
ExecStart=/home/core/start-cluster.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable k3d-cluster.service

echo "K3d cluster bootstrap completed"
