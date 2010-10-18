# CONFIGURATION.  CHANGE FOR EACH RELEASE.
VERSION=3.2.5
RELEASE=2
DATE=`date -R`

# BUILD THE SOURCE TARBALL.
rm -rf jarvis_$VERSION.orig.tar.gz
tar zcf jarvis_$VERSION.orig.tar.gz ../../../jarvis \
    --exclude=jarvis/pkg \
    --exclude=CVS \
    --exclude=CVS/* \
    --transform "s/^jarvis/jarvis-$VERSION/"

# COPY THE DEBIAN PACKAGE TEMPLATE.
rm -rf jarvis-$VERSION
mkdir -p jarvis-$VERSION/debian
find template -maxdepth 1 -type f -exec cp {} jarvis-$VERSION/debian/ \;

# MODIFY TEMPLATE DEFAULTS
perl -pi -e "s/VERSION/$VERSION/" jarvis-$VERSION/debian/changelog
perl -pi -e "s/RELEASE/$RELEASE/" jarvis-$VERSION/debian/changelog
perl -pi -e "s/DATE/$DATE/" jarvis-$VERSION/debian/changelog

# PERFORM THE PACKAGE BUILD
cd jarvis-$VERSION
debuild