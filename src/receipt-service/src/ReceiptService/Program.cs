using Azure.Monitor.OpenTelemetry.AspNetCore;
using Dapr;
using Dapr.Client;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// ── OpenTelemetry → Azure Monitor (App Insights) ─────────────────────────────
var appInsightsConnStr = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
if (!string.IsNullOrEmpty(appInsightsConnStr))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor(o =>
        o.ConnectionString = appInsightsConnStr);
}

// ── Dapr ──────────────────────────────────────────────────────────────────────
builder.Services.AddControllers().AddDapr();
builder.Services.AddDaprClient();
builder.Services.AddHealthChecks();

var app = builder.Build();

app.UseCloudEvents();
app.MapSubscribeHandler();
app.MapControllers();
app.MapHealthChecks("/healthz");

app.Run();
