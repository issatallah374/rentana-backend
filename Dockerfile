# Use Java 17
FROM eclipse-temurin:17-jdk-alpine

# Set working directory
WORKDIR /app

# Copy all files
COPY . .

# Give permission to gradlew (IMPORTANT)
RUN chmod +x gradlew

# Build the Spring Boot app
RUN ./gradlew build -x test

# Run the app (auto-detect jar)
CMD ["sh", "-c", "java -jar $(ls build/libs/*.jar | head -n 1)"]