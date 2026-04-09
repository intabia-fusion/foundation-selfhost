#!/bin/bash
#

source ./config/platform.conf
docker run -ti \
-e SERVER_SECRET=${SECRET} \
-e 

intabiafusion/tool:${PLATFORM_VERSION} bash
