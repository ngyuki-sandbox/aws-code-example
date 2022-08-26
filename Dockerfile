FROM php:alpine

RUN docker-php-ext-enable opcache

CMD ["php", "-S", "0.0.0.0:9876"]
