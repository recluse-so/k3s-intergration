#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to print warning messages
print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to print error messages
print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Display the Joker
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/joker.sh" ]; then
  chmod +x "$SCRIPT_DIR/joker.sh"
  "$SCRIPT_DIR/joker.sh"
fi

# Check for required tools
print_status "Checking for required tools..."

if ! command_exists kubectl; then
  print_error "kubectl is not installed. Please install kubectl first."
  exit 1
fi

if ! command_exists kustomize; then
  print_warning "kustomize is not installed. Will use kubectl's built-in kustomize."
fi

# Check if we're connected to a Kubernetes cluster
print_status "Checking Kubernetes cluster connection..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
  exit 1
fi

# Create the policy directory if it doesn't exist
print_status "Creating policy directory..."
mkdir -p k8s/vanilla-install/policy

# Check if the policy file exists
if [ ! -f "k8s/vanilla-install/policy/team-policy.md" ]; then
  print_warning "Policy file not found at k8s/vanilla-install/policy/team-policy.md"
  print_warning "Please create the policy file before proceeding."
  exit 1
fi

# Create a ConfigMap from the policy file
print_status "Creating ConfigMap from policy file..."
kubectl create configmap aranya-policy --from-file=k8s/vanilla-install/policy/team-policy.md -n aranya --dry-run=client -o yaml | kubectl apply -f -

# Apply the base configuration
print_status "Applying base configuration..."
kubectl apply -k k8s/vanilla-install/base

# Check if we're in a development environment
if [ -d "k8s/vanilla-install/overlays/dev" ]; then
  print_status "Development overlay detected. Applying development configuration..."
  kubectl apply -k k8s/vanilla-install/overlays/dev
fi

# Wait for the daemon to be ready
print_status "Waiting for Aranya daemon to be ready..."
kubectl rollout status daemonset/aranya-daemon -n aranya

# Verify the installation
print_status "Verifying installation..."

# Check if the daemon pods are running
DAEMON_PODS=$(kubectl get pods -n aranya -l app=aranya-daemon -o name | wc -l)
if [ "$DAEMON_PODS" -eq 0 ]; then
  print_error "No Aranya daemon pods are running."
  exit 1
fi

# Check if the policy is mounted
POLICY_MOUNTED=$(kubectl describe pod -n aranya -l app=aranya-daemon | grep -A 5 Mounts | grep policy-volume | wc -l)
if [ "$POLICY_MOUNTED" -eq 0 ]; then
  print_warning "Policy volume is not mounted in the daemon pods."
  print_warning "Please check the daemon configuration."
fi

# Check if the init container completed successfully
INIT_COMPLETED=$(kubectl get pods -n aranya -l app=aranya-daemon -o jsonpath='{.items[0].status.initContainerStatuses[?(@.name=="policy-init")].state.terminated.exitCode}')
if [ "$INIT_COMPLETED" != "0" ]; then
  print_warning "Policy init container may not have completed successfully."
  print_warning "Please check the pod logs for more information."
fi

print_status "Installation completed successfully!"
print_status "You can check the status of the Aranya daemon with:"
echo "  kubectl get pods -n aranya -l app=aranya-daemon"
print_status "To view the logs of the Aranya daemon, use:"
echo "  kubectl logs -n aranya -l app=aranya-daemon" 