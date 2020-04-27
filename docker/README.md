# Building

```
# for the latest version
docker build -t circonuslabs/broker:latest --build-arg release=latest .
# for the release version
docker build -t circonuslabs/broker:release --build-arg release=release .
```

# Running

```
docker volume create broker_config
docker volume create broker_log
docker run -d \
  --name circonus_broker
  --network host \
  -e CIRCONUS_AUTH_TOKEN=<token> \
  -e CLUSTER_NAME=<name> \
  -v broker_config:/opt/noit/prod/etc \
  -v broker_log:/opt/noit/prod/log \
  circonuslabs/broker
```

# Upgrading

```
docker stop circonus_broker
docker rm circonus_broker
docker pull circonuslabs/broker:latest
docker run -d \
  --name circonus_broker
  --network host \
  -e CIRCONUS_AUTH_TOKEN=<token> \
  -e CLUSTER_NAME=<name> \
  -v broker_config:/opt/noit/prod/etc \
  -v broker_log:/opt/noit/prod/log \
  circonuslabs/broker:latest
```

# Online inspection

```
docker exec -it circonus_broker console
```
