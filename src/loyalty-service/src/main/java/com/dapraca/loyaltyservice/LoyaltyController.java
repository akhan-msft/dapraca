package com.dapraca.loyaltyservice;

import com.dapraca.loyaltyservice.LoyaltyModels.LoyaltyAccount;
import com.dapraca.loyaltyservice.LoyaltyModels.OrderEvent;
import io.dapr.Topic;
import io.dapr.client.DaprClient;
import io.dapr.client.domain.CloudEvent;
import io.dapr.client.domain.State;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.math.RoundingMode;

@RestController
@RequestMapping("/api/loyalty")
@RequiredArgsConstructor
@Slf4j
public class LoyaltyController {

    private static final String PUBSUB_NAME   = "pubsub-servicebus";
    private static final String TOPIC_NAME    = "orders";
    private static final String STATE_STORE   = "statestore-cosmosdb";

    private final DaprClient daprClient;
    private final Tracer tracer;

    // ── Dapr pub/sub subscriber ───────────────────────────────────────────────

    @PostMapping(path = "/orders", consumes = MediaType.ALL_VALUE)
    @Topic(pubsubName = PUBSUB_NAME, name = TOPIC_NAME)
    public ResponseEntity<Void> onOrder(
            @RequestBody(required = false) CloudEvent<OrderEvent> cloudEvent) {

        if (cloudEvent == null || cloudEvent.getData() == null) {
            log.warn("Received empty cloud event — skipping");
            return ResponseEntity.ok().build();
        }

        OrderEvent event = cloudEvent.getData();
        Span span = tracer.spanBuilder("loyalty.onOrder").startSpan();
        try (var scope = span.makeCurrent()) {
            span.setAttribute("order.id", event.orderId());
            span.setAttribute("customer.id", event.customerId());
            log.info("Processing loyalty for customer {} (order {})", event.customerId(), event.orderId());

            updateLoyaltyAccount(event);
            return ResponseEntity.ok().build();
        } catch (Exception ex) {
            span.recordException(ex);
            log.error("Failed to update loyalty for customer {}: {}", event.customerId(), ex.getMessage(), ex);
            return ResponseEntity.ok().build();
        } finally {
            span.end();
        }
    }

    // ── Query endpoint ────────────────────────────────────────────────────────

    @GetMapping("/{customerId}")
    public ResponseEntity<LoyaltyAccount> getLoyaltyAccount(@PathVariable String customerId) {
        State<LoyaltyAccount> state = daprClient
                .getState(STATE_STORE, customerId, LoyaltyAccount.class)
                .block();

        if (state == null || state.getValue() == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(state.getValue());
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private void updateLoyaltyAccount(OrderEvent event) {
        String key = event.customerId();

        State<LoyaltyAccount> existing = daprClient
                .getState(STATE_STORE, key, LoyaltyAccount.class)
                .block();

        LoyaltyAccount current = (existing != null && existing.getValue() != null)
                ? existing.getValue()
                : new LoyaltyAccount(event.customerId(), event.loyaltyId(), 0, BigDecimal.ZERO, "BRONZE");

        // 1 point per dollar of order total, rounded to nearest integer
        int earnedPoints = event.orderTotal() != null
                ? event.orderTotal().setScale(0, RoundingMode.HALF_UP).intValue()
                : 0;

        int newPoints = current.points() + earnedPoints;
        BigDecimal newSpend = current.totalSpend().add(
                event.orderTotal() != null ? event.orderTotal() : BigDecimal.ZERO);
        String newTier = LoyaltyAccount.tierFor(newPoints);

        LoyaltyAccount updated = new LoyaltyAccount(
                current.customerId(),
                current.loyaltyId() != null ? current.loyaltyId() : event.loyaltyId(),
                newPoints,
                newSpend,
                newTier
        );

        daprClient.saveState(STATE_STORE, key, updated).block();
        log.info("Customer {} now has {} points (tier: {})", key, newPoints, newTier);
    }
}
