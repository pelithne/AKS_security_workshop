#!/bin/bash
# Update the package index and install the prerequisites for Azure CLI
sudo apt-get update && sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg
# Download and install the Microsoft signing key
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
# Add the Azure CLI repository to your sources list
AZ_REPO=$(lsb_release -cs) && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
# Install Azure CLI
sudo apt-get update && sudo apt-get install azure-cli
# Install Docker
sudo apt-get update && sudo apt-get install docker.io
# Install AKS CLI
az aks install-cli

