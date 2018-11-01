
----------------------------------------------------------------------
# Introduction:

Following these instructions will allow you to create a Jarvis Docker image.
You can then easily run this image as a "container", which will automatically start up
a fully functional web server hosting Jarvis for you. This will also allow you
to easily build other Docker images that are built upon Jarvis.

    What is Docker? See here:
    
    https://www.docker.com/whatisdocker/
    
Docker is required for this, so please follow the instructions relevant to your system from this page:
    
    https://docs.docker.com/installation/#installation


----------------------------------------------------------------------
# Building the Docker image:

Before an updated container can be used, it will need to be built for production.
This can be carried out by running the following command from the root of the project:

  "docker build -t nsquarednz/jarvis:{tag} -t nsquarednz/jarvis:latest -f ./docker/Dockerfile ."

This command will create an image tagged as both {tag} and latest. Be sure to replace {tag} with the correct version tag.
    
----------------------------------------------------------------------
# Running the Docker image:
 
Follow these instructions to set up your Docker image:

  Option A) Run the Jarvis container manually:

      1)  From here you can run jarvis as a stand alone process by executing:
            "docker run --rm -p 5080:80 -p 5443:443 nsquarednz/jarvis:latest"
          This command is a minimal example. It will need to be complemented with
          additional arguments such as mounted volumes for app names.
          Use this if you know what you are doing.

  Option B) Run the Jarvis container with docker-compose (as a production configuration):

      1)  From the root of this project execute: 
            "docker-compose -f ./docker-compose.yml up"
          This will generate the jarvis container named "docker_jarvis_{n}".
          It will then also proceed to start the container as with Option A.


----------------------------------------------------------------------
# Using the Docker image:

This will run the Apache web server in a container, already configured.

If you built and ran the container with installation "Option B", it will have set
this to be running on http://localhost:5080/ and https://localhost:5443/

If you are running this using "docker run" you will need to specify these ports
using the "-p" flag. 
See here for more info: https://docs.docker.com/engine/reference/run/#expose-incoming-ports
Additionally, passing the " --rm" flag will remove the container once you stop running it.
It is nice to keep your container list clean.
       
----------------------------------------------------------------------
# Docker compose information:

The docker compose file provided will allow you a quick way to deploy Jarvis.
It provides the following basic container configuration:

### Ports

Jarvis will run with a http available on port 5080 and https on 443.
*Note: https uses a self signed certificate*

### Environnement variables

Jarvis requires Apache to run. Apache is configured to run as PUID 1000 and GUID 1000.
You can change this by setting the PUID and PGID in the docker compose file.
You can also set a custom apache $SUFFIX which is used to prefix log file names.

### Volumes

 - **jarvis-applications:**
    This stores the datasets and modules used with Jarvis. See the Jarvis 
    Docs for more information.
 - **jarvis-configs:**
    The location of your application's config files
 - **jarvis-data:**
    Shared data used by your application's modules
 - **jarvis-temp:**
    Any shared temporary files used by your application's modules. Eg. Cookies.

Any of these volumes can be replaced with a mount from the Docker host machine.
       
----------------------------------------------------------------------
# Docker image information


|                           |               |
| ---                       | ---           |
| Supported Architectures   | X86-64        |
| Image Base                | [nsquarednz/base-ubuntu](https://github.com/nsquarednz/docker-base-ubuntu) |
| Additional applications   | jarvis        |
|                           | openssl       |
|                           | apache2       |
|                           | libcgi-session-perl |
|                           | libmime-types-perl  |
|                           | libxml-smart-perl   |
|                           | libdbi-perl         |
|                           | libjson-perl        |
