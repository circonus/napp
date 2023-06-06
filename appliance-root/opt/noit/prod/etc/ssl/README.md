# SSL/TLS configuration

This directory contains files necessary for the functioning of the Circonus
Enterprise Broker. These are generated and/or retrieved during the
[provisioning process](https://docs.circonus.com/circonus/integrations/brokers/installation/#provision-the-broker)
and should not be altered or removed unless directed by Circonus Support.

* `ca.crt` : Circonus Certificate Authority public certificate. This is the
  start of the CA chain for certificates issued by Circonus.
* `appliance.key` : Private key for this broker.
* `appliance.csr` : Certificate Signing Request, created when the broker was
  provisioned, requesting a certificate from the Circonus CA.
* `appliance.crt` : Public certificate issued to this broker by the Circonus
  CA.
