# Getting Started with Minikube

A simple Kubernetes application running on Minikube: Nginx serving a static page that proxies API requests to a FastAPI backend.

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/)

## Project Structure

```
backend/     — FastAPI app (GET /api/hello returns {"message": "Hello, World!"})
frontend/    — Nginx serving static HTML and proxying /api/* to the backend
k8s/         — Kubernetes manifests (Deployments + Services)
deploy.sh    — Build & deploy script
.github/workflows/
  ci.yml     — CI: tests the app on minikube
  deploy-aca.yml — CD: deploys to Azure Container Apps after CI passes
```

## Local Development (Minikube)

1. Start minikube:

   ```bash
   minikube start
   ```

2. Deploy the application:

   ```bash
   ./deploy.sh
   ```

   This builds Docker images inside minikube, applies the Kubernetes manifests, and waits for pods to be ready.

### Open in Browser

```bash
minikube service frontend --url
```

Open the printed URL in your browser. Click the button to call the FastAPI backend.

### Dashboard

```bash
minikube dashboard
```

### Useful Commands

```bash
kubectl get pods
kubectl logs -l app=backend
kubectl logs -l app=frontend
```

### Cleanup

```bash
kubectl delete -f k8s/
minikube stop
minikube delete
```

---

## Azure Deployment

The app is deployed to [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview)
and exposed at `https://azure.romanpavelka.cz`. Pushes to `main` trigger CI, and on success the deploy workflow
updates the running containers.

### One-Time Azure Setup

Install [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), then sign up and log in:

```bash
# Sign up at https://azure.microsoft.com/free/ if you don't have an account

az login
az provider register --namespace Microsoft.ContainerRegistry --wait
az provider register --namespace Microsoft.OperationalInsights --wait
```

#### 1. Set variables

```bash
RESOURCE_GROUP="rg-getting-started"
LOCATION="polandcentral"
ACR_NAME="gettingstartedcr"      # must be globally unique, lowercase, no dashes
ENVIRONMENT="cae-getting-started"
```

#### 2. Create resource group and container registry

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION

az acr create \
  --name $ACR_NAME \
  --resource-group $RESOURCE_GROUP \
  --sku Basic \
  --admin-enabled true
```

#### 3. Build and push initial images

```bash
az acr login --name $ACR_NAME

docker build -t $ACR_NAME.azurecr.io/backend:latest  backend/
docker build -t $ACR_NAME.azurecr.io/frontend:latest frontend/

docker push $ACR_NAME.azurecr.io/backend:latest
docker push $ACR_NAME.azurecr.io/frontend:latest
```

#### 4. Create Container Apps environment

```bash
az containerapp env create \
  --name $ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

#### 5. Create backend (internal)

```bash
az containerapp create \
  --name backend \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image $ACR_NAME.azurecr.io/backend:latest \
  --registry-server $ACR_NAME.azurecr.io \
  --registry-identity system \
  --target-port 8000 \
  --ingress internal \
  --transport http \
  --min-replicas 1 \
  --max-replicas 3
```

#### 6. Create frontend (external)

The frontend needs `BACKEND_URL` set to the internal backend URL. In Container Apps, internal apps are reachable by name on port 80:

```bash
az containerapp create \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image $ACR_NAME.azurecr.io/frontend:latest \
  --registry-server $ACR_NAME.azurecr.io \
  --registry-identity system \
  --target-port 80 \
  --ingress external \
  --transport http \
  --min-replicas 1 \
  --max-replicas 3 \
  --env-vars "BACKEND_URL=http://backend"
```

#### 7. Custom domain (test domain: azure.romanpavelka.cz)

Get the frontend's auto-assigned FQDN and the environment's verification ID:

```bash
# Get the frontend FQDN
az containerapp show \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.configuration.ingress.fqdn' -o tsv

# Get the domain verification ID
az containerapp show \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --query 'properties.customDomainVerificationId' -o tsv
```

Add these DNS records at your domain registrar for `romanpavelka.cz`:

| Type  | Name    | Value                                |
|-------|---------|--------------------------------------|
| CNAME | `azure` | `<frontend-fqdn>.` from above (trailing dot required) |
| TXT   | `asuid.azure` | `<customDomainVerificationId>` |

Verify DNS propagation before proceeding:

```bash
dig azure.romanpavelka.cz CNAME
dig asuid.azure.romanpavelka.cz TXT
```

Once the records resolve correctly, bind the domain with a managed certificate:

```bash
az containerapp hostname add \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --hostname azure.romanpavelka.cz

az containerapp hostname bind \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --hostname azure.romanpavelka.cz \
  --environment $ENVIRONMENT \
  --validation-method CNAME
```

### GitHub Actions Setup (OIDC)

The deploy workflow uses OpenID Connect (OIDC) — no long-lived secrets needed.

#### 1. Create a service principal

