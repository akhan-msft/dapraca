# Multi-stage build — layered jar for faster rebuilds
FROM eclipse-temurin:21-jdk-jammy AS builder
WORKDIR /app
COPY pom.xml .
COPY src ./src

# Download dependencies first (cached layer if pom.xml unchanged)
RUN apt-get update && apt-get install -y maven && mvn dependency:go-offline -q
RUN mvn package -DskipTests -q

# Extract Spring Boot layers for optimal image caching
RUN java -Djarmode=layertools -jar target/*.jar extract

# ── Runtime image ──────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy

RUN useradd -r -u 1000 appuser
WORKDIR /app

COPY --from=builder /app/dependencies/ ./
COPY --from=builder /app/spring-boot-loader/ ./
COPY --from=builder /app/snapshot-dependencies/ ./
COPY --from=builder /app/application/ ./

RUN chown -R appuser /app
USER appuser

EXPOSE 8080

ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
