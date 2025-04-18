.PHONY: build docker-build deploy clean install install-cli

# Build binaries
build:
	cargo build --release
	mkdir -p bin
	cp ./target/release/socni bin/vlan
	cp ./target/release/socni-ctl bin/socni-ctl
	chmod +x bin/vlan bin/socni-ctl

# Build Docker image
docker-build:
	docker build -t vlan-cni:latest -f Dockerfile.socni .

# Deploy to Kubernetes
deploy:
	kubectl apply -f manifests/daemonset.yaml

# Create network attachment definitions
create-networks:
	kubectl apply -f manifests/deployments/network-attachment-definitions/

# Install CNI plugin locally
install: build
	sudo mkdir -p /opt/cni/bin
	sudo cp bin/vlan /opt/cni/bin/
	sudo chmod +x /opt/cni/bin/vlan
	sudo cp bin/socni-ctl /usr/local/bin/
	sudo chmod +x /usr/local/bin/socni-ctl
	sudo bash scripts/install-cni.sh

# Install CLI tool only
install-cli: build
	sudo cp bin/socni-ctl /usr/local/bin/
	sudo chmod +x /usr/local/bin/socni-ctl
	sudo bash scripts/install-cli.sh

# Clean up
clean:
	kubectl delete -f manifests/deployments/daemonset.yaml || true
	kubectl delete -f manifests/deployments/configmap.yaml || true
	kubectl delete -f manifests/deployments/rbac.yaml || true
	rm -rf bin
	cd socni && cargo clean