#!/bin/bash
#

source ./platform_v7.conf
docker run -ti \
-e SERVER_SECRET=${SECRET} \
-e 

intabiafusion/tool:${PLATFORM_VERSION} bash
