#!/bin/sh
helm search repo ingress-nginx --versions | tail | awk '{print $2}' | while read line; do
  echo "Installing version $line"
  #helm install --version $line  ingress-nginx ingress-nginx/ingress-nginx
  read -p "Continue? (Y/N): " confirm
  # [[ $confirm == [yY] ]] || return 1
done