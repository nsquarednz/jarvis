#!/bin/bash
#
# Script to create debian packages. To be run in the directory with make.sh
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
TAR_ORIG=jarvisnew_$VERSION.orig.tar.gz

# Find our base directory, so we can build the package directory correctly
DIR=`pwd`
BASEPATH=`dirname $DIR`
BASEPATH=`dirname $BASEPATH`
BASEDIR=`basename $BASEPATH`

echo $BASEPATH

echo $BASEDIR

# Clean up.
rm -rf jarvisnew-*
rm -f jarvisnew_*.orig.tar.gz
rm -f jarvisnew_*_all.deb
rm -f jarvisnew_*.diff.gz
rm -f jarvisnew_*.dsc
rm -f jarvisnew_*.build
rm -f jarvisnew_*.changes

# BUILD THE SOURCE TARBALL.
tar zcf $TAR_ORIG "../../../$BASEDIR" \
    --exclude="$BASEDIR/pkg" \
    --exclude="$BASEDIR/BUILDROOT" \
    --exclude=CVS \
    --exclude=.hg \
    --exclude=rpms \
    --exclude=jarvis.tar \
    --transform "s/^$BASEDIR/jarvisnew-$VERSION/"

# COPY THE DEBIAN PACKAGE TEMPLATE.
#
# Template was originally created with:
#   cd jarvis-$VERSION
#   dh_make -e jarvis@nsquaredsoftware.com
#
# (But has been customized since then)
#
tar -xzf $TAR_ORIG
mkdir -p jarvisnew-$VERSION/debian
find template -maxdepth 1 -type f -exec cp {} jarvisnew-$VERSION/debian/ \;

# MODIFY TEMPLATE DEFAULTS
perl -pi -e "s/VERSION/$VERSION/" jarvisnew-$VERSION/debian/changelog
perl -pi -e "s/RELEASE/$RELEASE/" jarvisnew-$VERSION/debian/changelog
perl -pi -e "s/DATE/$DATE/" jarvisnew-$VERSION/debian/changelog
perl -pi -e "s/DATE/$DATE/" jarvisnew-$VERSION/debian/copyright

# PERFORM THE PACKAGE BUILD
#
# Note: RE: Warnings unknown substitution variable ${shlibs:Depends}
# See: http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=566837
# (Fixed in dpkg version 1.15.6)
#
cd jarvisnew-$VERSION
debuild -uc -us
