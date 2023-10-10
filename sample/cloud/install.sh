#!/bin/bash

helm repo update
helm install my-release protopie/cloud -n my-namespace --create-namespace \
    --set-file config.yml=config.yml \
    --set-file license.pem license.pem \
    -f my.values.yaml