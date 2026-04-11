FROM grafana/grafana:11.5.0

USER root

ENV GF_PATHS_PLUGINS=/opt/grafana-plugins

RUN mkdir -p "${GF_PATHS_PLUGINS}" \
    && chown -R grafana:root "${GF_PATHS_PLUGINS}" \
    && grafana cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install grafana-clickhouse-datasource

USER grafana
