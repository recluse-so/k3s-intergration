#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display menu
show_menu() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}                SoCNI Functionality Checker            ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""
    echo -e "${YELLOW}1. Basic Checks${NC}"
    echo "   1.1 Check SoCNI Pod Status"
    echo "   1.2 Check SoCNI Logs"
    echo "   1.3 Check SoCNI CLI Tool"
    echo ""
    echo -e "${YELLOW}2. Network Configuration${NC}"
    echo "   2.1 Check CNI Configuration"
    echo "   2.2 Check Network Namespaces"
    echo ""
    echo -e "${YELLOW}3. Testing VLAN Functionality${NC}"
    echo "   3.1 Create Test Pods"
    echo "   3.2 Verify Pod Network"
    echo "   3.3 Test VLAN Isolation"
    echo ""
    echo -e "${YELLOW}4. Cryptographic Verification${NC}"
    echo "   4.1 Verify Aranya Keystore"
    echo "   4.2 Check TLS Certificates"
    echo "   4.3 Test Encrypted Communication"
    echo "   4.4 Verify Policy Enforcement"
    echo ""
    echo -e "${YELLOW}5. Troubleshooting${NC}"
    echo "   5.1 Check Network Policies"
    echo "   5.2 Check Network Routes"
    echo "   5.3 Check System Logs"
    echo ""
    echo -e "${YELLOW}6. Cleanup${NC}"
    echo "   6.1 Delete Test Pods"
    echo "   6.2 Restart SoCNI Daemonset"
    echo "   6.3 Clean All Resources"
    echo ""
    echo -e "${RED}0. Exit${NC}"
    echo ""
    echo -n "Enter your choice: "
}

# Function to execute commands
execute_command() {
    case $1 in
        "1.1")
            echo -e "${GREEN}Checking SoCNI pod status...${NC}"
            kubectl get pods -n kube-system | grep vlan-cni
            kubectl describe pod -n kube-system -l app=vlan-cni
            ;;
        "1.2")
            echo -e "${GREEN}Checking SoCNI logs...${NC}"
            kubectl logs -n kube-system -l app=vlan-cni --tail=50
            ;;
        "1.3")
            echo -e "${GREEN}Checking SoCNI CLI tool...${NC}"
            minikube ssh "socni-ctl status"
            minikube ssh "socni-ctl list-networks"
            ;;
        "2.1")
            echo -e "${GREEN}Checking CNI configuration...${NC}"
            minikube ssh "cat /etc/cni/net.d/10-socni.conflist"
            minikube ssh "ls -l /opt/cni/bin/vlan"
            ;;
        "2.2")
            echo -e "${GREEN}Checking network namespaces...${NC}"
            minikube ssh "ip netns list"
            echo -n "Enter namespace to inspect (or press Enter to skip): "
            read namespace
            if [ ! -z "$namespace" ]; then
                minikube ssh "ip netns exec $namespace ip addr"
            fi
            ;;
        "3.1")
            echo -e "${GREEN}Creating test pods...${NC}"
            kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan-pod
  annotations:
    socni.network.aranya.io/tenant-id: "test"
    socni.network.aranya.io/vlan: "100"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF

            kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan-pod-2
  annotations:
    socni.network.aranya.io/tenant-id: "test"
    socni.network.aranya.io/vlan: "200"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF
            ;;
        "3.2")
            echo -e "${GREEN}Verifying pod network...${NC}"
            kubectl get pod test-vlan-pod test-vlan-pod-2 -o wide
            echo -e "${YELLOW}View network interfaces in pod? (y/n)${NC}"
            read response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                kubectl exec -it test-vlan-pod -- ip addr
            fi
            echo -e "${YELLOW}Test connectivity to gateway? (y/n)${NC}"
            read response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                kubectl exec -it test-vlan-pod -- ping -c 3 10.100.0.1
            fi
            ;;
        "3.3")
            echo -e "${GREEN}Testing VLAN isolation...${NC}"
            POD2_IP=$(kubectl get pod test-vlan-pod-2 -o jsonpath='{.status.podIP}')
            if [ -n "$POD2_IP" ]; then
                kubectl exec -it test-vlan-pod -- ping -c 3 $POD2_IP
            else
                echo -e "${RED}Could not get IP address of second pod${NC}"
            fi
            ;;
        "4.1")
            echo -e "${GREEN}Verifying Aranya keystore...${NC}"
            minikube ssh "ls -l /var/lib/aranya/keystore/"
            minikube ssh "openssl x509 -in /var/lib/aranya/keystore/server.crt -text -noout"
            minikube ssh "openssl x509 -in /var/lib/aranya/keystore/client.crt -text -noout"
            ;;
        "4.2")
            echo -e "${GREEN}Checking TLS certificates...${NC}"
            # Verify certificate chain
            minikube ssh "openssl verify -CAfile /var/lib/aranya/keystore/ca.crt /var/lib/aranya/keystore/server.crt"
            minikube ssh "openssl verify -CAfile /var/lib/aranya/keystore/ca.crt /var/lib/aranya/keystore/client.crt"
            
            # Check certificate validity
            minikube ssh "openssl x509 -in /var/lib/aranya/keystore/server.crt -checkend 0 -noout"
            minikube ssh "openssl x509 -in /var/lib/aranya/keystore/client.crt -checkend 0 -noout"
            ;;
        "4.3")
            echo -e "${GREEN}Testing encrypted communication...${NC}"
            # Create a test pod with tcpdump
            kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: tcpdump-pod
