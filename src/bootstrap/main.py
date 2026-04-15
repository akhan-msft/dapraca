"""
Bootstrap Service — Red Dog
Runs once at startup to create the Azure SQL schema for the accounting-service.
Uses Managed Identity (DefaultAzureCredential) — no SQL passwords.
Scales to zero after completion.
"""
import os
import struct
import logging
import time

import pyodbc
from azure.identity import DefaultAzureCredential
from azure.monitor.opentelemetry import configure_azure_monitor

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("bootstrap")

SQL_SCHEMA = """
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'orders')
BEGIN
    CREATE TABLE orders (
        order_id      NVARCHAR(100)  PRIMARY KEY,
        customer_id   NVARCHAR(100)  NOT NULL,
        customer_name NVARCHAR(200)  NOT NULL,
        loyalty_id    NVARCHAR(100),
        order_date    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
        order_total   DECIMAL(10,2)  NOT NULL,
        store_id      NVARCHAR(100)  NOT NULL DEFAULT 'RedDog',
        status        NVARCHAR(50)   NOT NULL DEFAULT 'pending'
    );
    PRINT 'Table orders created.';
END

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'order_metrics')
BEGIN
    CREATE TABLE order_metrics (
        store_id           NVARCHAR(100) PRIMARY KEY,
        total_orders       INT           NOT NULL DEFAULT 0,
        total_revenue      DECIMAL(14,2) NOT NULL DEFAULT 0,
        avg_order_value    DECIMAL(10,2) NOT NULL DEFAULT 0
    );
    PRINT 'Table order_metrics created.';
END
"""


def get_token_bytes(credential: DefaultAzureCredential) -> bytes:
    """Get an AAD access token for Azure SQL and convert to the format pyodbc expects."""
    token = credential.get_token("https://database.windows.net/.default")
    token_bytes = token.token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    return token_struct


def run_bootstrap():
    server = os.environ["SQL_SERVER"]
    database = os.environ["SQL_DATABASE"]

    log.info("Bootstrapping Azure SQL: server=%s database=%s", server, database)

    credential = DefaultAzureCredential()

    connection_string = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server=tcp:{server},1433;"
        f"Database={database};"
        f"Encrypt=yes;TrustServerCertificate=no;"
        f"Connection Timeout=30;"
    )

    retries = 5
    for attempt in range(1, retries + 1):
        try:
            token_bytes = get_token_bytes(credential)
            # SQL_COPT_SS_ACCESS_TOKEN = 1256
            conn = pyodbc.connect(connection_string, attrs_before={1256: token_bytes})
            conn.autocommit = True
            cursor = conn.cursor()
            log.info("Connected to Azure SQL. Applying schema...")
            cursor.execute(SQL_SCHEMA)
            log.info("Schema applied successfully.")
            cursor.close()
            conn.close()
            return
        except Exception as exc:
            log.warning("Attempt %d/%d failed: %s", attempt, retries, exc)
            if attempt < retries:
                time.sleep(10 * attempt)
            else:
                raise


def main():
    # Configure OpenTelemetry → App Insights (connection string from env/Key Vault)
    conn_str = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if conn_str:
        configure_azure_monitor(connection_string=conn_str)
    else:
        log.warning("APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled")

    run_bootstrap()
    log.info("Bootstrap complete. Service will scale to zero.")


if __name__ == "__main__":
    main()
