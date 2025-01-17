# Builder for ess_backend webservice and scripts
FROM rust:alpine AS builder

# install openssl 1.1.1
RUN apk add --no-cache --update "openssl>1.1.1" && \
    apk add --no-cache --upgrade bash && \
    apk add --no-cache musl-dev

WORKDIR /ess_backend/scripts
COPY ./scripts/*.template ./
COPY ./scripts/openssl.cnf ./
COPY ./scripts/generate_certs.sh .

# build scripts
RUN ./generate_certs.sh admin
RUN ./generate_certs.sh pam

# Copy source last as they can change
WORKDIR /ess_backend
COPY Cargo.toml ./
COPY src/* ./src/

RUN cargo build --release

FROM alpine

ENV ESS_WS_PATH=/opt/ess_backend
ENV ESS_WS_CERTS_PATH=$ESS_WS_PATH/certs

WORKDIR $ESS_WS_CERTS_PATH
COPY --from=builder /ess_backend/scripts/admin/* admin/
COPY --from=builder /ess_backend/scripts/pam/* pam/

WORKDIR $ESS_WS_PATH
COPY --from=builder /ess_backend/target/release/ess_backend .

# ESS backend web service envars
ENV ESS_ADMIN_WS_PORT=8081
ENV ESS_PAM_WS_PORT=8080
EXPOSE $ESS_ADMIN_WS_PORT  $ESS_PAM_WS_PORT

ENV ESS_ADMIN_WS_ROOT_CA=$ESS_WS_CERTS_PATH/admin/admin-root-ca.crt
ENV ESS_ADMIN_WS_CERT=$ESS_WS_CERTS_PATH/admin/admin-server-crt.pem
ENV ESS_ADMIN_WS_KEY=$ESS_WS_CERTS_PATH/admin/admin-server-key.pem
ENV ESS_PAM_WS_ROOT_CA=$ESS_WS_CERTS_PATH/pam/pam-root-ca.crt
ENV ESS_PAM_WS_CERT=$ESS_WS_CERTS_PATH/pam/pam-server-crt.pem
ENV ESS_PAM_WS_KEY=$ESS_WS_CERTS_PATH/pam/pam-server-key.pem
ENV ESS_LOG_LEVEL="INFO"

# Postgres connection details envars
# user: ess_admin
# host: postgres.local:5432
# database: ess
ENV ESS_DB_CONN="postgres://ess_admin@postgres.local:5432/ess"

# use build-in health check command
HEALTHCHECK --interval=2m --timeout=30s --start-period=30s --retries=3 \
	CMD /opt/ess_backend/ess_backend health || exit 1

# The ess_backend handles the SIGUP, SIGINT and SIGTERM signals.
# Docker uses SIGTERM by default. However SIGINT is more common
# in dev usage so use this one.
STOPSIGNAL SIGINT

# Note we run the service as exxec form not shell form
# and the format is a json array
ENTRYPOINT ["/opt/ess_backend/ess_backend", "start" ]
