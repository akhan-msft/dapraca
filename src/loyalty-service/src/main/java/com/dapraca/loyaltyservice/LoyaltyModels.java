package com.dapraca.loyaltyservice;

import java.math.BigDecimal;
import java.time.Instant;

public class LoyaltyModels {

    /**
     * Order event received from the pub/sub topic.
     */
    public record OrderEvent(
            String orderId,
            String customerId,
            String customerName,
            String loyaltyId,
            Instant orderDate,
            BigDecimal orderTotal,
            String storeId
    ) {}

    /**
     * A customer's loyalty account stored in the Dapr state store.
     * Tier thresholds: BRONZE < 500 pts | SILVER < 2000 pts | GOLD >= 2000 pts.
     */
    public record LoyaltyAccount(
            String customerId,
            String loyaltyId,
            int points,
            BigDecimal totalSpend,
            String tier
    ) {
        /** Derive tier from accumulated points. */
        public static String tierFor(int points) {
            if (points < 500) return "BRONZE";
            if (points < 2000) return "SILVER";
            return "GOLD";
        }
    }
}
