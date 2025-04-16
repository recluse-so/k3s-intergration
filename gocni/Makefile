.PHONY: build docker-build deploy clean install

# Build binary
build:
	go build -o bin/vlan-cni ./cmd/vlan-cni

# Build Docker image
docker-build:
	docker build -t vlan-cni:latest .

# Deploy to Kubernetes
deploy:
	kubectl apply -f deployments/configmap.yaml
	kubectl apply -f deployments/rbac.yaml
	kubectl apply -f deployments/daemonset.yaml

# Create network attachment definitions
create-networks:
	kubectl apply -f deployments/network-attachment-definitions/

# Install CNI plugin locally
install: build
	sudo ./scripts/install.sh

# Clean up
clean:
	kubectl delete -f deployments/daemonset.yaml
	kubectl delete -f deployments/configmap.yaml
	kubectl delete -f deployments/rbac.yaml
	rm -f bin/vlan-cni