```bash
APP_NAME="github-deploy-getting-started"

# Create app registration and service principal
az ad app create --display-name $APP_NAME
APP_ID=$(az ad app list --display-name $APP_NAME --query '[0].appId' -o tsv)
az ad sp create --id $APP_ID
SP_OBJECT_ID=$(az ad sp list --filter "appId eq '$APP_ID'" --query '[0].id' -o tsv)
```

#### 2. Grant permissions

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Contributor on the resource group (deploy container apps)
az role assignment create \
  --assignee-object-id $SP_OBJECT_ID \
  --assignee-principal-type ServicePrincipal \
  --role Contributor \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP

# AcrPush on the container registry
ACR_ID=$(az acr show --name $ACR_NAME --query id -o tsv)
az role assignment create \
  --assignee-object-id $SP_OBJECT_ID \
  --assignee-principal-type ServicePrincipal \
  --role AcrPush \
  --scope $ACR_ID
```

#### 3. Add OIDC federated credential

```bash
GITHUB_ORG="<your-github-username>"
GITHUB_REPO="getting-started-minikube"

az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-main-deploy",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':environment:production-aca",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

#### 4. Configure GitHub repository

Add these as **repository secrets** (Settings > Secrets and variables > Actions):

| Secret                    | Value                                     |
|---------------------------|-------------------------------------------|
| `AZURE_CLIENT_ID`        | `$APP_ID` from above                      |
| `AZURE_TENANT_ID`        | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID`  | `az account show --query id -o tsv`       |

Add these as **repository variables**:

| Variable               | Value                |
|------------------------|----------------------|
| `ACR_NAME`             | `gettingstartedcr`   |
| `AZURE_RESOURCE_GROUP` | `rg-getting-started` |

Also create a GitHub **environment** called `production-aca` (Settings > Environments) — this is referenced
by the deploy workflow and the OIDC federated credential.

### Authentication (Azure Easy Auth)

The frontend uses [Azure Container Apps built-in authentication](https://learn.microsoft.com/en-us/azure/container-apps/authentication)
(Easy Auth) to require sign-in via Microsoft or Google accounts. No application code changes are needed — authentication is handled
at the platform level before requests reach the container.

#### 1. Register a Microsoft identity provider

Create an app registration in Microsoft Entra ID:

```bash
AUTH_APP_NAME="getting-started-auth"

az ad app create \
  --display-name $AUTH_APP_NAME \
  --sign-in-audience AzureADandPersonalMicrosoftAccount \
  --web-redirect-uris "https://azure.romanpavelka.cz/.auth/login/aad/callback"

AUTH_APP_ID=$(az ad app list --display-name $AUTH_APP_NAME --query '[0].appId' -o tsv)
```

Create a client secret:

```bash
AUTH_CLIENT_SECRET=$(az ad app credential reset \
  --id $AUTH_APP_ID \
  --display-name "easy-auth" \
  --query password -o tsv)

echo "Save this secret — you won't be able to see it again: $AUTH_CLIENT_SECRET"
```

#### 2. Register a Google identity provider

1. Go to the [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Create a new project (or select an existing one)
3. Go to **APIs & Services > Credentials > Create Credentials > OAuth client ID**
4. Set application type to **Web application**
5. Add authorized redirect URI: `https://azure.romanpavelka.cz/.auth/login/google/callback`
6. Note the **Client ID** and **Client Secret**

#### 3. Enable authentication on the frontend Container App

```bash
GOOGLE_CLIENT_ID="<your-google-client-id>"
GOOGLE_CLIENT_SECRET="<your-google-client-secret>"

az containerapp auth update \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --unauthenticated-client-action AllowAnonymous \
  --enabled true
```

Add the Microsoft identity provider:

```bash
az containerapp auth microsoft update \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --client-id $AUTH_APP_ID \
  --client-secret $AUTH_CLIENT_SECRET \
  --issuer "https://login.microsoftonline.com/common/v2.0" \
  --yes
```

Add the Google identity provider:

```bash
az containerapp auth google update \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --client-id $GOOGLE_CLIENT_ID \
  --client-secret $GOOGLE_CLIENT_SECRET \
  --yes
```

#### 4. Restart the frontend to apply secret changes

After updating auth configuration or secrets, the active revision must be restarted:

```bash
az containerapp revision restart \
  --name frontend \
  --resource-group $RESOURCE_GROUP \
  --revision $(az containerapp revision list \
    --name frontend \
    --resource-group $RESOURCE_GROUP \
    --query '[0].name' -o tsv)
```

#### 5. Verify

Open `https://azure.romanpavelka.cz` in a private browser window. You should be redirected to sign in
with a Microsoft account. To sign in with Google instead, navigate directly
to `https://azure.romanpavelka.cz/.auth/login/google`.

> **Tip:** To inspect the logged-in user's claims, call `https://azure.romanpavelka.cz/.auth/me` — this
returns the token claims as JSON without any backend changes.
