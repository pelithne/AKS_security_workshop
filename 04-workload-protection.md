# 4.0 Deploy app with Workload Identity

## 4.1 Introduction
Workload identity is important as it allows you to securely access Azure resources from your Kubernetes applications using Azure AD identities. This way, you can avoid storing and managing credentials in your cluster, and instead rely on the native Kubernetes mechanisms to federate with external identity providers. Workload identity also simplifies the authentication process for your applications, as they can use the Azure Identity client libraries or MSAL to seamlessly obtain tokens from Azure AD and access Azure resources. Workload identity is the recommended way to authenticate with Azure AD from AKS pods, as it replaces the deprecated pod identity feature that had some limitations and complexities. more information about workload identity can be found here: [Use Azure AD workload identity with Azure Kubernetes Service (AKS)](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview?tabs=dotnet)


In this tutorial, you will learn how to:

- Build an application and store it in Azure Container Registry
- Activate OpenID Connect (OIDC) issuer on Azure Kubernetes Service (AKS) cluster (or create a new cluster with OIDC activated)
- Create a secret and store it in Azure Key Vault
- Create an Azure Active Directory (Azure AD) managed identity
- Connect the managed identity to a Kubernetes service account with token federation
- Deploy a workload and verify authentication to Key Vault with the workload identity

To begin, you need to create some environment variables that will be used throughout the tutorial.

## 4.2 Deployment
In this tutorial, you will learn how to configure environment variables for various Azure resources that are required for your application. The environment variables will store the names and locations of the following resources:

* Azure Kubernetes Service (AKS) namespace: This is the logical grouping of your Kubernetes objects within the AKS cluster.
* Azure Key Vault name: This is the name of the secure storage service that holds your secrets, keys, and certificates.
* Azure Identity name: This is the name of the managed identity that grants your application access to the Azure resources.

By setting these environment variables, you will be able to use them in your code and scripts without hard-coding the values. This will make your application more secure and maintainable.

### 4.2.1 Prepare Environment Variables for infrastructure

First, lets create a few environment variables, for ease of use

> **_! Note:_** The Azure keyvault name is a global name that must be unique, it is a 3-24 characther string that can contain only 0-9,a-z,A-Z and not consecutive. They keyvault name is part of the DNS name of the the key vault service endpoint. **Thus it is important that you create a unique name else the deployment will fail**. You need to assign a distinct value to the **KEYVAULT_NAME** environment variable.
````
FRONTEND_NAMESPACE="frontend"
BACKEND_NAMESPACE="backend"
SERVICE_ACCOUNT_NAME="workload-identity-sa"
SUBSCRIPTION="$(az account show --query id --output tsv)"
USER_ASSIGNED_IDENTITY_NAME="keyvaultreader"
FEDERATED_IDENTITY_CREDENTIAL_NAME="keyvaultfederated"
KEYVAULT_NAME="<DEFINE A KEYVAULT NAME HERE>"
KEYVAULT_SECRET_NAME="redissecret"
````

### 4.2.2 Update AKS cluster with OIDC issuer

1) Enable the existing cluster to use OpenID connect (OIDC) as an authentication protocol for Kubernetes API server. This allows the cluster to integrate with Azure Active Directory (Microsoft Entra ID) and other identity providers that support OIDC.

````bash
az aks update -g $RG -n $AKS_CLUSTER_NAME  --enable-oidc-issuer 

````

2) Get the OICD issuer URL. Query the AKS cluster for the OICD issuer URL with the following command, which stores the reult in an environment variable.

````bash
AKS_OIDC_ISSUER="$(az aks show -n $AKS_CLUSTER_NAME -g $RG  --query "oidcIssuerProfile.issuerUrl" -otsv)"
````

The variable should contain the Issuer URL similar to the following:
 ````https://eastus.oic.prod-aks.azure.com/9e08065f-6106-4526-9b01-d6c64753fe02/9a518161-4400-4e57-9913-d8d82344b504/````

### 4.2.3 Create Azure Keyvault

1) Create the Azure Keyvault instance:


````bash
az keyvault create -n $KEYVAULT_NAME -g $RG -l $LOCATION
````
2) In this step we need to further secure our Key vault, we need to deny as a default action for the network access policy, which means that only the specified IP addresses or virtual networks can access the key vault, we want to restrict it to certain virtual networks only.

````bash
az keyvault update -n $KEYVAULT_NAME -g $RG --default-action deny
````

3) Create a private DNS zone for the Azure Keyvault.

````bash
az network private-dns zone create --resource-group $RG --name privatelink.vaultcore.azure.net
````

4) Link the Private DNS Zone to the HUB and SPOKE Virtual Network

