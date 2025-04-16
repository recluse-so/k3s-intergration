.PHONY: build docker-build deploy clean install

# Build binaries
build:
	cd socni && cargo build --release
	mkdir -p bin
	cp socni/target/release/vlan-cni bin/vlan
	cp socni/target/release/socni-ctl bin/socni-ctl

# Build Docker image
docker-build:
	docker build -t vlan-cni:latest -f Dockerfile.socni .

# Deploy to Kubernetes
deploy:
	kubectl apply -f manifests/daemonset.yaml

# Create network attachment definitions
create-networks:
	kubectl apply -f deployments/network-attachment-definitions/

# Install CNI plugin locally
install: build
	sudo mkdir -p /opt/cni/bin
	sudo cp bin/vlan /opt/cni/bin/
	sudo chmod +x /opt/cni/bin/vlan
	sudo cp bin/socni-ctl /usr/local/bin/
	sudo chmod +x /usr/local/bin/socni-ctl
	sudo socni/scripts/install.sh

# Install CLI tool only
install-cli: build
	sudo cp bin/socni-ctl /usr/local/bin/
	sudo chmod +x /usr/local/bin/socni-ctl

# Clean up
clean:
	kubectl delete -f deployments/daemonset.yaml || true
	kubectl delete -f deployments/configmap.yaml || true
	kubectl delete -f deployments/rbac.yaml || true
	rm -rf bin
	cd socni && cargo clean