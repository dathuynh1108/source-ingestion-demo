FROM mcr.microsoft.com/mssql/server:2022-latest

USER root
WORKDIR /opt/bootstrap

COPY docker/sqlserver-init/init_inventory.sql /opt/bootstrap/init_inventory.sql
COPY docker/sqlserver-init/entrypoint.sh /opt/bootstrap/entrypoint.sh

RUN chmod +x /opt/bootstrap/entrypoint.sh

ENTRYPOINT ["/bin/bash", "/opt/bootstrap/entrypoint.sh"]