````bash
az network private-dns link vnet create --resource-group $RG --virtual-network $HUB_VNET_NAME --zone-name privatelink.vaultcore.azure.net --name hubvnetkvdnsconfig --registration-enabled false
````
````bash
az network private-dns link vnet create --resource-group $RG --virtual-network $SPOKE_VNET_NAME --zone-name privatelink.vaultcore.azure.net --name spokevnetkvdnsconfig --registration-enabled false
````

5) Create a private endpoint for the Keyvault

First we need to obtain the Keyvault ID in order to deploy the private endpoint.

````bash
KEYVAULT_ID=$(az keyvault show --name $KEYVAULT_NAME \
  --query 'id' --output tsv)
````
Create the private endpoint in endpoint subnet.

````bash
az network private-endpoint create --resource-group $RG --vnet-name $SPOKE_VNET_NAME --subnet $ENDPOINTS_SUBNET_NAME --name KVPrivateEndpoint --private-connection-resource-id $KEYVAULT_ID --group-ids vault --connection-name PrivateKVConnection --location $LOCATION
````

6) Fetch IP of the private endpoint and create an "A" DNS record in the private DNS zone.

Obtain the IP address of the private endpoint NIC card.
 ````bash
KV_PRIVATE_IP=$(az network private-endpoint show -g $RG -n KVPrivateEndpoint \
  --query 'customDnsConfigs[0].ipAddresses[0]' --output tsv)
 ````

Create the A record in DNS zone. and point it to the private endpoint IP of the Keyvault.

````bash
  az network private-dns record-set a create \
  --name $KEYVAULT_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --resource-group $RG
````
Point the "A" record to the private endpoint IP of the Keyvault.
````bash
 az network private-dns record-set a add-record -g $RG -z "privatelink.vaultcore.azure.net" -n $KEYVAULT_NAME -a $KV_PRIVATE_IP
 ````

7) Validate the private link connection from Jumpbox

8) Navigate to the Azure portal at [https://portal.azure.com](https://portal.azure.com) and enter your login credentials.
9) Once logged in, locate and select your **resource group** where the Jumpbox has been deployed.
10) Within your resource group, find and click on the **Jumpbox VM**.
11) In the left-hand side menu, under the **Operations** section, select ‘Bastion’.
12) Enter the **credentials** for the Jumpbox VM and verify that you can log in successfully.
13) Once successfully logged in to the jumpbox **login to Azure** if you have not already done so in previous steps.
14) in the command line type the following command and ensure it returns the **private ip address of the private endpoint**.

````bash
dig <KEYVAULT NAME>.vault.azure.net
````
Example output:
````bash
azureuser@Jumpbox-VM:~$ dig alibengtssonkeyvault.vault.azure.net

; <<>> DiG 9.18.12-0ubuntu0.22.04.3-Ubuntu <<>> alibengtssonkeyvault.vault.azure.net
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 22014
;; flags: qr rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 65494
;; QUESTION SECTION:
;alibengtssonkeyvault.vault.azure.net. IN A

;; ANSWER SECTION:
alibengtssonkeyvault.vault.azure.net. 60 IN CNAME alibengtssonkeyvault.privatelink.vaultcore.azure.net.
alibengtssonkeyvault.privatelink.vaultcore.azure.net. 1800 IN A10.1.2.6

;; Query time: 12 msec
;; SERVER: 127.0.0.53#53(127.0.0.53) (UDP)
;; WHEN: Sun Oct 08 16:41:05 UTC 2023
;; MSG SIZE  rcvd: 138

````

You have successfully achieved the secure AKS baseline by deploying Azure Key Vault and integrating it with Azure Private Link. This completes the targeted architecture that ensures the security and privacy **baseline** of your AKS cluster and its secrets.

![Screenshot](/images/hubandspokewithpeeringBastionJumpboxFirewallaksvirtualnetlinkandacrandinternalloadbalancerandapplicationgwandkeyvault.jpg)

 ### Add a secret to Azure Keyvault

Create a secret in the keyvault. This is the secret that will be used by the frontend application to connect to the (redis) backend.

 ````
 az keyvault secret set --vault-name "${KEYVAULT_NAME}" --name "${KEYVAULT_SECRET_NAME}" --value 'redispassword'
 ````

### Add the Key Vault URL to the environment variable *KEYVAULT_URL*
 ````
 export KEYVAULT_URL="$(az keyvault show -g "${RESOURCE_GROUP}" -n ${KEYVAULT_NAME} --query properties.vaultUri -o tsv)"
 ````

 ### Create a managed identity and grant permissions to access the secret

