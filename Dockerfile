FROM debian:buster-slim

ENV container docker
ENV LC_ALL C.UTF-8
ENV DEBIAN_FRONTEND noninteractive

# Set up the user to be the same as the user creating the container.  Not
# strictly necessary, but this way all the permissions of the generated files
# will match.

ARG USER
ARG UID

ENV USER $USER
ENV HOME /home/$USER
ENV CUSTOM_MANIFEST ""

RUN apt update \
    && apt install -y sudo

RUN useradd -m -s /bin/bash $USER -u $UID -d $HOME \
    && passwd -d $USER \
    && echo "$USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN mkdir /source && chown -R $USER /source
RUN mkdir /output && chown -R $USER /output
RUN mkdir /working && chown -R $USER /working
RUN mkdir /static && chown -R $USER /static

SHELL [ "/bin/bash", "-c" ]

USER $USER
WORKDIR /working

COPY --chown=$USER x86_64-linux-gnu/manifest.xml /static/x86_64-linux-gnu/manifest.xml
COPY --chown=$USER aarch64-linux-gnu/manifest.xml /static/aarch64-linux-gnu/manifest.xml
COPY --chown=$USER rebuild-internal.sh /static/rebuild-internal.sh

RUN TOOLS_DIR=/static/tools /static/rebuild-internal.sh install_packages

VOLUME /source
VOLUME /working
VOLUME /output

ENTRYPOINT ["/static/rebuild-internal.sh"]
