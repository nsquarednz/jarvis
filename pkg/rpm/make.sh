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
JARVIS_PACKAGE='jarvis'
CGI_SESSION_VERSION='CGI-Session-4.48'
CGI_SESSION_PATH="https://cpan.metacpan.org/authors/id/M/MA/MARKSTOS/$CGI_SESSION_VERSION.tar.gz"

# Find our base directory, so we can build the package directory correctly
DIR=`pwd`
BASEPATH=`dirname $DIR`
BASEDIR=`basename $BASEPATH`

# Deployement directories.
SRC_DIR=../..
DEPLOY_DIR=../../deploy
CGI_SESSION_DIR=../../cgi-session

# Determine the version of the source system the output packages where compiled on.
# This is used in our output filename as well as determining which spec file to use.
RHELVERSION=`rpm -E %{rhel}`

# We implement a specific version for RHEL6 everything else just uses the default spec file.
SPECFILE=""
if [[ $RHELVERSION == '6' ]]; then
    SPECFILE="jarvis_rhel_6.spec"

elif [[ $RHELVERSION == '8' ]]; then
    SPECFILE="jarvis_rhel_8.spec"

else
    SPECFILE="jarvis.spec"
fi

# Cleanup.
rm -rf $DEPLOY_DIR
mkdir $DEPLOY_DIR
mkdir -p rpms

# Firstly the base package.
echo "# Building base package directory to $DEPLOY_DIR/$JARVIS_PACKAGE"
cd "$DIR"
mkdir $DEPLOY_DIR/$JARVIS_PACKAGE

# Compile C modules.

# N2 ASN1 Utils
echo "# Compiling: Jarvis JSON Utils"
cd "$DIR/$SRC_DIR/xs/Jarvis-JSON-Utils"
perl Makefile.PL
make
make DESTDIR=$DIR/$DEPLOY_DIR/$JARVIS_PACKAGE/ install

# Remove the generated perllocal.pod file to avoid overwriting the destination file.
echo "# Removing generated perllocal.pod"
find $DIR/$DEPLOY_DIR/$JARVIS_PACKAGE -name perllocal.pod -type f -delete

echo "# Building package hierarchy to $DEPLOY_DIR/$JARVIS_PACKAGE"
cd "$DIR"

cp -r $SRC_DIR/cgi-bin $DEPLOY_DIR/$JARVIS_PACKAGE
cp -r $SRC_DIR/demo $DEPLOY_DIR/$JARVIS_PACKAGE
cp -r $SRC_DIR/htdocs $DEPLOY_DIR/$JARVIS_PACKAGE
cp -r $SRC_DIR/lib $DEPLOY_DIR/$JARVIS_PACKAGE
cp -r $SRC_DIR/etc $DEPLOY_DIR/$JARVIS_PACKAGE

mkdir $DEPLOY_DIR/$JARVIS_PACKAGE/docs
cp $SRC_DIR/docs/jarvis_guide.pdf $DEPLOY_DIR/$JARVIS_PACKAGE/docs

# Move configuration files from Apache to HTTPD.
mkdir $DEPLOY_DIR/$JARVIS_PACKAGE/etc/httpd
mv $DEPLOY_DIR/$JARVIS_PACKAGE/etc/apache $DEPLOY_DIR/$JARVIS_PACKAGE/etc/httpd/conf.d

# Move bundled binary scripts.
mkdir $DEPLOY_DIR/$JARVIS_PACKAGE/bin
cp $SRC_DIR/bin/clean-sessions.pl $DEPLOY_DIR/$JARVIS_PACKAGE/bin

# Check for RHEL 8 specific build tasks.
if [[ $RHELVERSION == '8' ]]; then
    # Fetch, build and inline the CGI Session Library.
    echo "# RHEL 8 Detected. Fetching and building perl-CGI-Session"

    # Cleanup.
    rm -rf $CGI_SESSION_DIR
    mkdir $CGI_SESSION_DIR

    # Move into our build directory.
    cd "$DIR/$CGI_SESSION_DIR"

    # Get the binaries.
    wget $CGI_SESSION_PATH

    # Unpack.
    tar -zxvf "$CGI_SESSION_VERSION.tar.gz"

    # Build.
    cd "$CGI_SESSION_VERSION"
    perl Makefile.PL
    make

    # Copy files into the required directories.
    cp -r lib/* $DEPLOY_DIR/$JARVIS_PACKAGE/lib

    # Move back to the dir the rest of the build expects us to be in.
    cd "$DIR"
fi

echo "# Building RPM Package with spec file: $SPECFILE"

# Build the RPM package.
VERSION=$VERSION \
RELEASE=$RELEASE \
PACKAGE=$JARVIS_PACKAGE \
    rpmbuild -v \
    --define "_builddir $DIR/$DEPLOY_DIR/$JARVIS_PACKAGE" \
    --define "_rpmdir %(pwd)/rpms" \
    --define "_srcrpmdir %(pwd)/rpms" \
    --define "_sourcedir %(pwd)/../" \
    -ba $SPECFILE
