package com.dapraca.makelineservice;

import com.azure.monitor.opentelemetry.exporter.AzureMonitorExporterBuilder;
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@Slf4j
public class TelemetryConfig {

    @Value("${APPLICATIONINSIGHTS_CONNECTION_STRING:}")
    private String connectionString;

    @Bean
    public OpenTelemetry openTelemetry() {
        if (connectionString == null || connectionString.isBlank()) {
            log.warn("APPLICATIONINSIGHTS_CONNECTION_STRING not set — telemetry disabled");
            return OpenTelemetry.noop();
        }

        var spanExporter = new AzureMonitorExporterBuilder()
                .connectionString(connectionString)
                .buildTraceExporter();

        var tracerProvider = SdkTracerProvider.builder()
                .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
                .build();

        return OpenTelemetrySdk.builder()
                .setTracerProvider(tracerProvider)
                .buildAndRegisterGlobal();
    }

    @Bean
    public Tracer tracer(OpenTelemetry openTelemetry) {
        return openTelemetry.getTracer("makeline-service");
    }
}
