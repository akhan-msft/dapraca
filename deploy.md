# Deployment Guide

This guide covers all paths to deploy **dapraca** (Red Dog Order Management) to Azure, from a fully automated GitHub Actions pipeline to step-by-step manual deployment.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [One-Time Setup: Azure Service Principal (OIDC)](#one-time-setup-azure-service-principal-oidc)
3. [GitHub Repository Secrets and Variables](#github-repository-secrets-and-variables)
4. [GitHub Actions Pipeline](#github-actions-pipeline)
5. [Manual Deployment with `azd`](#manual-deployment-with-azd)
6. [Deploying Individual Services](#deploying-individual-services)
7. [Local Development](#local-development)
8. [Tearing Down the Environment](#tearing-down-the-environment)
9. [Architecture Notes](#architecture-notes)

---

## Prerequisites

Install the following tools before deploying:

| Tool | Version | Install |
|------|---------|---------|
| [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) | Latest | `winget install microsoft.azd` or see link |
| [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) | ≥ 2.60 | `winget install Microsoft.AzureCLI` |
| [Docker Desktop](https://www.docker.com/products/docker-desktop) | Latest | Required for image builds |
| [Java 21 (Temurin)](https://adoptium.net/) | 21 LTS | Required for Java service builds |
| [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) | 8.x | Required for receipt-service build |
| [Node.js](https://nodejs.org/) | 20 LTS | Required for UI build |
| [Python](https://www.python.org/downloads/) | 3.12 | Required for bootstrap service |

---

## One-Time Setup: Azure Service Principal (OIDC)

The GitHub Actions CD pipeline authenticates to Azure using **OIDC federated credentials** (no long-lived secrets). Run this once per environment.

### 1. Login to Azure

```bash
az login --tenant <YOUR_TENANT_ID>
az account set --subscription <YOUR_SUBSCRIPTION_ID>
```

> **Note:** If your subscription is in a non-default tenant, you must specify the tenant ID explicitly.

### 2. Create a Service Principal

```bash
# Create the service principal (contributor on the subscription)
az ad sp create-for-rbac \
  --name "sp-dapraca-github" \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID> \
  --json-auth
```

Save the JSON output — you will need `clientId`, `tenantId`, and `subscriptionId` for GitHub secrets.

### 3. Add Federated OIDC Credential

This allows GitHub Actions to authenticate without a client secret.

```bash
# Get the service principal's object ID
SP_OBJECT_ID=$(az ad sp show --id <CLIENT_ID_FROM_ABOVE> --query id -o tsv)

# Add federated credential for the master branch
az ad app federated-credential create \
  --id $SP_OBJECT_ID \
  --parameters '{
    "name": "github-dapraca-master",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:ref:refs/heads/master",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Replace `<YOUR_GITHUB_ORG>/<YOUR_REPO>` with your GitHub org and repo name (e.g., `akhan-msft/dapraca`).

### 4. Grant Additional RBAC Roles

The service principal needs User Access Administrator to assign roles during `azd provision`:

```bash
az role assignment create \
  --assignee <CLIENT_ID> \
  --role "User Access Administrator" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>
```

---

## GitHub Repository Secrets and Variables

In your GitHub repository, go to **Settings → Secrets and variables → Actions** and add:

### Secrets (Settings → Secrets → Actions)

| Secret Name | Value |
|-------------|-------|
| `AZURE_CLIENT_ID` | `clientId` from the service principal output |
| `AZURE_TENANT_ID` | `tenantId` from the service principal output |
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID |

### Variables (Settings → Variables → Actions) — Optional

| Variable Name | Default | Description |
|---------------|---------|-------------|
| `AZURE_ENV_NAME` | `dapraca-dev` | Name prefix for all Azure resources |
| `AZURE_LOCATION` | `eastus` | Azure region for deployment |

---

## GitHub Actions Pipeline

The repo contains two workflows:

### CI — `.github/workflows/ci.yml`

**Triggers:** Push or PR to `master` or `main`

Runs in parallel across all services:

| Job | What it does |
|-----|-------------|
| `java-services` (matrix) | `mvn verify` + Docker build validate for order/accounting/loyalty/makeline services |
| `receipt-service` | `dotnet restore`, `dotnet build`, `dotnet test` + Docker build |
| `bootstrap` | `pip install`, `ruff` lint + Docker build |
| `ui` | `npm ci`, React build, BFF install + Docker build |
| `bicep-lint` | `az bicep build` to validate Bicep templates |

### CD — `.github/workflows/cd.yml`

**Triggers:** Push to `master` or `main`

Runs `azd up` which:
1. Builds Docker images for all 7 services
2. Pushes images to Azure Container Registry
3. Provisions all Azure infrastructure via Bicep (idempotent)
4. Deploys all Container Apps with the new images

The CD pipeline runs in sequence after CI. A failed CI run does NOT trigger CD.

> **First run:** The CD pipeline will provision all Azure resources from scratch (~15–20 minutes). Subsequent runs are incremental (~5 minutes for service-only changes).

### Viewing the Pipeline Output

Navigate to **Actions** tab in your GitHub repository to monitor progress. The final step outputs the UI URL:

```
https://ui.<unique-id>.<region>.azurecontainerapps.io/
```

---

## Manual Deployment with `azd`

Use this approach to deploy directly from your local machine without GitHub Actions.

### 1. Login

```bash
# If your subscription is in a non-default tenant, specify the tenant
azd auth login --tenant-id <YOUR_TENANT_ID>

# Standard login (default tenant)
azd auth login
```

### 2. Initialize the Environment

```bash
cd dapraca

# Create a new azd environment
azd env new dapraca-dev

# Set the subscription and region
azd env set AZURE_SUBSCRIPTION_ID <YOUR_SUBSCRIPTION_ID>
azd env set AZURE_LOCATION westus3    # or your preferred region
azd env set AZURE_PRINCIPAL_ID $(az ad signed-in-user show --query id -o tsv)
```

### 3. Provision Infrastructure + Deploy Services

```bash
azd up
```

This single command:
- Builds all Docker images locally
- Provisions all Azure resources (ACR, ACA Environment, Service Bus, SQL, Cosmos DB, Redis, Key Vault, Storage, Managed Identity, App Insights)
- Pushes images to ACR
- Deploys all Container Apps

> **Expected duration:** 15–25 minutes on first run.

### 4. Get the UI URL

```bash
azd show
```

Or navigate to the Azure Portal → Container Apps → `ca-ui-*` → Application URL.

---

## Deploying Individual Services

After the initial `azd up`, you can redeploy a single service without reprovisioning all infrastructure:

```bash
# Deploy only the UI
azd deploy --service ui

# Deploy only the makeline service
azd deploy --service makeline-service

# Deploy only the accounting service
azd deploy --service accounting-service
```

Available service names (matching `azure.yaml`):
- `ui`
- `order-service`
- `accounting-service`
- `loyalty-service`
- `makeline-service`
- `receipt-service`
- `bootstrap`

> **Tip:** After running `azd provision` alone (e.g., for Bicep changes), always follow with `azd deploy` or `azd up` to restore the correct service images. ACA infrastructure-only updates reset container images to a placeholder.

---

## Local Development

### Option A: Docker Compose (Recommended)

Run all services locally with Dapr sidecars using Docker Compose:

```bash
docker compose up
```

The `docker-compose.yml` in the repo root spins up:
- All 7 services with Dapr sidecars
- Redis (Makeline state store)
- Zipkin (tracing)
- Azure service emulators (Azurite for Storage, Cosmos DB emulator)

Access the UI at: `http://localhost:3000`

### Option B: Individual Services

Each service can be run independently for development:

**Java services (Spring Boot):**
```bash
cd src/order-service
mvn spring-boot:run
```

**Receipt service (.NET):**
```bash
cd src/receipt-service/src/ReceiptService
dotnet run
```

**UI (React + Node BFF):**
```bash
cd src/ui/client && npm ci && npm run build
cd ../         && npm ci && node server/index.js
```

**Bootstrap (Python):**
```bash
cd src/bootstrap
pip install -r requirements.txt
python main.py
```

See [docs/local-dev.md](docs/local-dev.md) for detailed local dev setup with Dapr standalone.

---

## Tearing Down the Environment

```bash
# Destroy all Azure resources created by azd
azd down

# Add --purge to also permanently delete Key Vault (skip soft-delete)
azd down --purge
```

> **Warning:** This deletes all data including the SQL database, Cosmos DB, and Blob Storage receipts.

---

## Architecture Notes

### Why `azd up` and not Terraform?

The project uses [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/) which orchestrates Bicep-based provisioning + container image build/push/deploy in a single command. This is the recommended approach for ACA + Dapr applications.

### Workload Profiles

Two ACA workload profiles are used:
- **Dedicated D4** — `order-service` and `makeline-service` for low-latency, consistent performance
- **Consumption** — All other services (scale-to-zero, cost-optimized)

### Dapr Components

All four Dapr components are provisioned as part of `azd provision` via `infra/modules/daprComponents.bicep`:

| Component | Type | Azure Resource |
|-----------|------|----------------|
| `pubsub-servicebus` | Pub/Sub | Azure Service Bus |
| `statestore-redis` | State | Azure Managed Redis |
| `statestore-cosmosdb` | State | Azure Cosmos DB |
| `binding-blobstorage` | Output Binding | Azure Blob Storage |

All components authenticate via **Managed Identity** — no connection strings.

### KEDA Autoscaling

Each service has KEDA scalers configured in the Container App Bicep:
- **Service Bus topic length** scaler — scales subscribers based on message backlog
- **HTTP** scaler — scales `order-service` and `ui` based on HTTP concurrency
- **Scale to zero** — all Consumption-profile services scale to zero when idle

### Security

- All secrets are stored in **Azure Key Vault** and referenced as ACA secret env vars
- **User-assigned Managed Identity** is shared across all services
- Service Bus has local auth disabled (`disableLocalAuth: true`) — only RBAC
- SQL Server is configured with **Entra ID-only authentication** (no SQL password)

### Observability

All services export telemetry to **Application Insights** via OpenTelemetry:
```
Application Insights → Application Map shows full service dependency graph
```

Navigate to the App Insights resource in the Azure Portal to view:
- **Application Map** — end-to-end service topology
- **Live Metrics** — real-time request rate and performance
- **Transaction Search** — trace individual orders end-to-end
- **Logs** — KQL queries across all service logs

---

## Troubleshooting

### `azd provision` resets service images

If you run `azd provision` alone (e.g., after a Bicep change), the Container App images are reset to a placeholder. Always follow with:
```bash
azd deploy
```

### Services fail to start after first provision

The `bootstrap` service runs SQL schema initialization. If it fails, check its logs:
```bash
az containerapp logs show \
  --name ca-bootstrap-<suffix> \
  --resource-group <your-rg> \
  --type system \
  --follow
```

### Dapr pub/sub not working

Dapr components are loaded by the sidecar at startup. If you add or modify a Dapr component, restart the affected Container Apps:
```bash
az containerapp revision restart \
  --name ca-<service>-<suffix> \
  --resource-group <your-rg> \
  --revision <revision-name>
```

### SQL connection errors (Managed Identity)

Ensure the Managed Identity has been added as an Entra ID user in the SQL database. The bootstrap service handles this, but you can also run manually:
```sql
CREATE USER [<managed-identity-name>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [<managed-identity-name>];
```

### Checking service logs

```bash
# Stream logs for a specific service
az containerapp logs show \
  --name ca-<service>-<suffix> \
  --resource-group rg-dapraca-<region> \
  --follow

# Or use azd
azd monitor
```
