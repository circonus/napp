FROM ubuntu:22.04
ARG STYLE
RUN apt-get update && apt-get install -y gnupg
COPY console.sh /bin/console
COPY circonus.${STYLE}.list /etc/apt/sources.list.d/circonus.list
ADD https://keybase.io/circonuspkg/pgp_keys.asc?fingerprint=14ff6826503494d85e62d2f22dd15eba6d4fa648 /etc/apt/trusted.gpg.d/circonus.asc
ADD https://updates.circonus.net/backtrace/ubuntu/backtrace_package_signing.key /etc/apt/trusted.gpg.d/circonus-backtrace.asc
RUN chmod 755 /bin/console && \
    apt-get update && \
    apt-get install -y circonus-field-broker circonus-field-broker-crashreporter telnet && \
    mkdir /opt/napp/package && \
    /opt/circonus/bin/curl -s -o /opt/napp/package/circonus-field-broker-core-stock.deb `awk '{print $2; exit(0);}' /etc/apt/sources.list.d/circonus.list`pool/main/c/circonus-field-broker-core/`dpkg -l circonus-field-broker-core | awk '/broker-core/{print $2"-"$3"jammy_"$4".deb"}'` && \
    /usr/bin/dpkg -l circonus-field-broker-core | \
      awk '/broker-core/{print $2"-"$3}' > /opt/noit/prod/etc/docker-core-version && \
    rm -rf /var/lib/apt/lists/*
VOLUME ["/opt/noit/prod/etc", "/opt/noit/prod/log"]

# These are default ports, you almost certainly want to run this
# image in host mode b/c the broker can open arbitrary ports during
# runtime.

# Main broker services
EXPOSE 43191/tcp
EXPOSE 43191/udp
# opentsdb (default)
EXPOSE 4242/tcp
# collectd (default)
EXPOSE 25826/udp
# ganglia (default)
EXPOSE 8649/udp
# Statsd (defaults)
EXPOSE 8126/tcp
EXPOSE 8125/udp
EXPOSE 8125/tcp

CMD ["/opt/napp/bin/broker-start", "-D", "-D"]
