### Setup environment variables


````
RG=AKS_Security_RG
LOCATION=westeurope # NOTE for this exercise use "westeurope"  as region
HUB_VNET_PREFIX=10.0.0.0/16 # IP range of the hub virtual network
HUB_VNET_NAME=Hub_VNET
BASTION_NSG_NAME=Bastion_NSG
JUMPBOX_NSG_NAME=Jumpbox_NSG
AKS_NSG_NAME=Aks_NSG
ENDPOINTS_NSG_NAME=Endpoints_NSG
LOADBALANCER_NSG_NAME=Loadbalancer_NSG
APPGW_NSG=Appgw_NSG
SPOKE_VNET_PREFIX=10.1.0.0/16
SPOKE_VNET_NAME=Spoke_VNET


````

### Create the resource group for the virtual networks

````
az group create --name $RG --location westeurope
````


### Create Network Security Group (NSG) for the Hub.

//TODO: create a script that performs the actions below.

In this step, we will begin by establishing a Network Security Group (NSG) that will subsequently be associated with the AzureBastionSubnet. It is crucial to note that there are specific prerequisites concerning security rules that must be met before Azure Bastion can be deployed.

Essentially, we are establishing security rules to permit both the control and data plane access to the AzureBastion. For a more detailed understanding of these rules, please refer to the following resource: [More Information](https://learn.microsoft.com/en-us/azure/bastion/bastion-nsg).

Lets Create the NSG for AzureBastionSubnet.
````
az network nsg create \
    --resource-group $RG \
    --name $BASTION_NSG_NAME \
    --location $LOCATION
````

Associate the required **inbound** security rules to the NSG.
````
    az network nsg rule create --name AllowHttpsInbound \
    --nsg-name $BASTION_NSG_NAME --priority 120 --resource-group $RG\
    --access Allow --protocol TCP --direction Inbound \
    --source-address-prefixes "Internet" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "443"
	
   	az network nsg rule create --name AllowGatewayManagerInbound \
    --nsg-name $BASTION_NSG_NAME --priority 130 --resource-group $RG\
    --access Allow --protocol TCP --direction Inbound \
    --source-address-prefixes "GatewayManager" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "443"
	
	az network nsg rule create --name AllowAzureLoadBalancerInbound \
    --nsg-name $BASTION_NSG_NAME --priority 140 --resource-group $RG\
    --access Allow --protocol TCP --direction Inbound \
    --source-address-prefixes "AzureLoadBalancer" \
    --source-port-ranges "*" \
    --destination-address-prefixes "*" \
    --destination-port-ranges "443"
	
	
	az network nsg rule create --name AllowBastionHostCommunication \
    --nsg-name $BASTION_NSG_NAME --priority 150 --resource-group $RG\
    --access Allow --protocol TCP --direction Inbound \
    --source-address-prefixes "VirtualNetwork" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges 8080 5701
````

Associate the required **outbound** security rules to the NSG.

````
    az network nsg rule create --name AllowSshRdpOutbound \
    --nsg-name $BASTION_NSG_NAME --priority 100 --resource-group $RG\
    --access Allow --protocol "*" --direction outbound \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges 22 3389
	
    az network nsg rule create --name AllowAzureCloudOutbound \
    --nsg-name $BASTION_NSG_NAME --priority 110 --resource-group $RG\
    --access Allow --protocol Tcp --direction outbound \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "AzureCloud" \
    --destination-port-ranges 443
	
	az network nsg rule create --name AllowBastionCommunication \
    --nsg-name $BASTION_NSG_NAME --priority 120 --resource-group $RG\
    --access Allow --protocol "*" --direction outbound \
    --source-address-prefixes "VirtualNetwork" \
    --source-port-ranges "*" \
    --destination-address-prefixes "VirtualNetwork" \
    --destination-port-ranges 8080 5701
	
	az network nsg rule create --name AllowHttpOutbound \
    --nsg-name $BASTION_NSG_NAME --priority 130 --resource-group $RG\
    --access Allow --protocol "*" --direction outbound \
    --source-address-prefixes "*" \
    --source-port-ranges "*" \
    --destination-address-prefixes "Internet" \
    --destination-port-ranges 80
````

Create an NSG for the JumpBox subnet.

````
az network nsg create \
    --resource-group $RG \
    --name $JUMPBOX_NSG_NAME \
    --location $LOCATION
````

### Create the hub virtual network with three subnets, and associate the NSG to their respective subnet.


Create the HUB VNET with one subnet for **AzureBastionSubnet** and associate it to the bastion NSG.

````

az network vnet create \
    --resource-group $RG  \
    --name $HUB_VNET_NAME \
    --address-prefixes $HUB_VNET_PREFIX \
    --subnet-name AzureBastionSubnet \
    --subnet-prefixes 10.0.1.0/24 \
    --network-security-group $BASTION_NSG_NAME

````
Create subnet for the Azure Firewall


````

az network vnet subnet create \
    --resource-group $RG  \
    --vnet-name $HUB_VNET_NAME \
    --name AzureFirewallSubnet \
    --address-prefixes 10.0.2.0/24

````
Create subnet for the Virtual Machine that will be used as "jumpbox".

````

az network vnet subnet create \
    --resource-group $RG  \
    --vnet-name $HUB_VNET_NAME \
    --name JumpboxSubnet \
    --address-prefixes 10.0.3.0/24 \
    --network-security-group $JUMPBOX_NSG_NAME
````

### Create Network Security Group (NSG) for the Spoke.
````
az network nsg create \
    --resource-group $RG \
    --name $AKS_NSG_NAME \
    --location $LOCATION
	
az network nsg create \
    --resource-group $RG \
    --name $ENDPOINTS_NSG_NAME \
    --location $LOCATION

az network nsg create \
    --resource-group $RG \
    --name $LOADBALANCER_NSG_NAME \
    --location $LOCATION

az network nsg create \
    --resource-group $RG \
    --name $APPGW_NSG \
    --location $LOCATION
````



### Create the spoke virtual network with 4 subnets, and associate the NSG to their respective subnet.


Create the spoke VNET with one subnet for **AKS Subnet** and associate it to the AKS NSG.

````
az network vnet create \
    --resource-group $RG  \
    --name $SPOKE_VNET_NAME \
    --address-prefixes $SPOKE_VNET_PREFIX \
    --subnet-name aks-subnet \
    --subnet-prefixes 10.1.1.0/24 \
	--network-security-group $AKS_NSG_NAME

````

Create subnet for the Endpoints and associate it to the endpoints NSG.


````
az network vnet subnet create \
    --resource-group $RG  \
    --vnet-name $SPOKE_VNET_NAME  \
    --name endpoints-subnet \
    --address-prefixes 10.1.2.0/24 \
	--network-security-group $ENDPOINTS_NSG_NAME

````

Create subnet for the load balancer that will be used for ingress traffic and associate it to the loadbalancer NSG.

````
az network vnet subnet create \
    --resource-group $RG  \
    --vnet-name $SPOKE_VNET_NAME \
    --name loadbalancer-subnet \
    --address-prefixes 10.1.3.0/24 \
	--network-security-group $LOADBALANCER_NSG_NAME
````


````
az network vnet subnet create \
    --resource-group $RG  \
    --vnet-name $SPOKE_VNET_NAME \
    --name app-gw-subnet \
    --address-prefixes 10.1.4.0/24 \
	--network-security-group $APPGW_NSG

````

### Create a peering connection between the hub and spoke virtual networks


````
az network vnet peering create \
    --resource-group $RG  \
    --name hub-to-spoke \
    --vnet-name $HUB_VNET_NAME \
    --remote-vnet $SPOKE_VNET_NAME \
    --allow-vnet-access

````

### Create a peering connection between the spoke and hub virtual networks


````
az network vnet peering create \
    --resource-group $RG  \
    --name spoke-to-hub \
    --vnet-name $SPOKE_VNET_NAME \
    --remote-vnet $HUB_VNET_NAME \
    --allow-vnet-access

````

### Create a public IP address for the bastion host


````
az network public-ip create \
    --resource-group $RG  \
    --name bastion-pip \
    --sku Standard \
    --allocation-method Static
````

### Create a network security group for the bastion subnet


````
az network nsg create \
    --resource-group $RG  \
    --name bastion-nsg
````

### Create a network security group rule to allow SSH traffic to the bastion subnet


````
az network nsg rule create \
    --resource-group $RG  \
    --nsg-name bastion-nsg \
    --name allow-ssh \
    --protocol Tcp \
    --direction Inbound \
    --source-address-prefixes Internet \
    --source-port-ranges '*' \
    --destination-address-prefixes 10.0.1.0/24 \
    --destination-port-ranges 22 \
    --access Allow \
    --priority 100

````

### Create JumpBox host



````
az vm create \
    --resource-group $RG \
    --name jumpbox-win \
    --image Win2019Datacenter \
    --admin-username azureuser \
    --admin-password Ericsson_2055 \
    --vnet-name $HUB_VNET_NAME \
    --subnet JumpBoxSubnet \
    --size Standard_B2s \
    --storage-sku Standard_LRS \
    --os-disk-name jumpbox-win-osdisk \
    --os-disk-size-gb 128 \
    --nsg jumpbox-nsg \
    --public-ip-address "" 
  

````

````
az network nic create \
    --resource-group $RG \
    --name jumpbox-win-nic \
    --vnet-name $HUB_VNET_NAME \
    --subnet JumpBoxSubnet \
    --network-security-group jumpbox-nsg \
    --accelerated-networking true 
 

````

````
az network nic ip-config create \
    --resource-group $RG \
    --nic-name jumpbox-win-nic \
    --name ipconfig1 \
    --private-ip-address 10.0.3.4 \
    --public-ip-address "" 

````

### Create the bastion host in hub vnet



````
az network bastion create \
    --resource-group $RG \
    --name bastionhost \
    --public-ip-address bastion-pip \
    --vnet-name $HUB_VNET_NAME \
    --location westeurope

````

### Connect to VM using the portal:
https://learn.microsoft.com/en-us/azure/bastion/create-host-cli#steps

### Create an Azure Firewall in the azure-firewall-subnet


````
az network firewall create \
    --resource-group $RG \
    --name azure-firewall \
    --location westeurope \
    --vnet-name $HUB_VNET_NAME \
    --enable-dns-proxy true

````

````
az network public-ip create \
    --name fw-pip \
    --resource-group $RG \
    --location westeurope \
    --allocation-method static \
    --sku standard

````

````
az network firewall ip-config create \
    --firewall-name azure-firewall \
    --name FW-config \
    --public-ip-address fw-pip \
    --resource-group $RG \
    --vnet-name $HUB_VNET_NAME

````

````
az network firewall update \
    --name azure-firewall \
    --resource-group $RG 

````

### Create Azure firewall network rules    


````
az network firewall network-rule create -g $RG -f azure-firewall --collection-name 'aksfwnr' -n 'apiudp' --protocols 'UDP' --source-addresses '*' --destination-addresses "AzureCloud.$LOC" --destination-ports 1194 --action allow --priority 100
````

````
az network firewall network-rule create -g $RG -f azure-firewall --collection-name 'aksfwnr' -n 'apitcp' --protocols 'TCP' --source-addresses '*' --destination-addresses "AzureCloud.$LOC" --destination-ports 9000
````

````
az network firewall network-rule create -g $RG -f azure-firewall --collection-name 'aksfwnr' -n 'time' --protocols 'UDP' --source-addresses '*' --destination-fqdns 'ntp.ubuntu.com' --destination-ports 123

````

### Create Azure firewall application rules


````
az network firewall application-rule create -g $RG -f azure-firewall --collection-name 'aksfwar' -n 'fqdn' --source-addresses '*' --protocols 'http=80' 'https=443' --fqdn-tags "AzureKubernetesService" --action allow --priority 100

````

### Create a route table for the spoke virtual network


````
az network route-table create \
    --resource-group $RG  \
    --name spoke-rt

````

### Create a route to the internet via the Azure Firewall


````
az network route-table route create \
    --resource-group $RG  \
    --name default-route \
    --route-table-name spoke-rt \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address 10.0.2.4

````

### Associate the route table with the aks-subnet


````
az network vnet subnet update \
    --resource-group $RG  \
    --vnet-name $SPOKE_VNET_NAME \
    --name aks-subnet \
    --route-table spoke-rt

````

### Create a user-assigned managed identity


````
az identity create \
    --resource-group $RG \
    --name abui

````

### Get the id of the user managed identity
identity_id=$(

````
az identity show \
    --resource-group $RG \
    --name abui \
    --query id \
    --output tsv)

````

### Get the principal id of the user managed identity
principal_id=$(

````
az identity show \
    --resource-group $RG \
    --name abui \
    --query principalId \
    --output tsv)

````

### Assign permissions for the user managed identity to the routing table


````
az role assignment create \
    --assignee $principal_id \
    --scope /subscriptions/0b6cb75e-8bb1-426b-8c7e-acd7c7599495/resourceGroups/$RG/providers/Microsoft.Network/routeTables/spoke-rt \
    --role "Network Contributor"

````

### Create a custom role, with least privilage access for AKS load balancer subnet

````
touch aks-net-contributor.json
````

add the following information to the json file.
````
{
    "properties": {
        "roleName": "aks-net-contributor",
        "description": "least privilige access",
        "assignableScopes": [
            "/subscriptions/0b6cb75e-8bb1-426b-8c7e-acd7c7599495/resourceGroups/$RG/providers/Microsoft.Network/virtualNetworks/$SPOKE_VNET_NAME/subnets/loadbalancer-subnet"
        ],
        "permissions": [
            {
                "actions": [
                    "Microsoft.Network/loadBalancers/read",
                    "Microsoft.Network/loadBalancers/write",
                    "Microsoft.Network/networkSecurityGroups/join/action",
                    "Microsoft.Network/loadBalancers/delete",
                    "Microsoft.Network/virtualNetworks/subnets/read",
                    "Microsoft.Network/virtualNetworks/subnets/write",
                    "Microsoft.Network/virtualNetworks/subnets/join/action"
                ],
                "notActions": [],
                "dataActions": [],
                "notDataActions": []
            }
        ]
    }
}
````

### create a role


````
az role definition create --role-definition ./aks-net-contributor.json
````


assign the custom role to the user assigned managed identity, first identify the service principal ID

principalId=$(

````
az identity show --name abui --resource-group $RG --query principalId --output tsv)

````

````
az role assignment create --assignee $principalId --role "aks-net-contributor"
````

### Create the AKS cluster in the aks-subnet


````
az aks create --resource-group $RG --node-count 3 --vnet-subnet-id /subscriptions/0b6cb75e-8bb1-426b-8c7e-acd7c7599495/resourceGroups/$RG/providers/Microsoft.Network/virtualNetworks/$SPOKE_VNET_NAME/subnets/aks-subnet  --enable-aad --enable-azure-rbac --name private-aks --enable-private-cluster --outbound-type userDefinedRouting --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys --assign-identity $identity_id

````

### Link the the hub network to the private DNS zone. 

DNS_ZONE_NAME=$(

````
az network private-dns zone list --resource-group $NODE_GROUP --query "[0].name" -o tsv)
HUB_VNET_ID=$(
````

````
az network vnet show -g $RG -n $HUB_VNET_NAME --query id --output tsv)
````

````
az network private-dns link vnet create --name "hubnetdnsconfig" --registration-enabled false --resource-group $NODE_GROUP --virtual-network $HUB_VNET_ID --zone-name $DNS_ZONE_NAME 

````

### create ACR 


````
az acr create \
    --resource-group $RG \
    --name acraksbl \
    --sku Premium \
    --admin-enabled false \
    --location westeurope \
    --allow-trusted-services false \
    --public-network-enabled false

````

### Disable network policies in subnet


````
az network vnet subnet update \
 --name endpoints-subnet \
 --vnet-name $SPOKE_VNET_NAME\
 --resource-group $RG \
 --disable-private-endpoint-network-policies
 
#Configure the private DNS zone
````

````
az network private-dns zone create \
  --resource-group $RG \
  --name "privatelink.azurecr.io"

````

### Create a virtual network association link
 

````
az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "privatelink.azurecr.io" \
  --name ACRDNSSpokeLink \
  --virtual-network $SPOKE_VNET_NAME \
  --registration-enabled false
 
  ````

````
az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "privatelink.azurecr.io" \
  --name ACRDNSHubLink \
  --virtual-network $HUB_VNET_NAME \
  --registration-enabled false

````

### Create a private registry endpoint 
REGISTRY_ID=$(

````
az acr show --name acraksbl \
  --query 'id' --output tsv)

````

````
az network private-endpoint create \
    --name ACRPrivateEndpoint \
    --resource-group $RG \
    --vnet-name $SPOKE_VNET_NAME \
    --subnet endpoints-subnet \
    --private-connection-resource-id $REGISTRY_ID \
    --group-ids registry \
    --connection-name PrivateACRConnection
````

#### Configure DNS record 

### get endpoint IP configuration
NETWORK_INTERFACE_ID=$(

````
az network private-endpoint show \
  --name ACRPrivateEndpoint \
  --resource-group $RG \
  --query 'networkInterfaces[0].id' \
  --output tsv)

 ```` 

### fetch the container registry private IP address
REGISTRY_PRIVATE_IP=$(

````
az network nic show --ids $NETWORK_INTERFACE_ID --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry'].privateIPAddress" -o tsv)
````
### fetch the data endpoint IP address of the container registry

DATA_ENDPOINT_PRIVATE_IP=$(

````
az network nic show --ids $NETWORK_INTERFACE_ID --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry_data_westeurope'].privateIPAddress" -o tsv)
````

### fetch the FQDN associated with the registry and data endpoint

REGISTRY_FQDN=$(

````
az network nic show \
  --ids $NETWORK_INTERFACE_ID \
  --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry'].privateLinkConnectionProperties.fqdns" \
  --output tsv)
````
DATA_ENDPOINT_FQDN=$(

````
az network nic show \
  --ids $NETWORK_INTERFACE_ID \
  --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry_data_westeurope'].privateLinkConnectionProperties.fqdns" \
  --output tsv)
````


#Create DNS records in the private zone



````
az network private-dns record-set a create \
  --name acraksbl \
  --zone-name privatelink.azurecr.io \
  --resource-group $RG

  ````

### Specify registry region in data endpoint name


````
az network private-dns record-set a create \
  --name acraksbl.westeurope.data \
  --zone-name privatelink.azurecr.io \
  --resource-group $RG

````
  
### create the A records for the registry endpoint and data endpoint



````
az network private-dns record-set a add-record \
  --record-set-name acraksbl \
  --zone-name privatelink.azurecr.io \
  --resource-group $RG \
  --ipv4-address $REGISTRY_PRIVATE_IP

````

### Specify registry region in data endpoint name


````
az network private-dns record-set a add-record \
  --record-set-name acraksbl.westeurope.data \
  --zone-name privatelink.azurecr.io \
  --resource-group $RG \
  --ipv4-address $DATA_ENDPOINT_PRIVATE_IP

````

#### Create Application Gateway

### Create public IP address with a domain name associated to the PIP resource


````
az network public-ip create -g $RG -n AGPublicIPAddress --dns-name mvcnstudent01 --allocation-method Static --sku Standard --location westeurope
````

### Create WAF policy 


````
az network application-gateway waf-policy create --name ApplicationGatewayWAFPolicy --resource-group $RG
````

### Create application Gateway 

  

````
az network application-gateway create \
  --name AppGateway \
  --location westeurope \
  --resource-group rg_baseline \
  --vnet-name spoke-vnet \
  --subnet app-gw-subnet \
  --capacity 1 \
  --sku WAF_v2 \
  --http-settings-cookie-based-affinity Disabled \
  --frontend-port 443 \
  --http-settings-port 80 \
  --http-settings-protocol Http \
  --priority "1" \
  --public-ip-address AGPublicIPAddress \
  --cert-file appgwcert.pfx \
  --cert-password "<PASSWORD>" \
  --waf-policy ApplicationGatewayWAFPolicy \
  --servers 10.1.3.4
````
### Create Health probe
````
 az network application-gateway probe create \
    --gateway-name AppGateway \
    --resource-group rg_baseline \
    --name health-probe \
    --protocol Http \
    --path / \
    --interval 30 \
    --timeout 120 \
    --threshold 3 \
    --host 127.0.0.1
````

### Associate the health probe to the backend pool.
````
az network application-gateway http-settings update -g rg_baseline --gateway-name AppGateway -n appGatewayBackendHttpSettings --probe health-probe
````
