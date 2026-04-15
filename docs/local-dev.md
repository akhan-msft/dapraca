# Local Development Guide

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | latest | https://docker.com |
| Dapr CLI | 1.13+ | `winget install Dapr.CLI` |
| Azure CLI | latest | `winget install Microsoft.AzureCLI` |
| Java 21 | JDK | `winget install EclipseAdoptium.Temurin.21.JDK` |
| .NET 8 | SDK | https://dot.net |
| Node 20 | LTS | https://nodejs.org |
| Python 3.12 | | https://python.org |

## Quick start (all services via Docker Compose)

```bash
# Initialize Dapr (first time only)
dapr init

# Start everything
docker compose up -d

# Check status
docker compose ps

# Tail logs
docker compose logs -f ui
docker compose logs -f order-service

# Open dashboard
open http://localhost:3000
```

Services:
| Service | Port |
|---|---|
| UI (dashboard) | http://localhost:3000 |
| order-service | http://localhost:8080 |
| accounting-service | http://localhost:8081 |
| loyalty-service | http://localhost:8082 |
| makeline-service | http://localhost:8083 |
| receipt-service | http://localhost:8084 |
| Redis | localhost:6379 |
| SQL Server | localhost:1433 |
| Azurite (Blob) | localhost:10000 |

## Running individual services with Dapr CLI (for development)

```bash
# order-service
cd src/order-service
mvn spring-boot:run &
dapr run --app-id order-service --app-port 8080 --components-path ../../local-dev/dapr-components

# receipt-service
cd src/receipt-service/src/ReceiptService
dotnet run &
dapr run --app-id receipt-service --app-port 8080 --components-path ../../../../local-dev/dapr-components

# bootstrap (run once to create SQL schema)
cd src/bootstrap
SQL_SERVER=localhost SQL_DATABASE=reddog python main.py
```

## Dapr Dashboard (inspect components, subscriptions, service invocation)

```bash
dapr dashboard
# Opens http://localhost:8080
```

## Sending a test order

```bash
curl -X POST http://localhost:3000/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "cust-001",
    "customerName": "Jane Smith",
    "items": [
      { "productId": "p-001", "productName": "Red Dog Burger", "quantity": 2, "unitPrice": 9.99 }
    ]
  }'
```

## Stopping

```bash
docker compose down
docker compose down -v   # Also remove volumes (reset data)
```
