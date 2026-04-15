# Architecture Deep Dive

## Relationship to MS Learn Article

This repo is a companion demo for:
> **[Deploy microservices with Azure Container Apps and Dapr](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/serverless/microservices-with-container-apps-dapr)**

### Deviations from the article

| Article | This Demo | Reason |
|---|---|---|
| Traefik as ingress | Native ACA Envoy ingress | Reduce dependencies; Envoy is built-in and handles TLS/routing natively |
| Virtual Customer service | Removed | Use the order-placement form in the UI instead |
| Virtual Worker service | Removed | Use the "Complete" button in the Makeline dashboard |
| .NET only | Java (4) + .NET (1) + Python (1) + ReactJS | Showcase Dapr's polyglot capabilities |
| No Managed Identity | User-Assigned Managed Identity | Security best practice; no secrets in code |
| No Key Vault | Azure Key Vault | All secrets managed centrally |
| No workload profiles | Dedicated D4 + Consumption | Segment latency-sensitive services |
| No OTEL | OpenTelemetry → App Insights | Standard observability across all languages |

---

## Ingress Design

Without Traefik, the `ui` service is the **single external entry point**:

```
Browser → HTTPS → ACA Envoy (external ingress) → ui:3000
                                                     │ (internal ACA DNS)
                                                     ├─ Dapr invoke → order-service:8080
                                                     ├─ Dapr invoke → accounting-service:8080
                                                     └─ Dapr invoke → makeline-service:8080
```

The Node.js BFF pattern means:
- React SPA is served from the same origin (no CORS issues)
- All backend calls go through the BFF via Dapr service invocation
- Zero backend services need external ingress (better security posture)

---

## ACA Workload Profiles

| Profile | Services | Rationale |
|---|---|---|
| **Dedicated D4** (2 vCPU, 8 GiB) | `order-service`, `makeline-service` | Latency-sensitive: user places orders + dashboard polls queue in real time. Dedicated compute avoids cold starts. |
| **Consumption** | `ui`, `accounting-service`, `loyalty-service`, `receipt-service`, `bootstrap` | Event-driven / async. Scale-to-zero acceptable. Cost-optimized. |

---

## Dapr Building Blocks

### Pub/Sub (Azure Service Bus)

```
order-service ─publish──► orders topic
                               │
               ┌───────────────┼───────────────┐
               ▼               ▼               ▼               ▼
    accounting-service  loyalty-service  makeline-service  receipt-service
```

All 4 subscribers use independent Service Bus subscriptions — each gets its own copy of every message. If a subscriber fails, it retries independently (KEDA scales it up).

### State Store — Cosmos DB (loyalty-service)

- Key: `customerId`
- Value: `LoyaltyAccount` JSON (points, totalSpend, tier)
- Why Cosmos DB: globally distributed, serverless billing, Dapr-native support

### State Store — Azure Managed Redis (makeline-service)

- Keys: `{orderId}` → `WorkOrder` JSON; `queue-index` → list of active order IDs
- Why Redis: ultra-low latency reads for the live dashboard queue

### Output Binding — Blob Storage (receipt-service)

- Blob name: `{storeId}/{year}/{month}/{day}/{receiptId}.json`
- No SDK code needed for storage auth — Dapr sidecar handles managed identity to Storage

---

## Security Architecture

```
[Container App]
      │ AZURE_CLIENT_ID env var
      ▼
[User-Assigned Managed Identity]
      │ RBAC
      ├─► Service Bus Data Owner  → send/receive/manage
      ├─► Cosmos DB Contributor   → read/write state
      ├─► Storage Blob Contributor → write receipts
      ├─► Key Vault Secrets User  → read secrets
      └─► ACR Pull               → pull container images

[Key Vault secrets]
      ├─ appinsights-connection-string  → APPLICATIONINSIGHTS_CONNECTION_STRING
      ├─ redis-host / redis-password    → Dapr Redis component
      ├─ sql-server-fqdn               → accounting + bootstrap
      └─ servicebus-namespace          → Dapr Service Bus component
```

---

## KEDA Scaling

| Service | Scale Trigger | Min | Max |
|---|---|---|---|
| `order-service` | HTTP concurrent requests (50) | 1 | 10 |
| `accounting-service` | Service Bus topic message count (10) + HTTP | 0 | 10 |
| `loyalty-service` | Service Bus topic message count (10) | 0 | 10 |
| `makeline-service` | Service Bus topic message count (10) + HTTP | 1 | 10 |
| `receipt-service` | Service Bus topic message count (10) | 0 | 10 |
| `ui` | HTTP concurrent requests (100) | 1 | 10 |
| `bootstrap` | None (runs once) | 0 | 1 |

When all subscribers have 0 messages pending and no HTTP traffic, `accounting`, `loyalty`, and `receipt` services scale to zero — you pay nothing.

---

## OpenTelemetry Integration

All 7 services export traces, metrics, and logs to **Application Insights** via OpenTelemetry:

| Language | Library |
|---|---|
| Java | `opentelemetry-javaagent` + `azure-monitor-opentelemetry-exporter` |
| .NET 8 | `Azure.Monitor.OpenTelemetry.AspNetCore` |
| Python | `azure-monitor-opentelemetry` |
| Node.js | `@azure/monitor-opentelemetry` |

The `APPLICATIONINSIGHTS_CONNECTION_STRING` env var is the only configuration needed — it's stored in Key Vault and injected by ACA at runtime.

Dapr sidecar traces (pub/sub, state, binding operations) are forwarded to App Insights via the `daprAIConnectionString` on the ACA environment — giving you a complete **Application Map** showing all service-to-service interactions.
