#!/bin/sh

set -eux

docker-php-ext-install pdo_mysql &

while ! nc mysql 3306 -z; do
  sleep 1
done

wait

php test.php
