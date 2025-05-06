#!/bin/bash

# Create or update the secret from the policy file
kubectl create secret generic socni-policies \
  --from-file=multi-tenant-policy.md=multi-tenant-policy.md \
  --namespace=kube-system \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret 'socni-policies' has been updated in namespace kube-system" 