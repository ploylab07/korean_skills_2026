apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: containerd-registry-mirror
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: containerd-registry-mirror
  template:
    metadata:
      labels:
        app: containerd-registry-mirror
    spec:
      hostPID: true
      tolerations:
        - operator: Exists
      initContainers:
        - name: configure
          image: ${ECR_REGISTRY}/addon/preload-helper:latest
          securityContext:
            privileged: true
          command:
            - sh
            - -c
            - |
              set -e
              ECR="https://${ECR_REGISTRY}"
              for base in docker.io registry-1.docker.io; do
                for path in radial/busyboxplus library/mysql; do
                  DIR="/host/etc/containerd/certs.d/${base}/${path}"
                  mkdir -p "$DIR"
                  cat > "$DIR/hosts.toml" <<TOML
              server = "https://registry-1.docker.io"

              [host."https://registry-1.docker.io"]
                capabilities = []

              [host."${ECR}"]
                capabilities = ["pull", "resolve"]
                override_path = true
              TOML
                done
              done
              CFG=/host/etc/containerd/config.toml
              if ! grep -q 'registry.mirrors."docker.io"' "$CFG"; then
                cat >> "$CFG" <<CFG

              [plugins."io.containerd.cri.v1.images".registry.mirrors."docker.io"]
                endpoint = ["${ECR}"]
              CFG
              fi
          volumeMounts:
            - name: host-root
              mountPath: /host
      containers:
        - name: pause
          image: ${ECR_REGISTRY}/addon/preload-helper:latest
          command: ["sleep", "infinity"]
      volumes:
        - name: host-root
          hostPath:
            path: /
