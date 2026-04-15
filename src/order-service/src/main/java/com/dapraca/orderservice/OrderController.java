package com.dapraca.orderservice;

import io.dapr.client.DaprClient;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api/orders")
@RequiredArgsConstructor
@Slf4j
public class OrderController {

    private final DaprClient daprClient;
    private final Tracer tracer;

    @Value("${dapr.pubsub.name}")
    private String pubsubName;

    @Value("${dapr.pubsub.topic}")
    private String topic;

    // In-memory store for demo — in production, use a persistent store
    private final Map<String, OrderEvent> orderStore = new ConcurrentHashMap<>();

    @PostMapping
    public ResponseEntity<Map<String, String>> placeOrder(@Valid @RequestBody OrderRequest request) {
        Span span = tracer.spanBuilder("placeOrder").startSpan();
        try (Scope ignored = span.makeCurrent()) {
            String orderId = UUID.randomUUID().toString();
            BigDecimal total = request.getItems().stream()
                .map(i -> i.getUnitPrice().multiply(BigDecimal.valueOf(i.getQuantity())))
                .reduce(BigDecimal.ZERO, BigDecimal::add);

            OrderEvent event = OrderEvent.builder()
                .orderId(orderId)
                .customerId(request.getCustomerId())
                .customerName(request.getCustomerName())
                .loyaltyId(request.getLoyaltyId())
                .orderDate(Instant.now())
                .orderTotal(total)
                .storeId("RedDog")
                .items(request.getItems())
                .status("pending")
                .build();

            orderStore.put(orderId, event);

            // Publish to Service Bus via Dapr pub/sub
            daprClient.publishEvent(pubsubName, topic, event).block();

            log.info("Order {} placed and published for customer {}", orderId, request.getCustomerId());
            span.setAttribute("order.id", orderId);
            span.setAttribute("order.total", total.doubleValue());

            return ResponseEntity.accepted().body(Map.of(
                "orderId", orderId,
                "status", "accepted"
            ));
        } finally {
            span.end();
        }
    }

    @GetMapping("/{orderId}")
    public ResponseEntity<OrderEvent> getOrder(@PathVariable String orderId) {
        OrderEvent order = orderStore.get(orderId);
        if (order == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(order);
    }

    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("OK");
    }
}
