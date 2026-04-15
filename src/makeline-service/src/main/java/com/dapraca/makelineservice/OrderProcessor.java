package com.dapraca.makelineservice;

import com.dapraca.makelineservice.MakelineModels.WorkOrder;
import io.dapr.client.DaprClient;
import io.dapr.client.domain.State;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * Background task that simulates kitchen processing.
 * Runs every 10 seconds, picks one queued order, moves it through
 * processing → completed, removing it from the queue index once done.
 *
 * This replaces the "virtual worker" simulator from the reference app,
 * keeping processing logic inside the makeline service itself.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OrderProcessor {

    private static final String STATE_STORE = "statestore-redis";
    private static final String QUEUE_INDEX = "queue-index";

    private final DaprClient daprClient;

    @Scheduled(fixedDelay = 10_000)
    public void processNextOrder() {
        try {
            List<String> orderIds = readQueueIndex();
            if (orderIds.isEmpty()) return;

            // Find the first queued order
            for (String orderId : orderIds) {
                State<WorkOrder> state = daprClient.getState(STATE_STORE, orderId, WorkOrder.class).block();
                if (state == null || state.getValue() == null) continue;

                WorkOrder order = state.getValue();
                if (!"queued".equals(order.status())) continue;

                // Move to processing
                WorkOrder processing = new WorkOrder(
                        order.orderId(), order.customerId(), order.customerName(),
                        order.orderTotal(), "processing", order.queuedAt(), null);
                daprClient.saveState(STATE_STORE, orderId, processing).block();
                log.info("Processing order {}", orderId);

                // Simulate work — complete after a short delay (next scheduler tick)
                Thread.sleep(3_000);

                WorkOrder completed = new WorkOrder(
                        order.orderId(), order.customerId(), order.customerName(),
                        order.orderTotal(), "completed", order.queuedAt(), Instant.now());
                daprClient.saveState(STATE_STORE, orderId, completed).block();
                log.info("Completed order {}", orderId);

                // Remove from queue index
                removeFromQueueIndex(orderId);
                break; // process one order per tick
            }
        } catch (Exception e) {
            log.warn("Order processor tick failed: {}", e.getMessage());
        }
    }

    @SuppressWarnings("unchecked")
    private List<String> readQueueIndex() {
        State<List> state = daprClient.getState(STATE_STORE, QUEUE_INDEX, List.class).block();
        if (state == null || state.getValue() == null) return new ArrayList<>();
        return new ArrayList<>((List<String>) state.getValue());
    }

    private void removeFromQueueIndex(String orderId) {
        List<String> current = readQueueIndex();
        if (current.remove(orderId)) {
            daprClient.saveState(STATE_STORE, QUEUE_INDEX, current).block();
        }
    }
}