Create a User Managed Identity. We will give this identity *GET access* to the keyvault, and later associate it with a Kubernetes service account. 

 ````
 az account set --subscription "${SUBSCRIPTION}"
 az identity create --name "${USER_ASSIGNED_IDENTITY_NAME}" --resource-group "${RESOURCE_GROUP}" --location "${LOCATION}" --subscription "${SUBSCRIPTION}"

 ````

 Set an access policy for the managed identity to access the Key Vault

 ````
 export USER_ASSIGNED_CLIENT_ID="$(az identity show --resource-group "${RESOURCE_GROUP}" --name "${USER_ASSIGNED_IDENTITY_NAME}" --query 'clientId' -otsv)"

 az keyvault set-policy --name "${KEYVAULT_NAME}" --secret-permissions get --spn "${USER_ASSIGNED_CLIENT_ID}"
 ````


 ### Create Kubernetes service account

First, connect to the cluster if not already connected
 
 ````
 az aks get-credentials -n myAKSCluster -g "${RESOURCE_GROUP}"
 ````

#### Create service account

The service account should exist in the frontend namespace, because it's the frontend service that will use that service account to get the credentials to connect to the (redis) backend service.

First create the namespace

````
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: $FRONTEND_NAMESPACE
  labels:
    name: $FRONTEND_NAMESPACE
EOF
````

Then create a service account in that namespace. Notice the annotation for *workload identity*
````
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: $FRONTEND_NAMESPACE
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
  name: ${SERVICE_ACCOUNT_NAME}
EOF
````


### Establish federated identity credential

In this step we connect the service account with the user defined managed identity, using a federated credential.

````
az identity federated-credential create --name ${FEDERATED_IDENTITY_CREDENTIAL_NAME} --identity-name ${USER_ASSIGNED_IDENTITY_NAME} --resource-group ${RESOURCE_GROUP} --issuer ${AKS_OIDC_ISSUER} --subject system:serviceaccount:${FRONTEND_NAMESPACE}:${SERVICE_ACCOUNT_NAME}
````

### Build the application

Now its time to build the application. In order to do so, first clone the applications repository:

````
git clone git@github.com:pelithne/azure-voting-app-redis.git
````
Then CD into the directory where the (python) application resides and issue the acr build command

#### Note: if the ACR is private, the *acr build* command is not available. Instead the *docker build* command can be used.

````
cd azure-voting-app-redis
cd azure-vote 
az acr build --image azure-vote:v1 --registry $ACRNAME .

````



### Deploy the application

We want to create some separation between the frontend and backend, by deploying them into different namespaces. Later we will add more separation by introducing network policies in the cluster to allow/disallow traffic between specific namespaces.


First, create the backend namespace


````
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: backend
  labels:
    name: backend
EOF
````

cd only neccesery if using yaml files
````
cd ..
````

Backend
````
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-back
  namespace: $BACKEND_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-back
  template:
    metadata:
      labels:
        app: azure-vote-back
    spec:
      nodeSelector:
        "kubernetes.io/os": linux
      containers:
      - name: azure-vote-back
        image: mcr.microsoft.com/oss/bitnami/redis:6.0.8
        ports:
        - containerPort: 6379
          name: redis
        env:
        - name: REDIS_PASSWORD
          value: "redispassword"
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-back
  namespace: $BACKEND_NAMESPACE
spec:
  ports:
  - port: 6379
  selector:
    app: azure-vote-back
EOF
````


Then create the frontend. In this case we already created the frontend namespace in an earlier step.

````
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-front
  namespace: $FRONTEND_NAMESPACE
  labels:
    azure.workload.identity/use: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-front
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  minReadySeconds: 5 
  template:
    metadata:
      labels:
        app: azure-vote-front
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: $SERVICE_ACCOUNT_NAME
      nodeSelector:
        "kubernetes.io/os": linux
      containers:
      - name: azure-vote-front
        image: pelithnepubacr.azurecr.io/azure-vote:v19
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 250m
          limits:
            cpu: 500m
        env:
        - name: REDIS
          value: "azure-vote-back.backend"
        - name: KEYVAULT_URL
          value: $KEYVAULT_URL
        - name: SECRET_NAME
          value: $KEYVAULT_SECRET_NAME
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-front
  namespace: $FRONTEND_NAMESPACE
spec:
  type: LoadBalancer
  ports:
  - port: 80
  selector:
    app: azure-vote-front

EOF
````


### Network policies
The cluster is deployed using kubenet CNI, which means we have to use Calico Network Policies. 

````
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-backend-access2
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: azure-vote-back
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: frontend
    ports: []
EOF
````






cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: backend
spec:
  podSelector:
     matchLabels: {}
EOF