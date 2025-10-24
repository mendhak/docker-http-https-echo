[![pulls](https://img.shields.io/docker/pulls/mendhak/http-https-echo.svg?style=for-the-badge&logo=docker)](https://hub.docker.com/r/mendhak/http-https-echo)
[![Docker Image Version (latest semver)](https://img.shields.io/docker/v/mendhak/http-https-echo?color=lightblue&label=latest&sort=semver&style=for-the-badge)](https://hub.docker.com/r/mendhak/http-https-echo)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/mendhak/docker-http-https-echo/build.yml?color=darkgreen&style=for-the-badge&branch=master)](https://github.com/mendhak/docker-http-https-echo/actions?query=workflow%3ABuild)


`mendhak/http-https-echo` is a Docker image that can echo various HTTP request properties back to client in the response, as well as in the Docker container logs.
It comes with various options that can manipulate the response output, see the table of contents for a full list.

![browser](./screenshots/screenshot.png)

The image is available on [Docker Hub](https://hub.docker.com/r/mendhak/http-https-echo): `mendhak/http-https-echo:38`
The image is available on [Github Container Registry](https://github.com/mendhak/docker-http-https-echo/pkgs/container/http-https-echo): `ghcr.io/mendhak/http-https-echo:38`

Please do not use the `:latest` tag as it will break without warning, use a specific version instead.

This image is executed as non root by default and is fully compliant with Kubernetes or Openshift deployment.


- [Basic Usage](#basic-usage)
- [Choose your ports](#choose-your-ports)
- [Use your own certificates](#use-your-own-certificates)
- [Decode JWT header](#decode-jwt-header)
- [Disable ExpressJS log lines](#disable-expressjs-log-lines)
- [Do not log specific path](#do-not-log-specific-path)
- [JSON payloads and JSON output](#json-payloads-and-json-output)
- [No newlines](#no-newlines)
- [Send an empty response](#send-an-empty-response)
- [Custom status code](#custom-status-code)
- [Set response Content-Type](#set-response-content-type)
- [Add a delay before response](#add-a-delay-before-response)
- [Only return body in the response](#only-return-body-in-the-response)
- [Include environment variables in the response](#include-environment-variables-in-the-response)
- [Configuring CORS policy](#setting-corscross-origin-resource-sharing-headers-in-the-response) 
- [Client certificate details (mTLS) in the response](#client-certificate-details-mtls-in-the-response)
- [Preserve the case of headers in response body](#preserve-the-case-of-headers-in-response-body)
- [Override the response body with a file](#override-the-response-body-with-a-file)
- [Prometheus Metrics](#prometheus-metrics)
- [Screenshots](#screenshots)
- [Building](#building)
- [Changelog](#changelog)


## Basic Usage

Run with Docker

    docker run -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:38

Or run with Docker Compose

    docker-compose up

Then, issue a request via your browser or curl, and watch the response, as well as container log output.

    curl -k -X PUT -H "Arbitrary:Header" -d aaa=bbb https://localhost:8443/hello-world


## Choose your ports

You can choose a different internal port instead of 8080 and 8443 with the `HTTP_PORT` and `HTTPS_PORT` environment variables.

In this example I'm setting http to listen on 8888, and https to listen on 9999.

     docker run -e HTTP_PORT=8888 -e HTTPS_PORT=9999 -p 8080:8888 -p 8443:9999 --rm -t mendhak/http-https-echo:38


With docker compose, this would be:

    my-http-listener:
        image: mendhak/http-https-echo:38
        environment:
            - HTTP_PORT=8888
            - HTTPS_PORT=9999
        ports:
            - "8080:8888"
            - "8443:9999"


## Use your own certificates

The certificates are at `/app/fullchain.pem` and `/app/privkey.pem`.

You can use volume mounting to substitute the certificate and private key with your own.

    my-http-listener:
        image: mendhak/http-https-echo:38
        ports:
            - "8080:8080"
            - "8443:8443"
        volumes:
            - /etc/ssl/certs/ssl-cert-snakeoil.pem:/app/fullchain.pem
            - /etc/ssl/private/ssl-cert-snakeoil.key:/app/privkey.pem

You can use the environment variables `HTTPS_CERT_FILE` and `HTTPS_KEY_FILE` to define the location of existing certificate and private key inside container.


## Decode JWT header

If you specify the header that contains the JWT, the echo output will contain the decoded JWT.  Use the `JWT_HEADER` environment variable for this.

    docker run -e JWT_HEADER=Authentication -p 8080:8080 -p 8443:8443 --rm -it mendhak/http-https-echo:38


Now make your request with `Authentication: eyJ...` header (it should also work with the `Authentication: Bearer eyJ...` schema too):

     curl -k -H "Authentication: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" http://localhost:8080/

And in the output you should see a `jwt` section.

## Disable ExpressJS log lines

In the log output set the environment variable `DISABLE_REQUEST_LOGS` to true, to disable the specific ExpressJS request log lines. The ones like `::ffff:172.17.0.1 - - [03/Jan/2022:21:31:51 +0000] "GET /xyz HTTP/1.1" 200 423 "-" "curl/7.68.0"`.  The JSON output will still appear.

    docker run --rm -e DISABLE_REQUEST_LOGS=true --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:38


## Do not log specific path

Set the environment variable `LOG_IGNORE_PATH` to a path or a regex you would like to exclude from verbose logging to stdout.
This can help reduce noise from healthchecks in orchestration/infrastructure like Swarm, Kubernetes, ALBs, etc.

    # Ignore a single path    
    docker run -e LOG_IGNORE_PATH=/ping -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:38
    # Ignore multiple paths
    docker run -e LOG_IGNORE_PATH="^\/ping|^\/health|^\/metrics" -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:38
    # Ignore all paths
    docker run -e LOG_IGNORE_PATH=".*" -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:38
    docker run -e LOG_IGNORE_PATH="^" -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:38



## JSON payloads and JSON output

If you submit a JSON payload in the body of the request, with Content-Type: application/json, then the response will contain the escaped JSON as well.

For example,

    curl -X POST -H "Content-Type: application/json" -d '{"a":"b"}' http://localhost:8080/

Will contain a `json` property in the response/output.

        ...
        "xhr": false,
        "connection": {},
        "json": {
            "a": "b"
        }
    }

## No newlines

You can disable new lines in the log output by setting the environment variable `LOG_WITHOUT_NEWLINE`. For example,

```bash
docker run -e LOG_WITHOUT_NEWLINE=true -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:38
```

## Send an empty response

You can disable the JSON output in the response by setting the environment variable `ECHO_BACK_TO_CLIENT`. For example,

```bash
docker run -e ECHO_BACK_TO_CLIENT=false -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:38
```

## Custom status code

Use `x-set-response-status-code` to set a custom status code.

You can send it as a header:

```bash
curl -v -H "x-set-response-status-code: 401" http://localhost:8080/
```

You can send it as a querystring parameter:

```bash
curl -v http://localhost:8080/some/path?x-set-response-status-code=401
```

That will cause the reponse status code to be:

```
 HTTP/1.1 401 Unauthorized
```

## Set response Content-Type

Use `x-set-response-content-type` to set the Content-Type of the response.

You can send it as a header:

```bash
curl -H "X-Set-Response-Content-Type: text/plain" -kv https://localhost:8443/
```

You can send it as a querystring parameter:

```bash
curl  -kv https://localhost:8443/path?x-set-response-content-type=text/plain
```

This will cause the response content type to be:

```
< Content-Type: text/plain; charset=utf-8
```


## Add a delay before response

Use `x-set-response-delay-ms` to set a custom delay in milliseconds.  This will allow you to simulate slow responses.

You can send it as a header:

```bash
curl -v -H "x-set-response-delay-ms: 6000" http://localhost:8080/
```

You can send it as a querystring parameter:

```bash
curl -v http://localhost:8080/some/path?x-set-response-delay-ms=6000
```

## Only return body in the response

Use the querystring parameter, `response_body_only=true` to get just the request body in the response, none of the associated metadata.

```bash
curl -s -k -X POST -d 'cauliflower' http://localhost:8080/a/b/c?response_body_only=true
```

The output will be 'cauliflower'.

## Include environment variables in the response

You can have environment variables (that are visible to the echo server's process) added to the response body.  Because this could contain sensitive information, it is not a default behavior.

Pass the `ECHO_INCLUDE_ENV_VARS=1` environment variable in.

```bash
docker run -d --rm -e ECHO_INCLUDE_ENV_VARS=1 --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:38
```

Then do a normal request via curl or browser, and you will see the `env` property in the response body.

## Setting CORS(Cross-Origin Resource Sharing) headers in the response

Enable CORS headers in response by setting the environment variable `CORS_ALLOW_ORIGIN` to the list of allowed origins.
CORS configuration can be further fine-tuned by using the following environment variables:

- **`CORS_ALLOW_METHODS`**: List of Http methods allowed.
- **`CORS_ALLOW_HEADERS`**: List of headers allowed.
- **`CORS_ALLOW_CREDENTIALS`**: Comma-separated list of origin URLs from which the policy allows credentials to be sent.

None of these CORS settings can be set without setting the `CORS_ALLOW_ORIGIN` first. By default, they will all be missing when only the `CORS_ALLOW_ORIGIN` is set and need to be explicitly specified alongside `CORS_ALLOW_ORIGIN`.


## Client certificate details (mTLS) in the response

To get client certificate details in the response body, start the container with `MTLS_ENABLE=1` environment variable.  When passing a client certificate, the details about that certificate can be echoed back in the response body. The client certificate will not be validated.

For example, invoke using curl, passing a certificate and key.

```bash
curl -k --cert cert.pem --key privkey.pem  https://localhost:8443/
```

The response body will contain details about the client certificate passed in.

If you browse to https://localhost:8443/ in Firefox, you won't get prompted to supply a client certificate unless you have [an imported certificate by the same issuer as the server](https://superuser.com/questions/1043415/firefox-doesnt-ask-me-for-a-certificate-when-visiting-a-site-that-needs-one). If you need browser prompting to work, you'll need to follow the 'use your own certificates' section.  Firefox needs the imported certificate to be in a PKCS12 format, so if you have a certificate and key already, you can combine them using

```bash
openssl pkcs12 -export -in cert.pem -inkey privkey.pem -out certpkcs12.pfx
```

## Preserve the case of headers in response body

By default, the headers in the response body are lowercased. To attempt to preserve the case of headers in the response body, set the environment variable `PRESERVE_HEADER_CASE` to true.

```bash
docker run -e PRESERVE_HEADER_CASE=true -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:38
```

## Override the response body with a file

To override the response body with a file, set the environment variable `OVERRIDE_RESPONSE_BODY_FILE_PATH` to a file path.  
The file path needs to be in the `/app` directory.  

```bash
docker run -d --rm -v ${PWD}/test.html:/app/test.html -p 8080:8080 -e OVERRIDE_RESPONSE_BODY_FILE_PATH=/test.html -t mendhak/http-https-echo:38
```

## Set a maximum header size

You can use the `MAX_HEADER_SIZE` environment variable to set a maximum header size in bytes. The default is 1MB. 

```bash
docker run -d --rm -e MAX_HEADER_SIZE=1000  -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:38
```


## Prometheus Metrics

To expose http performance metrics, set the `PROMETHEUS_ENABLED` environment variable to true, the metrics will be available at `/metrics`. This uses the [`express-prom-bundle`](https://github.com/jochen-schweizer/express-prom-bundle) middleware

You can configure these metrics using the following variables:

| Variable                | Description                                   | Default Value |
| ----------------------- | --------------------------------------------- | ------------- |
| PROMETHEUS_ENABLED      | Toggles on the prometheus middleware          | false         |
| PROMETHEUS_METRICS_PATH | The path at which the metrics will be visible | /metrics      |
| PROMETHEUS_WITH_PATH    | Partitions the metrics by the requested path  | false         |
| PROMETHEUS_WITH_METHOD  | Partitions the metrics by HTTP method         | true          |
| PROMETHEUS_WITH_STATUS  | Partitions the metrics by HTTP status         | true          |
| PROMETHEUS_METRIC_TYPE  | Sets the type of metric, histogram or summary | summary       |

> Please check the middleware [documentation](https://github.com/jochen-schweizer/express-prom-bundle#options) for more details.

## Screenshots

#### Curl output

![curl](./screenshots/screenshot2.png)

#### `docker logs` output

![dockerlogs](./screenshots/screenshot3.png)



## Building and developing locally

    docker build -t mendhak/http-https-echo .

Run some tests to make sure features are working as expected.

    ./tests.sh

To create a new image on Docker Hub, I need to create a tag and push it.

    git tag -s 16
    git push --tags


## Changelog

See the [changelog](CHANGELOG.md)
