# Use official Maven+JDK21 image — avoids apt Maven (3.6.3) Lombok annotation processor issues
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app

# Cache dependencies separately from source
COPY pom.xml .
RUN mvn dependency:go-offline -q

COPY src ./src
RUN mvn package -DskipTests -q

# Extract Spring Boot layers for optimal image caching
RUN java -Djarmode=layertools -jar target/*.jar extract

# -- Runtime image --
FROM eclipse-temurin:21-jre-jammy

RUN useradd -r -u 1000 appuser
WORKDIR /app

# Application Insights Java Agent — auto-instruments Spring Boot -> App Insights
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/3.5.4/applicationinsights-agent-3.5.4.jar /app/agent/applicationinsights-agent.jar

COPY --from=builder /app/dependencies/ ./
COPY --from=builder /app/spring-boot-loader/ ./
COPY --from=builder /app/snapshot-dependencies/ ./
COPY --from=builder /app/application/ ./

RUN chown -R appuser /app
USER appuser

EXPOSE 8080
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/agent/applicationinsights-agent.jar"
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]