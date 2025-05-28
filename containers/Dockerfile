
FROM docker:25.0.5-dind

RUN apk update && \
    apk -v --no-cache add \
        groff \
        less \
        mailcap \
        python3 py3-pip

RUN apk add --no-cache aws-cli
RUN apk add py3-boto3 bash

RUN  chmod ugo+x /usr/local/bin/*.sh

   
COPY scripts/*.sh /usr/local/bin/
COPY scripts/*.py /usr/local/bin/
COPY scripts/*.R /usr/local/bin/

