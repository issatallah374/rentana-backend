# Use Java 21 (FIXED)
FROM eclipse-temurin:21-jdk-alpine

WORKDIR /app

COPY . .

# Fix permissions
RUN chmod +x gradlew

# Build app
RUN ./gradlew build -x test

# Run app (auto-detect jar)
CMD ["sh", "-c", "java -jar $(ls build/libs/*.jar | head -n 1)"]