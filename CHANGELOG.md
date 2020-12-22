
## verison `16` - 2020-12-22

* Dockerfile optimisation, slightly smaller image size
* This changelog added to the repo

## version `15` - 2020-12-15

* The image now runs as a non-root user by default. 

## version `14` - 2020-11-26

* Optionally allow running as a non root user. 

```
docker run --user node -e HTTP_PORT=8080 -e HTTPS_PORT=8443 -p 8080:8080 -p 8443:8443 --rm mendhak/http-https-echo:issue-14-non-root
#or
docker run --user node --sysctl net.ipv4.ip_unprivileged_port_start=0 -p 8080:80 -p 8443:443 --rm mendhak/http-https-echo:issue-14-non-root
```

## version `latest` and before

Unmaintained, please don't use the `latest` tag any longer

* JWT header
* Choose your own ports
* Choose your own certs
* Ignore a specific path
* JSON payloads
* Single line log output

