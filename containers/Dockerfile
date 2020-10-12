
FROM docker:19.03.6-dind

COPY scripts/*.sh /usr/local/bin/
COPY scripts/*.py /usr/local/bin/
COPY scripts/*.R /usr/local/bin/

RUN apk update && \
    apk -v --no-cache add \
        bash=5.0.11-r1 \
        python=2.7.18-r0 \
        py2-pip=18.1-r0 \
        groff=1.22.4-r0 \
        less=551-r0 \
        mailcap=2.1.48-r0 \
        && \
    pip install --upgrade awscli==1.18.147 python-magic==0.4.18 && \
    pip install boto3==1.15.15 && \
    apk -v --purge del py-pip && \
    rm /var/cache/apk/* && \
    chmod ugo+x /usr/local/bin/*.sh

   

