# WHY multi-stage build:
# Stage 1 (builder) has Maven and JDK — everything needed to compile.
# Stage 2 (runtime) has only the JRE — nothing to compile, nothing to
# exploit. The final image is smaller and has a smaller attack surface.

# ── Stage 1: build ────────────────────────────────────────────────────
FROM eclipse-temurin:17-jdk-alpine AS builder
WORKDIR /app

# Copy pom.xml first and download dependencies before copying source.
# WHY: Docker caches layers. If only source files change (not pom.xml),
# Maven doesn't re-download dependencies — builds are much faster.
COPY pom.xml .
RUN mvn dependency:go-offline -B --no-transfer-progress 2>/dev/null || true

COPY src ./src
RUN mvn package -DskipTests --batch-mode --no-transfer-progress

# ── Stage 2: runtime ─────────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

# WHY a non-root user:
# By default, Docker containers run as root. If your app is
# compromised, root inside the container has far more power than it
# should. Running as a dedicated app user limits the damage.
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app

COPY --from=builder /app/target/myapp.jar app.jar
RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

# WHY JAVA_OPTS as env: lets Kubernetes set heap size via the manifest
# without rebuilding the image
ENV JAVA_OPTS="-Xms256m -Xmx512m"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
