# 独立构建：用镜像自带的 Gradle 8.10.2，避免 wrapper 发行版下载地址在本地环境不可达。
FROM gradle:8.10.2-jdk17 AS build
WORKDIR /src
COPY deploy/local/iam-stub /src/iam-stub
COPY support-files/bkiam-rbac /src/support-files/bkiam-rbac
RUN gradle -p /src/iam-stub --no-daemon bootJar

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /src/iam-stub/build/libs/*.jar /app/iam-stub.jar
COPY --from=build /src/support-files/bkiam-rbac /app/support-files/bkiam-rbac
EXPOSE 8080
ENV STUB_SEED_PATH=/app/support-files/bkiam-rbac
ENTRYPOINT ["java", "-jar", "iam-stub.jar"]
