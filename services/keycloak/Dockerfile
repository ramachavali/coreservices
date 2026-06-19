FROM quay.io/keycloak/keycloak:26.2.5

ENV KC_DB=postgres
ENV KC_HTTP_ENABLED=true
ENV KC_PROXY_HEADERS=xforwarded
ENV KC_HEALTH_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
