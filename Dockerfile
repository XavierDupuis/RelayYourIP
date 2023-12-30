FROM alpine:latest

RUN apk --no-cache add msmtp dcron gettext jq yq curl

WORKDIR /app

COPY check_and_update.sh ./
RUN chmod +x ./check_and_update.sh
COPY msmtprc.template ./
COPY startup.sh ./

CMD ["sh", "./startup.sh"]