Name: jarvis
Version: %(echo $VERSION)
Release: 1
Summary: A web application framework written in Perl
Group: Application/Enterprise
License: LGPL v3
URL: http://gitorious.org/jarvis/jarvis
Source0: jarvis.tar
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

%global Root /usr/share/jarvis

%global _binaries_in_noarch_packages_terminate_build 0
%{?perl_default_filter}

# Lets do our own perl requires, because 50% of the packages we want are not available via yum.
%global __requires_exclude perl\\(

#BuildRequires:
Requires: perl(Net::LDAP) perl(LWP::UserAgent) perl(IO::String) perl(HTTP::Cookies) perl(Digest::MD5) perl(DBD::SQLite) perl(CGI::Session) perl(CGI::Cookie) perl(CGI)  perl(XML::Parser) perl(Class::Inspector) perl(MIME::Types) perl(URI::Encode) perl(Text::CSV)

%description
Jarvis is "helper glue". It is designed to bridge the gap between your
web-apps and your back-end database. The three standard components in a 
solution using Jarvis are:
 1. Rich Internet Applications. Ajax (XML or JSON) request and response.
 2. JARVIS
 3. Database. Accessible via SQL.
Front-end RIAs are often written using technologies such as Adobe Flex,
or JavaScript using libraries, including Dojo or ExtJS. These are often 
simple CRUD (Create, Read, Update, Delete) applications which simple wish
to perform basic operations on a back end databsae.

This requires some server script to handle data requests over http and
perform the corresponding back-end database transactions in a manner 
which is secure, extensible, standards-based and reasonably efficient.
%prep

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
make -f pkg/rpm/Makefile install DESTDIR=%{buildroot}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{Root}
%docdir /usr/share/jarvis/docs/
%config /etc/httpd/conf.d/jarvis.conf
%config /etc/jarvis/

%changelog

%post
echo "Jarvis installed and configuration created in /etc/httpd/conf.d"
echo "Reload the Apache configuration now."
echo "   systemctl restart httpd"

%postun
echo "Jarvis uninstalled and configuration removd from /etc/httpd/conf.d"
echo "Reload the Apache configuration now."
echo "   systemctl restart httpd"
