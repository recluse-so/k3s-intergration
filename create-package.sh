#!/bin/bash

# Get the GitHub token from Docker credentials
TOKEN=$(docker-credential-desktop get < <(echo "https://ghcr.io") | jq -r '.Secret')

if [ -z "$TOKEN" ]; then
    echo "No token found. Please make sure you are logged in to ghcr.io"
    exit 1
fi

# Create the package repository
echo "Creating package repository..."
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/user/packages/container/vlan-cni \
  -d '{"visibility":"private"}'

# Verify the package exists
echo -e "\nVerifying package..."
curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/user/packages/container/vlan-cni 