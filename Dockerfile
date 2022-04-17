FROM gcr.io/kaniko-project/executor:v1.8.1

ENV HOME /root
ENV USER root
ENV SSL_CERT_DIR=/kaniko/ssl/certs
ENV DOCKER_CONFIG /kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG /kaniko/.config/gcloud/docker_credential_gcr_config.json

ADD https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 /kaniko/jq
#RUN [ "wget", "-O", "/kaniko/jq", "https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64" ]
RUN [ "/busybox/chmod", "a+x", "/kaniko/jq" ]
RUN [ "/kaniko/jq", "-h" ]

# add the wrapper which acts as a drone plugin
COPY plugin.sh /kaniko/plugin.sh
ENTRYPOINT [ "/kaniko/plugin.sh" ]
