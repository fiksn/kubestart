FROM debian:stretch

RUN DEBIAN_FRONTEND=noninteractive apt-get -y update && apt-get -y install curl jq sudo vim git
COPY *.sh /usr/local/bin/
RUN /bin/bash -c "source /usr/local/bin/start.sh && install_cfssl && install_kubectl"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]

# External is meant for some auxiliary shell scripts
VOLUME ["/root/.kube", "/external"]

