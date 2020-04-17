FROM ubuntu:16.04
ARG release=latest
COPY console.sh /bin/console
COPY circonus.${release}.list /etc/apt/sources.list.d/circonus.list
ADD https://keybase.io/circonuspkg/pgp_keys.asc?fingerprint=14ff6826503494d85e62d2f22dd15eba6d4fa648 /tmp/circonus-apt.key
RUN chmod 755 /bin/console && \
    apt-key add /tmp/circonus-apt.key && \
    rm -f /tmp/circonus-apt.key && \
    apt-get update && \
    apt-get install -y circonus-field-broker && \
    apt-get install -y --allow-unauthenticated circonus-field-broker-crashreporter && \
    apt-get install -y telnet && \
    mkdir /opt/napp/package && \
    /opt/circonus/bin/curl -o /opt/napp/package/circonus-field-broker-core-stock.deb `awk '{print $3; exit(0);}' /etc/apt/sources.list.d/circonus.list`pool/main/c/circonus-field-broker-core/`dpkg -l circonus-field-broker-core | awk '/broker-core/{print $2"-"$3"xenial_"$4".deb"}'` && \
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
