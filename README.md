# dapraca — Red Dog Order Management on Azure Container Apps + Dapr

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Azure Developer CLI](https://img.shields.io/badge/azd-compatible-blue)](https://learn.microsoft.com/azure/developer/azure-developer-cli/)

> **Companion demo** for the Microsoft Learn architecture article:  
> [Deploy microservices with Azure Container Apps and Dapr](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/serverless/microservices-with-container-apps-dapr)

## Overview

This monorepo implements the **Red Dog** fictitious order management system — a polyglot microservices application running on [Azure Container Apps (ACA)](https://learn.microsoft.com/azure/container-apps/overview) with:

- 🔌 **[Dapr](https://dapr.io/)** building blocks: Pub/Sub, State, and Output Bindings
- ⚡ **[KEDA](https://keda.sh/)** event-driven autoscaling (scale to zero)
- 🧩 **[ACA Workload Profiles](https://learn.microsoft.com/azure/container-apps/workload-profiles-overview)**: Dedicated (low-latency) + Consumption
- 🔐 **Managed Identity** + **Azure Key Vault** (zero secrets in code)
- 📊 **OpenTelemetry → Application Insights** (distributed tracing, metrics, logs)
- 🌐 **Native ACA Envoy ingress** — no Traefik; UI is the single external entry point

## Architecture

```
[Browser]
    │ HTTPS (ACA Envoy)
    ▼
[ui — ReactJS + Node.js BFF]  ← external ingress (Consumption profile)
    │ Dapr service invocation (internal)
    ├──▶ [order-service — Java]      ── Dedicated D4 ──▶ Pub/Sub publish ──▶ [Service Bus: orders topic]
    ├──▶ [accounting-service — Java] ── Consumption  ←── Pub/Sub subscribe; State → Azure SQL
    └──▶ [makeline-service — Java]   ── Dedicated D4 ←── Pub/Sub subscribe; State → Azure Managed Redis

[Service Bus: orders topic]
    ├──▶ [accounting-service — Java]   (subscriber)
    ├──▶ [loyalty-service — Java]      (subscriber) → State → Cosmos DB
    ├──▶ [makeline-service — Java]     (subscriber) → State → Redis
    └──▶ [receipt-service — .NET 8]    (subscriber) → Output Binding → Blob Storage

[bootstrap — Python]  (runs once → creates Azure SQL schema → scales to zero)
```

## Services

| Service | Language | ACA Workload Profile | Ingress | Dapr Building Blocks | KEDA Scalers |
|---|---|---|---|---|---|
| `ui` | ReactJS + Node.js | Consumption | **External** | Service Invocation | HTTP |
| `order-service` | Java 21 / Spring Boot 3 | **Dedicated D4** | Internal | Pub/Sub (publisher) | HTTP |
| `accounting-service` | Java 21 / Spring Boot 3 | Consumption | Internal | Pub/Sub (sub) + SQL | Service Bus + HTTP |
| `loyalty-service` | Java 21 / Spring Boot 3 | Consumption | Internal | Pub/Sub (sub) + State (Cosmos) | Service Bus |
| `makeline-service` | Java 21 / Spring Boot 3 | **Dedicated D4** | Internal | Pub/Sub (sub) + State (Redis) | Service Bus + HTTP |
| `receipt-service` | .NET 8 / C# | Consumption | Internal | Pub/Sub (sub) + Binding (Blob) | Service Bus |
| `bootstrap` | Python 3.12 | Consumption | None | — | None (runs once) |

## Prerequisites

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Docker Desktop](https://www.docker.com/products/docker-desktop)
- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) (for local development)

## Quick Start (Deploy to Azure)

```bash
# 1. Login
azd auth login

# 2. Provision infrastructure and deploy all services
azd up

# 3. Open the dashboard
azd show
```

> The UI URL is printed after `azd up` completes.

## Local Development

See [docs/local-dev.md](docs/local-dev.md) for running all services locally with Docker Compose + Dapr standalone.

## Architecture Notes

See [docs/architecture.md](docs/architecture.md) for detailed design decisions and how they map to the MS Learn article.

## Azure Resources Provisioned

| Resource | Purpose |
|---|---|
| Azure Container Apps Environment | Hosts all 7 services with workload profiles |
| Azure Container Registry | Stores container images |
| Azure Service Bus (Standard) | Dapr Pub/Sub broker |
| Azure SQL Database | Accounting service store |
| Azure Cosmos DB (NoSQL, serverless) | Loyalty service state (via Dapr) |
| Azure Managed Redis | Makeline service state (via Dapr) |
| Azure Blob Storage | Receipt output binding (via Dapr) |
| Azure Key Vault | Secrets store |
| User-Assigned Managed Identity | Workload identity for all services |
| Application Insights | Telemetry (via OpenTelemetry) |
| Log Analytics Workspace | Backing store for App Insights + ACA |

## Security

- **No secrets in code or configuration files** — all sensitive values in Azure Key Vault
- **User-assigned Managed Identity** authenticates all services to Azure resources
- **RBAC** (not connection strings) for Service Bus, Cosmos DB, SQL, Redis, Storage
- Dapr components configured with `auth.secretStore` referencing Key Vault

## Contributing

This is a reference/demo project. PRs welcome for bug fixes and improvements.

## License

[MIT](LICENSE)
