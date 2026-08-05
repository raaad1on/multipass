FROM haproxy:3.0-alpine

# Edge proxy binds :443 on host network; run as root for privileged ports.
USER root

COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod 755 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
