VERSION=3.2.5
tar zcvf jarvis-$VERSION.orig.tar.gz ../../../jarvis \
    --exclude=jarvis/pkg \
    --exclude=CVS \
    --exclude=CVS/* \
    --transform "s/^jarvis/jarvis-$VERSION/"

rm -rf jarvis-$VERSION
mkdir jarvis-$VERSION
cp -R template jarvis-$VERSION/debian