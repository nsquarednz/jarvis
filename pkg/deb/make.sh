#!/bin/bash
#
# Script to create debian packages.
VERSION=$1
RELEASE=$2

# Check validity of version numbers.
if [[ -z "$RELEASE" ]]; then RELEASE=1; fi
if [[ ! $VERSION =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || [[ ! $RELEASE =~ ^[0-9]+$ ]]; then
    echo " "
    echo "usage: make.sh <version> [release]"
    echo " "
    echo "  e.g. make.sh 3.2.1"
    echo "  Version must be X.Y with optional .Z"
    echo "  Release must be number, default = 1"
    echo " "
    exit 1
fi

# Other parameters.
DATE=`date -R`
TAR_ORIG=jarvis_$VERSION.orig.tar.gz

# Clean up.
rm -rf jarvis-*
rm -f jarvis_*.orig.tar.gz
rm -f jarvis_*_all.deb
rm -f jarvis_*.diff.gz
rm -f jarvis_*.dsc
rm -f jarvis_*.build
rm -f jarvis_*.changes

# BUILD THE SOURCE TARBALL.
tar zcf $TAR_ORIG ../../../jarvis \
    --exclude=jarvis/pkg \
    --exclude=CVS \
    --exclude=CVS/* \
    --transform "s/^jarvis/jarvis-$VERSION/"

# COPY THE DEBIAN PACKAGE TEMPLATE.
#
# Template was originally created with:
#   cd jarvis-$VERSION
#   dh_make -e jarvis@nsquaredsoftware.com
#
# (But has been customized since then)
#
tar -xzf $TAR_ORIG
mkdir -p jarvis-$VERSION/debian
find template -maxdepth 1 -type f -exec cp {} jarvis-$VERSION/debian/ \;

# MODIFY TEMPLATE DEFAULTS
perl -pi -e "s/VERSION/$VERSION/" jarvis-$VERSION/debian/changelog
perl -pi -e "s/RELEASE/$RELEASE/" jarvis-$VERSION/debian/changelog
perl -pi -e "s/DATE/$DATE/" jarvis-$VERSION/debian/changelog
perl -pi -e "s/DATE/$DATE/" jarvis-$VERSION/debian/copyright

# PERFORM THE PACKAGE BUILD
#
# Note: RE: Warnings unknown substitution variable ${shlibs:Depends}
# See: http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=566837
# (Fixed in dpkg version 1.15.6)
#
cd jarvis-$VERSION
debuild