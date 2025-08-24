API_IP=$(ip -4 addr show | awk '/inet 192\.168\.1\./ {print $2}' | cut -d/ -f1 | head -n1)

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.0+k3s1" sh -s - server \
  --node-ip "${API_IP}" \
  --advertise-address "${API_IP}" \
  --tls-san "${API_IP}" \
  --write-kubeconfig-mode 644
