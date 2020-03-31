FROM ubuntu:16.04
COPY console.sh /bin/console
RUN chmod 755 /bin/console
ADD https://keybase.io/circonuspkg/pgp_keys.asc?fingerprint=14ff6826503494d85e62d2f22dd15eba6d4fa648 /tmp/circonus-apt.key
RUN apt-key add /tmp/circonus-apt.key
RUN rm -f /tmp/circonus-apt.key
COPY circonus.list /etc/apt/sources.list.d/circonus.list
RUN apt-get update
RUN apt-get install -y circonus-field-broker
RUN apt-get install -y --allow-unauthenticated circonus-field-broker-crashreporter
RUN apt-get install -y telnet
RUN echo "MANAGED_CORONER=1" >> /opt/noit/prod/etc/noit.env
VOLUME ["/opt/noit/prod/etc", "/opt/noit/prod/log"]

# These are default ports, you alsmost certainly want to run this
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

