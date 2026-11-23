# Two stages: the build tools stay in the first one, the final image holds only Java and the application file.
FROM eclipse-temurin:25-jdk AS build
WORKDIR /workspace
COPY gradlew settings.gradle build.gradle ./
COPY gradle gradle
COPY config config
COPY src src
RUN chmod +x gradlew \
    && ./gradlew --no-daemon bootJar \
    && cp "$(ls build/libs/*.jar | grep -v plain)" application.jar

FROM eclipse-temurin:25-jre
# Not root: whoever breaks in through the application gets the rights of an ordinary user only.
RUN useradd --system --create-home ilp
USER ilp
WORKDIR /home/ilp
COPY --from=build /workspace/application.jar application.jar
# The memory of the container is small and fixed, so Java is told which share of it the heap may take.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "application.jar"]
