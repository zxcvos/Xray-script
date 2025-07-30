FROM ubuntu:jammy

RUN apt update && \
  apt install socat curl gpg -y && \
  curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
  apt remove curl gpg -y && \
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ jammy main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
  apt update &&\
  apt install cloudflare-warp -y && \
  apt-get autoremove --yes && \
  apt-get autoclean && \
  rm -rf /var/lib/{apt,dpkg,cache,log}/

COPY startup.sh /bin/startup.sh
RUN chmod a+x /bin/startup.sh
ENTRYPOINT [ "/bin/startup.sh" ]
