#!/bin/bash

helm repo update
helm upgrade my-release ../../charts/cloud -n my-namespace \
    --install \
    --dry-run \
    --create-namespace \
    --set-file cloud.config.yml=config.yml \
    --set-file cloud.license.pem=license.pem \
    -f my.values.yaml
