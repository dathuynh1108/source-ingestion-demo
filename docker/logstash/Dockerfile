ARG LOGSTASH_VERSION=8.19.12
FROM docker.elastic.co/logstash/logstash:${LOGSTASH_VERSION}

USER root

ARG MSSQL_JDBC_VERSION=13.2.1.jre11

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN bin/logstash-plugin install logstash-integration-jdbc \
    && bin/logstash-plugin install logstash-integration-kafka

RUN mkdir -p /usr/share/logstash/vendor/jar/jdbc /usr/share/logstash/data/sql_last_value /usr/share/logstash/sql

RUN curl -fsSL \
      -o /usr/share/logstash/vendor/jar/jdbc/mssql-jdbc.jar \
      "https://repo1.maven.org/maven2/com/microsoft/sqlserver/mssql-jdbc/${MSSQL_JDBC_VERSION}/mssql-jdbc-${MSSQL_JDBC_VERSION}.jar"

COPY docker/logstash/config/logstash.yml /usr/share/logstash/config/logstash.yml
COPY docker/logstash/pipeline/logstash.conf /usr/share/logstash/pipeline/logstash.conf
COPY docker/logstash/sql/ /usr/share/logstash/sql/

USER logstash
