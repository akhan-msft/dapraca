package com.dapraca.orderservice;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import io.dapr.client.DaprClient;
import io.dapr.client.DaprClientBuilder;
import io.dapr.serializer.DaprObjectSerializer;
import io.dapr.utils.TypeRef;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.IOException;

@Configuration
public class DaprConfig {

    @Bean
    public DaprClient daprClient() {
        ObjectMapper mapper = new ObjectMapper()
                .registerModule(new JavaTimeModule())
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

        DaprObjectSerializer serializer = new DaprObjectSerializer() {
            @Override
            public byte[] serialize(Object o) throws IOException {
                if (o == null) return new byte[0];
                return mapper.writeValueAsBytes(o);
            }
            @Override
            public <T> T deserialize(byte[] data, TypeRef<T> type) throws IOException {
                if (data == null || data.length == 0) return null;
                return mapper.readValue(data, mapper.constructType(type.getType()));
            }
            @Override
            public String getContentType() { return "application/json"; }
        };

        return new DaprClientBuilder()
                .withObjectSerializer(serializer)
                .withStateSerializer(serializer)
                .build();
    }
}
