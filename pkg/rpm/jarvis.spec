Name: %(echo $PACKAGE)
Version: %(echo $VERSION)
Release: %(echo $RELEASE)
Summary: A web application framework written in Perl
Group: Application/Enterprise
License: LGPL v3
URL: http://gitorious.org/jarvis/jarvis
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)

%global jarvisRoot /usr/share/%{name}
%global _binaries_in_noarch_packages_terminate_build 0
%{?perl_default_filter}

# Lets do our own perl requires, because 50% of the packages we want are not available via yum.
%global __requires_exclude perl\\(

#BuildRequires:
Requires: httpd perl(CGI) perl(CGI::Session) perl(CGI::Cookie) perl(HTTP::Cookies) perl(MIME::Types) perl(DBI) perl(JSON) perl(XML::LibXML) perl(Digest::MD5) perl(Time::HiRes)

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

#
# All build steps are done by make.sh.
#

%build

#
# All build steps are done by make.sh.
#

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr/share/%{name}
cp -r %{_builddir}/* %{buildroot}/usr/share/%{name}
cp -r %{_builddir}/usr %{buildroot}

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{jarvisRoot}
%docdir /usr/share/jarvis/docs/
/usr/local/lib64/perl5/auto/Jarvis/

%changelog

%post

# Install the HTTPD configuration file if it doesn't exist.
if [ ! -f /etc/httpd/conf.d/%{name}.conf ]; then
    cp /usr/share/%{name}/etc/httpd/conf.d/%{name}.conf /etc/httpd/conf.d/%{name}.conf
    echo "Created /etc/httpd/conf.d/%{name}.conf"
fi

# Install the base Jarvis configuration.
if [ ! -d /etc/%{name} ]; then
    cp -r /usr/share/%{name}/etc/jarvis /etc/%{name}
    echo "Created /etc/%{name}"
fi

echo "Jarvis installed and configuration created in /etc/httpd/conf.d"
echo "Reload the Apache configuration now."
echo "   systemctl restart httpd"

%postun

echo "Jarvis uninstalled and configuration remains in /etc/httpd/conf.d"
