#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -n, --nodes     Number of nodes to generate keys for (default: 1)"
    echo "  -o, --output    Output directory for keys (default: ./aranya-keys)"
    echo "  -h, --help      Display this help message"
    exit 1
}

# Default values
NODES=1
OUTPUT_DIR="./aranya-keys"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--nodes)
            NODES="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate control plane key
echo "Generating control plane key..."
openssl genpkey -algorithm RSA -out "$OUTPUT_DIR/control-plane.key" -pkeyopt rsa_keygen_bits:4096
openssl rsa -in "$OUTPUT_DIR/control-plane.key" -pubout -out "$OUTPUT_DIR/control-plane.pub"

# Generate node keys
for i in $(seq 1 $NODES); do
    echo "Generating keys for node $i..."
    mkdir -p "$OUTPUT_DIR/node-$i"
    openssl genpkey -algorithm RSA -out "$OUTPUT_DIR/node-$i/node.key" -pkeyopt rsa_keygen_bits:4096
    openssl rsa -in "$OUTPUT_DIR/node-$i/node.key" -pubout -out "$OUTPUT_DIR/node-$i/node.pub"
done

# Create Kubernetes secret
echo "Creating Kubernetes secret..."
kubectl create secret generic aranya-keys \
    --from-file="$OUTPUT_DIR/control-plane.key" \
    --from-file="$OUTPUT_DIR/control-plane.pub" \
    --from-file="$OUTPUT_DIR/node-1/node.key" \
    --from-file="$OUTPUT_DIR/node-1/node.pub" \
    -n kube-system

echo "Keys generated successfully!"
echo "Control plane keys: $OUTPUT_DIR/control-plane.{key,pub}"
echo "Node keys: $OUTPUT_DIR/node-*/node.{key,pub}"
echo "Kubernetes secret 'aranya-keys' created in kube-system namespace" 