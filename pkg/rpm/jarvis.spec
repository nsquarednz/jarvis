Name: jarvis
Version: 3.0.6
Release: 1
Summary: A web application framework written in Perl
Group: Application/Enterprise
License: LGPL v3
URL: http://gitorious.org/jarvis/jarvis
Source0: jarvis.tar
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

%global Root /opt/jarvis

#BuildRequires:
Requires: perl(DBD::SQLite) 

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
%doc /opt/jarvis/docs/COPYING.LESSER 
%doc /opt/jarvis/docs/jarvis_guide.pdf
%docdir /opt/jarvis/docs/
%config /etc/httpd/conf.d/jarvis.conf

%changelog

%post
echo "Jarvis installed and configuration created in /etc/httpd/conf.d"
echo "Reload the Apache configuration now."
echo "   /etc/init.d/httpd reload"

%postun
echo "Jarvis uninstalled and configuration removd from /etc/httpd/conf.d"
echo "Reload the Apache configuration now."
echo "   /etc/init.d/httpd reload"
