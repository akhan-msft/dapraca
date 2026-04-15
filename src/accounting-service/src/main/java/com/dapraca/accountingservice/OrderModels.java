package com.dapraca.accountingservice;

import java.math.BigDecimal;
import java.time.Instant;

public class OrderModels {

    /**
     * Represents an order event received from the pub/sub topic.
     */
    public record OrderEvent(
            String orderId,
            String customerId,
            String customerName,
            String loyaltyId,
            Instant orderDate,
            BigDecimal orderTotal,
            String storeId,
            String status
    ) {}

    /**
     * Aggregated order metrics per store, returned by the metrics endpoints.
     */
    public record OrderMetrics(
            String storeId,
            int totalOrders,
            BigDecimal totalRevenue,
            BigDecimal avgOrderValue
    ) {}

    /**
     * Summary row for the order history list.
     */
    public record OrderSummary(
            String orderId,
            String customerName,
            BigDecimal orderTotal,
            String storeId,
            Instant orderDate,
            String status
    ) {}
}
