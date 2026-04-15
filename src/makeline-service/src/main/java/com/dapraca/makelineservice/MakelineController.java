package com.dapraca.makelineservice;

import com.dapraca.makelineservice.MakelineModels.OrderEvent;
import com.dapraca.makelineservice.MakelineModels.QueueSummary;
import com.dapraca.makelineservice.MakelineModels.WorkOrder;
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

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

@RestController
@RequestMapping("/api/makeline")
@RequiredArgsConstructor
@Slf4j
public class MakelineController {

    private static final String PUBSUB_NAME  = "pubsub-servicebus";
    private static final String TOPIC_NAME   = "orders";
    private static final String STATE_STORE  = "statestore-redis";
    private static final String QUEUE_INDEX  = "queue-index";

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
        Span span = tracer.spanBuilder("makeline.onOrder").startSpan();
        try (var scope = span.makeCurrent()) {
            span.setAttribute("order.id", event.orderId());
            log.info("Queuing work order {}", event.orderId());

            WorkOrder workOrder = new WorkOrder(
                    event.orderId(),
                    event.customerId(),
                    event.customerName(),
                    event.orderTotal(),
                    "queued",
                    Instant.now(),
                    null
            );

            // Persist the individual work order
            daprClient.saveState(STATE_STORE, event.orderId(), workOrder).block();

            // Update the queue index
            addToQueueIndex(event.orderId());

            return ResponseEntity.ok().build();
        } catch (Exception ex) {
            span.recordException(ex);
            log.error("Failed to queue order {}: {}", event.orderId(), ex.getMessage(), ex);
            return ResponseEntity.ok().build();
        } finally {
            span.end();
        }
    }

    // ── Query endpoint ────────────────────────────────────────────────────────

    @GetMapping("/orders")
    public ResponseEntity<QueueSummary> getQueue() {
        List<String> orderIds = readQueueIndex();
        List<WorkOrder> orders = new ArrayList<>();

        for (String id : orderIds) {
            State<WorkOrder> state = daprClient
                    .getState(STATE_STORE, id, WorkOrder.class)
                    .block();
            if (state != null && state.getValue() != null) {
                orders.add(state.getValue());
            }
        }

        long queued     = orders.stream().filter(o -> "queued".equals(o.status())).count();
        long processing = orders.stream().filter(o -> "processing".equals(o.status())).count();

        return ResponseEntity.ok(new QueueSummary((int) queued, (int) processing, orders));
    }

    // ── Complete endpoint ─────────────────────────────────────────────────────

    @PutMapping("/orders/{orderId}/complete")
    public ResponseEntity<WorkOrder> completeOrder(@PathVariable String orderId) {
        State<WorkOrder> state = daprClient
                .getState(STATE_STORE, orderId, WorkOrder.class)
                .block();

        if (state == null || state.getValue() == null) {
            return ResponseEntity.notFound().build();
        }

        WorkOrder existing = state.getValue();
        WorkOrder completed = new WorkOrder(
                existing.orderId(),
                existing.customerId(),
                existing.customerName(),
                existing.orderTotal(),
                "completed",
                existing.queuedAt(),
                Instant.now()
        );

        daprClient.saveState(STATE_STORE, orderId, completed).block();
        log.info("Order {} marked as completed", orderId);
        return ResponseEntity.ok(completed);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private List<String> readQueueIndex() {
        State<List> state = daprClient
                .getState(STATE_STORE, QUEUE_INDEX, List.class)
                .block();
        if (state == null || state.getValue() == null) {
            return new ArrayList<>();
        }
        return (List<String>) state.getValue();
    }

    private void addToQueueIndex(String orderId) {
        List<String> current = readQueueIndex();
        if (!current.contains(orderId)) {
            current = new ArrayList<>(current);
            current.add(orderId);
            daprClient.saveState(STATE_STORE, QUEUE_INDEX, current).block();
        }
    }
}
