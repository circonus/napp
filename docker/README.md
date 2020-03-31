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

# Online inspection

```
docker exec -it circonus_broker console
```
