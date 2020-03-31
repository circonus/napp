# Building

```
docker build -t circonus/broker .
```

# Running

```
docker run -d \
  --name circonus_broker
  --network host \
  -e CIRCONUS_AUTH_TOKEN=<token> \
  -e CLUSTER_NAME=<name> \
  circonus/broker
```

# Upgrading

```
docker stop circonus_broker
docker rename circonus_broker oldbroker
docker pull circonus/broker:latest
docker run -d \
  --name circonus_broker
  --network host \
  -e CIRCONUS_AUTH_TOKEN=<token> \
  -e CLUSTER_NAME=<name> \
  --volumes-from oldbroker \
  circonus/broker:latest
docker rm oldbroker
```

# Online inspection

```
docker exec -it circonus_broker console
```
