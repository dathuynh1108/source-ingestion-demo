FROM mcr.microsoft.com/mssql/server:2022-latest

USER root
WORKDIR /opt/generator

COPY docker/sqlserver-generator/entrypoint.sh /opt/generator/entrypoint.sh

RUN sed -i 's/\r$//' /opt/generator/entrypoint.sh \
    && chmod +x /opt/generator/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/opt/generator/entrypoint.sh"]
