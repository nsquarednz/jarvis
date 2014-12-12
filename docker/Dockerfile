FROM ubuntu:14.04

ADD ./DEBFILE DEBFILE

RUN apt-get update && \
    apt-get install -y \
        libcgi-session-perl \
        libtext-csv-perl \
        libmime-types-perl \
        libsoap-lite-perl \
        libxml-smart-perl \
        apache2 \
        libapache-dbi-perl \
        libjson-perl \
        libio-string-perl \
        libtemplate-perl \
        liburi-encode-perl \
        sqlite \
        libdbd-sqlite3-perl && \
    apt-get -f install && \

    dpkg --install DEBFILE && \
    cp /etc/jarvis/apache/jarvis-mod-perl.conf /etc/apache2/conf-available/jarvis-mod-perl.conf && \
    a2enconf jarvis-mod-perl

ENTRYPOINT apache2ctl -D FOREGROUND
