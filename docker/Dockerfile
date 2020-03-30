FROM ubuntu:16.04
COPY circonus-apt.key /tmp/circonus-apt.key
RUN apt-key add /tmp/circonus-apt.key
RUN rm -f /tmp/circonus-apt.key
COPY circonus.list /etc/apt/sources.list.d/circonus.list
RUN apt-get update
RUN apt-get install -y --force-yes circonus-field-broker
RUN apt-get install -y --force-yes circonus-field-broker-crashreporter
RUN apt-get install -y --force-yes telnet
RUN echo "MANAGED_CORONER=1" >> /opt/noit/prod/etc/noit.env

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