spec:
  containers:
  - name: tcpdump
    image: corfr/tcpdump
    command: ["sleep", "3600"]
    securityContext:
      capabilities:
        add: ["NET_ADMIN"]
EOF
            
            # Wait for pod to be ready
            kubectl wait --for=condition=Ready pod/tcpdump-pod --timeout=60s
            
            # Start tcpdump in background
            kubectl exec -it tcpdump-pod -- tcpdump -i any -w /tmp/capture.pcap &
            TCPDUMP_PID=$!
            
            # Create test traffic
            kubectl exec -it test-vlan-pod -- ping -c 3 10.100.0.1
            
            # Stop tcpdump
            kill $TCPDUMP_PID
            
            # Analyze capture
            echo -e "${YELLOW}Analyzing network traffic...${NC}"
            kubectl exec -it tcpdump-pod -- tcpdump -r /tmp/capture.pcap -n
            
            # Cleanup
            kubectl delete pod tcpdump-pod
            ;;
        "4.4")
            echo -e "${GREEN}Verifying policy enforcement...${NC}"
            # Create pods with different tenant IDs
            kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: tenant1-pod
  annotations:
    socni.network.aranya.io/tenant-id: "tenant1"
    socni.network.aranya.io/vlan: "100"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF

            kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: tenant2-pod
  annotations:
    socni.network.aranya.io/tenant-id: "tenant2"
    socni.network.aranya.io/vlan: "100"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF

            # Wait for pods to be ready
            kubectl wait --for=condition=Ready pod/tenant1-pod pod/tenant2-pod --timeout=60s

            # Get IP addresses
            TENANT1_IP=$(kubectl get pod tenant1-pod -o jsonpath='{.status.podIP}')
            TENANT2_IP=$(kubectl get pod tenant2-pod -o jsonpath='{.status.podIP}')

            # Test connectivity (should fail due to policy)
            echo -e "${YELLOW}Testing tenant isolation...${NC}"
            kubectl exec -it tenant1-pod -- ping -c 3 $TENANT2_IP || echo -e "${GREEN}Policy enforcement working (ping failed as expected)${NC}"

            # Cleanup
            kubectl delete pod tenant1-pod tenant2-pod
            ;;
        "5.1")
            echo -e "${GREEN}Checking network policies...${NC}"
            minikube ssh "cat /var/lib/aranya/config.json"
            minikube ssh "ps aux | grep aranya-daemon"
            ;;
        "5.2")
            echo -e "${GREEN}Checking network routes...${NC}"
            kubectl exec -it test-vlan-pod -- ip route
            minikube ssh "ip link show type vlan"
            ;;
        "5.3")
            echo -e "${GREEN}Checking system logs...${NC}"
            minikube ssh "journalctl -u kubelet | grep socni"
            minikube ssh "cat /var/log/socni.log"
            ;;
        "6.1")
            echo -e "${GREEN}Deleting test pods...${NC}"
            kubectl delete pod test-vlan-pod test-vlan-pod-2 --ignore-not-found
            ;;
        "6.2")
            echo -e "${GREEN}Restarting SoCNI daemonset...${NC}"
            kubectl rollout restart daemonset -n kube-system vlan-cni
            ;;
        "6.3")
            echo -e "${GREEN}Cleaning all resources...${NC}"
            kubectl delete -f manifests/daemonset.yaml --ignore-not-found
            kubectl delete -f deployments/network-attachment-definitions/ --ignore-not-found
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

# Main loop
while true; do
    show_menu
    read choice
    case $choice in
        0)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            execute_command "$choice"
            ;;
    esac
    echo -e "\nPress Enter to continue..."
    read
done 
