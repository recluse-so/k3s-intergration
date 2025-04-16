#!/bin/bash

# clone the repo
git clone https://github.com/aranya-project/aranya-core.git
git clone https://github.com/aranya-project/aranya.git

# build
make build

# clean up build
cargo clean

# run integration tests
sudo cargo test test_vlan_cni_with_aranya -- --ignored
cargo check --test integration_test