##### WARNING:
# 
# This dockerfile is configured to be run from the project root or by using docker-compose.
# 
# To Build it, execute:
#       "docker build -f ./docker/Dockerfile ."
#
################################


FROM nsquarednz/base-ubuntu:16.04
LABEL maintainer="N-Squared Software <support@nsquared.nz>"


################################
### Config:
###
# set version for s6 overlay
ARG S6_INIT_SCRIPTS_VERSION="v0.2"
ARG SERVICES="apache2 openssl"


### Install
RUN \
    echo "**** Update sources ****" \
       && apt-get update \
    && \
    echo "**** Install package management and build tools ****" \
        apt-get install -y --no-install-recommends \
            software-properties-common \
    && \
    echo "**** Install core dependencies ****" \
        && apt-get install -y \
            openssl \
    && \
    echo "**** Install Apache ****" \
        && apt-get install -y \
            apache2 \
            apache2-bin \
            apache2-data \
            apache2-dev \
            apache2-utils \
    && \
    echo "**** Configure Apache ****" \
        && a2enmod ssl \
        && a2enmod rewrite \
        && a2enmod cgi \
    && \
    echo "**** Install Jarvis dependencies ****" \
        && apt-get install -y \
            libcgi-session-perl \
            libmime-types-perl \
            libxml-smart-perl \
            libdbi-perl \
            libjson-perl \
    && \
    echo "**** Configure Jarvis ****" \
        && cd /etc/apache2/conf-enabled \
        && ln -s ../conf-available/jarvis.conf jarvis.conf \
    && \
    echo "**** Install init process ****" \
        && curl -L "https://github.com/nsquarednz/s6-init/archive/${S6_INIT_SCRIPTS_VERSION}.tar.gz" -o /tmp/s6-init.tar.gz \
        && tar xfz /tmp/s6-init.tar.gz -C /tmp \
        && cd /tmp/s6-init-* \
        && ./install \
    && \
    echo "**** Cleanup setup files ****" \
        && rm -rf /tmp/* \
        && rm -rf /var/lib/apt/lists/* \
        && rm -rf /var/lock/* \
        && rm -rf /run/apache*


### Install Jarvis
COPY cgi-bin                    /usr/share/jarvis/cgi-bin
COPY htdocs                     /usr/share/jarvis/htdocs
COPY lib                        /usr/share/jarvis/lib
COPY etc/jarvis                 /etc/jarvis
COPY etc/apache                 /etc/jarvis/apache
COPY etc/apache/jarvis.conf     /etc/apache2/conf-available/jarvis.conf


### Add local files
COPY docker/root/ /


### Configure default environment variables
ENV \
    APACHE_SUFFIX=""


### Expose ports and volumes
EXPOSE \
    80 \
    443
