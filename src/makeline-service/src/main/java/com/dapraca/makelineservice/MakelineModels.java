package com.dapraca.makelineservice;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

public class MakelineModels {

    /**
     * Order event received from the pub/sub topic.
     */
    public record OrderEvent(
            String orderId,
            String customerId,
            String customerName,
            BigDecimal orderTotal,
            String storeId,
            String status,
            /** Raw JSON string of order line items. */
            String items
    ) {}

    /**
     * A kitchen work order stored in the Dapr state store (Redis).
     * {@code completedAt} is null until the order is marked complete.
     */
    public record WorkOrder(
            String orderId,
            String customerId,
            String customerName,
            BigDecimal orderTotal,
            /** One of: queued | processing | completed */
            String status,
            Instant queuedAt,
            Instant completedAt
    ) {}

    /**
     * Summary of the current kitchen queue returned by GET /api/makeline/orders.
     */
    public record QueueSummary(
            int totalQueued,
            int totalProcessing,
            List<WorkOrder> orders
    ) {}
}
