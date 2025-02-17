#  _  ___                 _ ____  
# | |/ (_)_ __ ___   __ _(_)___ \ 
# | ' /| | '_ ` _ \ / _` | | __) |
# | . \| | | | | | | (_| | |/ __/ 
# |_|\_\_|_| |_| |_|\__,_|_|_____|
#                                 

# Source base [fpm-alpine/apache-debian]
ARG BASE="fpm-alpine"
ARG VER="prod"


###########################
# Shared tools
###########################

# full kimai source
FROM alpine:3.10 AS git-dev
ARG KIMAI="1.6"
RUN apk add --no-cache git && \
    git clone --depth 1 --branch ${KIMAI} https://github.com/kevinpapst/kimai2.git /opt/kimai

# production kimai source
FROM git-dev AS git-prod
WORKDIR /opt/kimai
RUN rm -r tests

# composer with prestissimo (faster deps install)
FROM composer:1.9 AS composer
RUN mkdir /opt/kimai && \
    composer require --working-dir=/opt/kimai hirak/prestissimo



###########################
# PHP extensions
###########################

#fpm alpine php extension base
FROM php:7.3.10-fpm-alpine3.10 AS fpm-alpine-php-ext-base
RUN apk add --no-cache \
    # gd
    libpng-dev \
    freetype-dev \
    # icu
    icu-dev \
    # zip
    libzip-dev \
    # build-tools
    m4 \
    perl \
    autoconf \
    dpkg \
    dpkg-dev \
    libmagic \
    file \
    make \
    re2c \
    libgomp \
    libatomic \
    mpfr3 \
    mpc1 \
    gcc \
    musl-dev \
    libc-dev \
    g++


# apache debian php extension base
FROM php:7.3.10-apache-buster AS apache-debian-php-ext-base
RUN apt-get update
RUN apt-get install -y \
        libicu-dev \
        libpng-dev \
        libzip-dev \
        libfreetype6-dev


# php extension gd
FROM ${BASE}-php-ext-base AS php-ext-gd
RUN docker-php-ext-configure gd \
        --with-freetype-dir && \
    docker-php-ext-install -j$(nproc) gd

# php extension intl
FROM ${BASE}-php-ext-base AS php-ext-intl
RUN docker-php-ext-install -j$(nproc) intl

# php extension pdo_mysql
FROM ${BASE}-php-ext-base AS php-ext-pdo_mysql
RUN docker-php-ext-install -j$(nproc) pdo_mysql

# php extension zip
FROM ${BASE}-php-ext-base AS php-ext-zip
RUN docker-php-ext-install -j$(nproc) zip




###########################
# fpm-alpine base build
###########################

# fpm-alpine base build
FROM php:7.3.10-fpm-alpine3.10 AS fpm-alpine-base
RUN apk add --no-cache \
        bash \
        haveged \
        icu \
        libpng \
        libzip \
        freetype && \
    touch /use_fpm

EXPOSE 9000



###########################
# apache-debian base build
###########################

FROM php:7.3.10-apache-buster AS apache-debian-base
COPY 000-default.conf /etc/apache2/sites-available/000-default.conf
RUN apt-get update && \
    apt-get install -y \
        bash \
        haveged \
        libicu63 \
        libpng16-16 \
        libzip4 \
        libfreetype6 && \
    echo "Listen 8001" > /etc/apache2/ports.conf && \
    a2enmod rewrite && \
    touch /use_apache

EXPOSE 8001



###########################
# global base build
###########################

FROM ${BASE}-base AS base
LABEL maintainer="tobias@neontribe.co.uk"
LABEL maintainer="bastian@schroll-software.de"

ARG KIMAI="1.6"
ENV KIMAI=${KIMAI}

ARG TZ=Europe/Berlin
ENV TZ=${TZ}
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone && \
    # make composer home dir
    mkdir /composer  && \
    chown -R www-data:www-data /composer

# drop root permissions
USER www-data

# copy startup script
COPY startup.sh /startup.sh

# copy composer
COPY --from=composer /usr/bin/composer /usr/bin/composer
COPY --from=composer --chown=www-data:www-data /opt/kimai/vendor /opt/kimai/vendor

# copy php extensions

# PHP extension pdo_mysql
COPY --from=php-ext-pdo_mysql /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini /usr/local/etc/php/conf.d/docker-php-ext-pdo_mysql.ini
COPY --from=php-ext-pdo_mysql /usr/local/lib/php/extensions/no-debug-non-zts-20180731/pdo_mysql.so /usr/local/lib/php/extensions/no-debug-non-zts-20180731/pdo_mysql.so
# PHP extension zip
COPY --from=php-ext-zip /usr/local/etc/php/conf.d/docker-php-ext-zip.ini /usr/local/etc/php/conf.d/docker-php-ext-zip.ini
COPY --from=php-ext-zip /usr/local/lib/php/extensions/no-debug-non-zts-20180731/zip.so /usr/local/lib/php/extensions/no-debug-non-zts-20180731/zip.so
# PHP extension gd
COPY --from=php-ext-gd /usr/local/etc/php/conf.d/docker-php-ext-gd.ini /usr/local/etc/php/conf.d/docker-php-ext-gd.ini
COPY --from=php-ext-gd /usr/local/lib/php/extensions/no-debug-non-zts-20180731/gd.so /usr/local/lib/php/extensions/no-debug-non-zts-20180731/gd.so
# PHP extension intl
COPY --from=php-ext-intl /usr/local/etc/php/conf.d/docker-php-ext-intl.ini /usr/local/etc/php/conf.d/docker-php-ext-intl.ini
COPY --from=php-ext-intl /usr/local/lib/php/extensions/no-debug-non-zts-20180731/intl.so /usr/local/lib/php/extensions/no-debug-non-zts-20180731/intl.so

ENV DATABASE_URL=sqlite:///%kernel.project_dir%/var/data/kimai.sqlite
ENV APP_SECRET=change_this_to_something_unique
ENV TRUSTED_PROXIES=false
ENV TRUSTED_HOSTS=false
ENV MAILER_FROM=kimai@example.com
ENV MAILER_URL=null://localhost
ENV ADMINPASS=
ENV ADMINMAIL=

VOLUME [ "/opt/kimai/var" ]

ENTRYPOINT /startup.sh



###########################
# final builds
###########################

# developement build
FROM base AS dev
# copy kimai develop source
COPY --from=git-dev --chown=www-data:www-data /opt/kimai /opt/kimai
# For some reason building with builf kit breaks here unless we do it as root: "copy(./.env): failed to open stream: Permission denied"
USER root
# do the composer deps installation
RUN export COMPOSER_HOME=/composer && \
    composer install --working-dir=/opt/kimai --optimize-autoloader && \
    composer clearcache && \
    chown -R www-data:www-data /opt/kimai
USER www-data

# production build
FROM base AS prod
# copy kimai production source
COPY --from=git-prod --chown=www-data:www-data /opt/kimai /opt/kimai
# For some reason building with builf kit breaks here unless we do it as root: "copy(./.env): failed to open stream: Permission denied"
USER root
# do the composer deps installation
RUN export COMPOSER_HOME=/composer && \
    composer install --working-dir=/opt/kimai --no-dev --optimize-autoloader && \
    composer clearcache && \
    chown -R www-data:www-data /opt/kimai
USER www-data

FROM ${VER}
ENV APP_ENV=${VER}
