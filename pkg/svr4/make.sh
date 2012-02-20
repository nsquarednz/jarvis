#!/bin/bash
#
set -e
set -x

# Script to create debian packages. To be run in the directory with make.sh
VERSION=$1
RELEASE=$2

# Check validity of version numbers.
if [[ -z "$RELEASE" ]]; then RELEASE=1; fi
if [[ ! $VERSION =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || [[ ! '$RELEASE =~ ^[0-9]+$' ]]; then
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
DATE=`date "+%Y-%m-%d %H:%M:%S"`

# Update the pkginfo.
cat pkginfo.tpl \
  | sed -e "s/__VERSION/$VERSION/" \
  | sed -e "s/__RELEASE/$RELEASE/" \
  | sed -e "s/__DATE/$DATE/" \
  > pkginfo

# Prepare the output directory.
PKGNAME=jarvis-$VERSION-$RELEASE.svr4
rm -rf $PKGNAME
rm -rf $PKGNAME.tar
rm -rf $PKGNAME.tar.gz
mkdir ./$PKGNAME

# Build and gzip.
pkgmk -d /tmp -d ./$PKGNAME

tar cvf $PKGNAME.tar $PKGNAME
gzip $PKGNAME.tar
