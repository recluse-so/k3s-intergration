#!/bin/bash

# Exit on error
set -e

# Configuration
ARANYA_DIR="/var/lib/aranya"
ARANYA_KEYSTORE="$ARANYA_DIR/keystore"

# Ensure keystore directory exists
if [ ! -d "$ARANYA_KEYSTORE" ]; then
    echo "Keystore directory does not exist. Please run setup_aranya.sh first."
    exit 1
fi

# Generate keys
echo "Generating Aranya keys..."
cd "$ARANYA_KEYSTORE"

# Generate root CA
openssl genrsa -out root-ca.key 4096
openssl req -new -x509 -days 3650 -key root-ca.key -out root-ca.crt -subj "/CN=Aranya Root CA"

# Generate server key and certificate
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr -subj "/CN=Aranya Server"
openssl x509 -req -days 3650 -in server.csr -CA root-ca.crt -CAkey root-ca.key -CAcreateserial -out server.crt

# Generate client key and certificate
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr -subj "/CN=Aranya Client"
openssl x509 -req -days 3650 -in client.csr -CA root-ca.crt -CAkey root-ca.key -CAcreateserial -out client.crt

# Set permissions
sudo chmod 600 *.key
sudo chmod 644 *.crt *.csr

echo "Keystore setup complete. Keys generated in $ARANYA_KEYSTORE" 