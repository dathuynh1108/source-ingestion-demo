FROM mcr.microsoft.com/mssql/server:2022-latest

USER root
WORKDIR /opt/bootstrap

COPY docker/sqlserver-init/init_inventory.sql /opt/bootstrap/init_inventory.sql
COPY docker/sqlserver-init/entrypoint.sh /opt/bootstrap/entrypoint.sh

RUN sed -i 's/\r$//' /opt/bootstrap/entrypoint.sh /opt/bootstrap/init_inventory.sql \
    && chmod +x /opt/bootstrap/entrypoint.sh

ENTRYPOINT ["/bin/sh", "/opt/bootstrap/entrypoint.sh"]
