using Dapr;
using Dapr.Client;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ReceiptService;

/// <summary>Order event received from Service Bus via Dapr pub/sub.</summary>
public record OrderEvent(
    string OrderId,
    string CustomerId,
    string CustomerName,
    string? LoyaltyId,
    DateTimeOffset OrderDate,
    decimal OrderTotal,
    string StoreId,
    string Status,
    List<OrderItem>? Items
);

public record OrderItem(
    string ProductId,
    string ProductName,
    int Quantity,
    decimal UnitPrice
);

/// <summary>Stored receipt document.</summary>
public record Receipt(
    string ReceiptId,
    string OrderId,
    string CustomerId,
    string CustomerName,
    DateTimeOffset OrderDate,
    DateTimeOffset GeneratedAt,
    decimal OrderTotal,
    string StoreId,
    List<OrderItem>? Items
);

[ApiController]
[Route("api/receipts")]
public class ReceiptController : ControllerBase
{
    private readonly DaprClient _daprClient;
    private readonly ILogger<ReceiptController> _logger;
    private const string BindingName = "binding-blobstorage";

    public ReceiptController(DaprClient daprClient, ILogger<ReceiptController> logger)
    {
        _daprClient = daprClient;
        _logger = logger;
    }

    /// <summary>
    /// Dapr pub/sub subscription handler.
    /// Receives order events from Service Bus and stores a receipt JSON in Blob Storage
    /// via Dapr output binding — no Azure SDK credentials needed here (Dapr handles auth).
    /// </summary>
    [Topic("pubsub-servicebus", "orders")]
    [HttpPost("orders")]
    public async Task<IActionResult> HandleOrder([FromBody] OrderEvent order, CancellationToken ct)
    {
        if (order is null)
            return BadRequest();

        var receiptId = Guid.NewGuid().ToString();
        var receipt = new Receipt(
            ReceiptId: receiptId,
            OrderId: order.OrderId,
            CustomerId: order.CustomerId,
            CustomerName: order.CustomerName,
            OrderDate: order.OrderDate,
            GeneratedAt: DateTimeOffset.UtcNow,
            OrderTotal: order.OrderTotal,
            StoreId: order.StoreId,
            Items: order.Items
        );

        var receiptJson = JsonSerializer.Serialize(receipt, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        // Store receipt via Dapr output binding → Azure Blob Storage (managed identity)
        var metadata = new Dictionary<string, string>
        {
            ["blobName"] = $"{order.StoreId}/{order.OrderDate:yyyy/MM/dd}/{receiptId}.json",
            ["contentType"] = "application/json"
        };

        await _daprClient.InvokeBindingAsync(
            bindingName: BindingName,
            operation: "create",
            data: receiptJson,
            metadata: metadata,
            cancellationToken: ct);

        _logger.LogInformation("Receipt {ReceiptId} stored for order {OrderId}", receiptId, order.OrderId);
        return Ok();
    }
}
