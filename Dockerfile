# Use Java 21
FROM eclipse-temurin:21-jdk-alpine

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Give execute permission to gradlew
RUN chmod +x gradlew

# Build the application
RUN ./gradlew build -x test

# Run the Spring Boot app (only jar after disabling plain jar)
CMD ["java", "-jar", "build/libs/rent-api-0.0.1-SNAPSHOT.jar"]