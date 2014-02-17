BUILDING

In order to build jarvis for debian, you need:

apt-get install devscripts
apt-get install debhelper

Then simply:

bash make.sh <x.y.z>

Where <x.y.z> is the version number, e.g. 1.2.3.


INSTALLING

In order to install the jarvis dpkg, you will need at LEAST:

apt-get install apache2
apt-get install libcgi-session-perl
apt-get install libtext-csv-perl
apt-get install libmime-types-perl
apt-get install libsoap-lite-perl
apt-get install libxml-smart-perl

For optional features you should also really add:

apt-get install libjson-perl
apt-get install libio-string-perl
apt-get install libdbi-perl
apt-get install libdbd-sqlite3-perl
apt-get install libsoap-lite-perl
apt-get install libjson-pp-perl
apt-get install libnet-ldap-perl
apt-get install libcrypt-eksblowfish-perl 

For better performance, we recommend:

apt-get install libapache2-mod-perl2
apt-get install libapache-dbi-perl
apt-get install libapache2-request-perl

For a wider range of databases, you might consider:

apt-get install libdbd-sybase-perl
apt-get install libdbd-pg-perl
