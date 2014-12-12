#!/bin/bash

if [ $# -ne 1 ] ; then
    echo "Error: Missing command line arguments."
    echo
    echo "This script will create a Docker image using the specified version of Jarvis."
    echo "After the Docker image is created, it is required to rename it using the command:"
    echo "  docker tag <image id> jarvis"
    echo "The image ID is given at the end of the Docker build process, or can be seen with:"
    echo "  docker images"
    echo
    echo "  Requirements:"
    echo "   - Docker (https://www.docker.com/)"
    echo
    echo "  Usage: ./$0 <file>"
    echo "    file      The Jarvis Debian package you wish to use."
    echo "              e.g. jarvis_6.1.1-1_all.deb"
    
    exit 1
fi

cp Dockerfile Dockerfile.orig

sed -i -e s/DEBFILE/$1/g Dockerfile

docker build $(dirname $(readlink -f "$0"))

mv Dockerfile.orig Dockerfile
