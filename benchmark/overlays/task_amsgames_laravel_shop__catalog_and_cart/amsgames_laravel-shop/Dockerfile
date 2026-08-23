FROM php:7.4-cli-bullseye

WORKDIR /app

COPY . /app/

EXPOSE 9100

CMD ["php", "-S", "0.0.0.0:9100", "-t", "public"]

