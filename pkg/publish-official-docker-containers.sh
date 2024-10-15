#!/usr/bin/env bash
set -e

#
# This script shows how you can build and publish the docker containers to our
# docker registry with the official tags. Run this script from the root
# directory of the source code module.
#
export BUILD_DATE=`date --rfc-3339=seconds`

# Get build version data from our teamcity script.
if [[ -e ../n2teamcity-scripts/hg_get_build_number.sh ]]; then
  source ../n2teamcity-scripts/hg_get_build_number.sh
else
  if [[ -e ../../n2teamcity-scripts/hg_get_build_number.sh ]]; then
    source ../../n2teamcity-scripts/hg_get_build_number.sh
  else
    if [[ -e ../../../n2teamcity-scripts/hg_get_build_number.sh ]]; then
       source ../../../n2teamcity-scripts/hg_get_build_number.sh
    else
      echo "Cannot find n2teamcity-scripts/hg_get_build_number.sh"
      exit 1
    fi
  fi
fi

# The above source of the teamcity script will set BUILD_VERSION
export VCS_REF=`hg log -l 1 -r . -T '{node}\n'`
export MAJOR_VERSION=`echo $LAST_TAG_VERSION | sed 's/^\([^.]\+\)\..*$/\1/'`
export MINOR_VERSION=`echo $LAST_TAG_VERSION | sed 's/^\([^.]\+\.[^.]\+\).*$/\1/'`
export DOCKER_REPOSITORY=${DOCKER_REPOSITORY:-docker-registry.nsquared.co.nz}

echo "Building with docker relevant variables:"
echo "    BUILD_DATE        $BUILD_DATE"
echo "    BUILD_VERSION     $BUILD_VERSION"
echo "    VCS_REF           $VCS_REF"
echo "    MAJOR_VERSION     $MAJOR_VERSION"
echo "    MINOR_VERSION     $MINOR_VERSION"
echo "    DOCKER_REPOSITORY $DOCKER_REPOSITORY"

if [[ -z $BUILD_DATE ]]; then
  echo "No BUILD_DATE"
  exit 1
fi
if [[ -z $BUILD_VERSION ]]; then
  echo "No BUILD_VERSION"
  exit 1
fi
if [[ -z $VCS_REF ]]; then
  echo "No VCS_REF"
  exit 1
fi
if [[ -z $MAJOR_VERSION ]]; then
  echo "No MAJOR_VERSION"
  exit 1
fi
if [[ -z $MINOR_VERSION ]]; then
  echo "No MINOR_VERSION"
  exit 1
fi

#
# Now build the docker container
#

docker build -f docker/DockerfileJARVIS --build-arg BUILD_DATE="$BUILD_DATE" --build-arg VCS_REF=$VCS_REF --build-arg BUILD_VERSION=$BUILD_VERSION -t $DOCKER_REPOSITORY/jarvis:latest-bookworm -t $DOCKER_REPOSITORY/jarvis:$MAJOR_VERSION-bookworm -t $DOCKER_REPOSITORY/jarvis:$MINOR_VERSION-bookworm .
for x in $DOCKER_REPOSITORY/jarvis:latest-bookworm $DOCKER_REPOSITORY/jarvis:$MAJOR_VERSION-bookworm $DOCKER_REPOSITORY/jarvis:$MINOR_VERSION-bookworm; do
	echo "Pushing $x"
	docker push $x
done
