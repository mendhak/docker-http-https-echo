
## Version `34` - `2024-08-17`
* Set `PRESERVE_HEADER_CASE` to `1` to attempt to preserve the case of headers in the response.
* Set `OVERRIDE_RESPONSE_BODY_FILE_PATH` to a path, to override the response body with the contents of that file. 

## Version `33` - `2024-04-07`
* Implementing configurable CORS settings by [ash0ne](https://github.com/mendhak/docker-http-https-echo/pull/65). 

## Version `32` - `2024-03-28`
* Update Express to 4.19.2 to address CVE-2024-29041

## Version `31` - 2023-12-03
* Use `PROMETHEUS_ENABLED` which enables a Prometheus metrics endpoint at /metrics

## Version `30` - 2023-06-03
* Use `HTTPS_CERT_FILE` and `HTTPS_KEY_FILE` to specify path to a certificate. 

## Version `29` - 2023-03-16
* Publishing this image to Github Container Registry. Available at `docker pull ghcr.io/mendhak/http-https-echo:latest`

## Version `28` - 2022-12-02
* Certificate now includes Subject Alternative Names as well as Common Name

## Version `27` - 2022-11-24
* Added some `org.opencontainers.image` labels to the Docker image

## Version `26` - 2022-10-30

* Environment variable `MTLS_ENABLE=1` will show details of the client certificate passed in the response body
* Environment variable `ECHO_INCLUDE_ENV_VARS=1` will include the container (or script's) environment variables in the response body. 

## Version `25` - 2022-10-09

* You can pass `x-set-response-content-type` in header, or querystring parameter, to set the content type of the response. 
* Upgrade to Node 16. 

## Version `24` - 2022-05-24

* Querystring parameter, `response_body_only=true` returns just the request body in the response.

## Version `23` - 2022-01-05

* Environment variable `DISABLE_REQUEST_LOGS=true` will remove the ExpressJS request log lines 
* Updated to Node 16
* Removed the `-----------` separator

## Version `22` - 2021-11-21

* You can now also send the response delay and response code as querystring parameters. 

## Version `21` - 2021-10-20

* You can send an empty response to the client by setting the environment variable `ECHO_BACK_TO_CLIENT=false` 

## Version `20` - 2021-09-27

* The image is available for multiple architectures.  This is being done via [docker buildx](https://github.com/mendhak/docker-http-https-echo/blob/9f511eae7c928d7f9543842598f9565c19828300/.github/workflows/publish.yml#L32) on Github Actions.

## Version `19` - 2021-04-08

* You can run the container as a different user than the one defined in the image. 

## Version `18` - 2021-02-26

* You can pass a `x-set-response-delay-ms` to set a custom delay in milliseconds.

## Version `17` - 2021-01-15

* You can pass a `x-set-response-status-code` header to set the response status code

## Version `16` - 2020-12-22

* Dockerfile optimisation, slightly smaller image size
* This changelog added to the repo

## Version `15` - 2020-12-15

* The image now runs as a non-root user by default. 

## Version `14` - 2020-11-26

* Optionally allow running as a non root user. 

```
docker run --user node -e HTTP_PORT=8080 -e HTTPS_PORT=8443 -p 8080:8080 -p 8443:8443 --rm mendhak/http-https-echo:issue-14-non-root
#or
docker run --user node --sysctl net.ipv4.ip_unprivileged_port_start=0 -p 8080:80 -p 8443:443 --rm mendhak/http-https-echo:issue-14-non-root
```

## Version `latest` and others

_Note: The `latest` tag is no longer being built, I've removed it from the automated builds. Please don't use the `latest` tag any longer._

* JWT header
* Choose your own ports
* Choose your own certs
* Ignore a specific path
* JSON payloads
* Single line log output

