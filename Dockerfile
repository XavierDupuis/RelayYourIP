FROM alpine:latest

RUN apk --no-cache add dcron gettext jq yq curl bind-tools

WORKDIR /app

COPY /scripts ./scripts
RUN chmod +x /app/scripts/*.sh
ENTRYPOINT ["sh", "/app/scripts/startup.sh"]