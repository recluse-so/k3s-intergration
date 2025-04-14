FROM golang:1.20 as builder

WORKDIR /workspace

# Copy go.mod and go.sum first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY cmd/ cmd/
COPY pkg/ pkg/

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -ldflags="-w -s" -o vlan-cni ./cmd/vlan-cni

# Use a minimal image for the final container
FROM alpine:3.17

WORKDIR /

COPY --from=builder /workspace/vlan-cni /opt/cni/bin/vlan-cni

# Install required tools
RUN apk add --no-cache iproute2 bash

# Installation script
COPY scripts/install.sh /install.sh
RUN chmod +x /install.sh

ENTRYPOINT ["/install.sh"]