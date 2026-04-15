package com.dapraca.orderservice;

import jakarta.validation.constraints.*;
import lombok.Builder;
import lombok.Data;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Inbound order request payload. */
@Data
class OrderRequest {

    @NotBlank(message = "customerId is required")
    private String customerId;

    @NotBlank(message = "customerName is required")
    private String customerName;

    private String loyaltyId;

    @NotEmpty(message = "items must not be empty")
    private List<OrderItem> items;

    @Data
    public static class OrderItem {
        @NotBlank
        private String productId;
        @NotBlank
        private String productName;
        @Min(1)
        private int quantity;
        @DecimalMin("0.01")
        private BigDecimal unitPrice;
    }
}

/** Published order event — sent to Service Bus via Dapr pub/sub. */
@Data
@Builder
class OrderEvent {
    private String orderId;
    private String customerId;
    private String customerName;
    private String loyaltyId;
    private Instant orderDate;
    private BigDecimal orderTotal;
    private String storeId;
    private List<OrderRequest.OrderItem> items;
    private String status;
}
