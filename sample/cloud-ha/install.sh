#!/bin/bash

helm repo update
helm upgrade ha-release protopie/cloud \
    -n ha-namespace \
    --install \
    --create-namespace \
    --set-file cloud.config.yml=config.yml \
    --set-file cloud.license.pem=license.pem \
    -f ha.values.yaml
