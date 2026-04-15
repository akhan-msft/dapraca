package com.dapraca.accountingservice;

import com.dapraca.accountingservice.OrderModels.OrderEvent;
import com.dapraca.accountingservice.OrderModels.OrderMetrics;
import io.dapr.Topic;
import io.dapr.client.domain.CloudEvent;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

import java.sql.Timestamp;
import java.util.List;

@RestController
@RequestMapping("/api/accounting")
@RequiredArgsConstructor
@Slf4j
public class AccountingController {

    private static final String PUBSUB_NAME = "pubsub-servicebus";
    private static final String TOPIC_NAME  = "orders";

    private final JdbcTemplate jdbcTemplate;
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
        Span span = tracer.spanBuilder("accounting.onOrder").startSpan();
        try (var scope = span.makeCurrent()) {
            span.setAttribute("order.id", event.orderId());
            span.setAttribute("order.storeId", event.storeId());
            log.info("Processing order {} for store {}", event.orderId(), event.storeId());

            persistOrder(event);
            upsertMetrics(event);

            return ResponseEntity.ok().build();
        } catch (Exception ex) {
            span.recordException(ex);
            log.error("Failed to persist order {}: {}", event.orderId(), ex.getMessage(), ex);
            // Return 200 to prevent Dapr from re-delivering a poison message
            return ResponseEntity.ok().build();
        } finally {
            span.end();
        }
    }

    // ── Query endpoints ───────────────────────────────────────────────────────

    @GetMapping("/metrics")
    public ResponseEntity<List<OrderMetrics>> getAllMetrics() {
        List<OrderMetrics> metrics = jdbcTemplate.query(
                "SELECT store_id, total_orders, total_revenue, avg_order_value FROM order_metrics ORDER BY store_id",
                (rs, rowNum) -> new OrderMetrics(
                        rs.getString("store_id"),
                        rs.getInt("total_orders"),
                        rs.getBigDecimal("total_revenue"),
                        rs.getBigDecimal("avg_order_value")
                )
        );
        return ResponseEntity.ok(metrics);
    }

    @GetMapping("/metrics/{storeId}")
    public ResponseEntity<OrderMetrics> getMetricsByStore(@PathVariable String storeId) {
        List<OrderMetrics> results = jdbcTemplate.query(
                "SELECT store_id, total_orders, total_revenue, avg_order_value FROM order_metrics WHERE store_id = ?",
                (rs, rowNum) -> new OrderMetrics(
                        rs.getString("store_id"),
                        rs.getInt("total_orders"),
                        rs.getBigDecimal("total_revenue"),
                        rs.getBigDecimal("avg_order_value")
                ),
                storeId
        );
        if (results.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(results.get(0));
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private void persistOrder(OrderEvent e) {
        jdbcTemplate.update(
                """
                INSERT INTO orders
                    (order_id, customer_id, customer_name, loyalty_id,
                     order_date, order_total, store_id, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                e.orderId(),
                e.customerId(),
                e.customerName(),
                e.loyaltyId(),
                e.orderDate() != null ? Timestamp.from(e.orderDate()) : null,
                e.orderTotal(),
                e.storeId(),
                e.status()
        );
    }

    private void upsertMetrics(OrderEvent e) {
        // SQL Server MERGE to upsert the per-store metrics row
        jdbcTemplate.update(
                """
                MERGE order_metrics AS target
                USING (SELECT ? AS store_id, ? AS order_total) AS source
                    ON target.store_id = source.store_id
                WHEN MATCHED THEN
                    UPDATE SET
                        total_orders   = target.total_orders + 1,
                        total_revenue  = target.total_revenue + source.order_total,
                        avg_order_value = (target.total_revenue + source.order_total)
                                          / (target.total_orders + 1)
                WHEN NOT MATCHED THEN
                    INSERT (store_id, total_orders, total_revenue, avg_order_value)
                    VALUES (source.store_id, 1, source.order_total, source.order_total);
                """,
                e.storeId(),
                e.orderTotal()
        );
    }
}
