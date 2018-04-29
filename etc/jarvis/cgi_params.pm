# 
# Some Perl CGI features (see http://perldoc.perl.org/CGI.html, section
# "Avoiding Denial of Service Attacks") must be enabled prior to the
# CGI object being created.
#
# To enable these for Jarvis, edit this file and uncomment those
# options you wish to enable.
#

#
# Disable all file uploads. No POST requests may upload files with this
# flag set.
# 
#$CGI::DISABLE_UPLOADS = 1;

#
# Limit the maxiumum HTTP POST size. E.g. to 10 megabytes.
#
#$CGI::POST_MAX = 1024*1024*10;

1;
