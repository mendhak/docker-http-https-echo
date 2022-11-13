[![pulls](https://img.shields.io/docker/pulls/mendhak/http-https-echo.svg?style=for-the-badge&logo=docker)](https://hub.docker.com/r/mendhak/http-https-echo)
[![Docker Image Version (latest semver)](https://img.shields.io/docker/v/mendhak/http-https-echo?color=lightblue&label=latest&sort=semver&style=for-the-badge)](https://hub.docker.com/r/mendhak/http-https-echo)
[![GitHub Workflow Status](https://img.shields.io/github/workflow/status/mendhak/docker-http-https-echo/Build?color=darkgreen&style=for-the-badge)](https://github.com/mendhak/docker-http-https-echo/actions?query=workflow%3ABuild)




[`mendhak/http-https-echo`](https://hub.docker.com/r/mendhak/http-https-echo) is a Docker image that can echo various HTTP request properties back to client, as well as in the Docker container logs.
You can use your own certificates, choose your ports, decode JWT headers and filter out certain paths.

![browser](https://raw.githubusercontent.com/mendhak/docker-http-https-echo/master/screenshots/screenshot.png)

This image is executed as non root by default and is fully compliant with Kubernetes or Openshift deployment.

Please do not use the `:latest` tag as it will break without warning, use a specific version instead.


- [Basic Usage](#basic-usage)
- [Choose your ports](#choose-your-ports)
- [Use your own certificates](#use-your-own-certificates)
- [Decode JWT header](#decode-jwt-header)
- [Disable ExpressJS log lines](#disable-expressjs-log-lines)
- [Do not log specific path](#do-not-log-specific-path)
- [JSON payloads and JSON output](#json-payloads-and-json-output)
- [Send an empty response](#send-an-empty-response)
- [Custom status code](#custom-status-code)
- [Set response Content-Type](#set-response-content-type)
- [Add a delay before response](#add-a-delay-before-response)
- [Only return body in the response](#only-return-body-in-the-response)
- [Include environment variables in the response](#include-environment-variables-in-the-response)
- [Client certificate details (mTLS) in the response](#client-certificate-details--mtls--in-the-response)
- [Output](#output)
- [Building](#building)
- [Changelog](#changelog)


## Basic Usage

Run with Docker

    docker run -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:25

Or run with Docker Compose

    docker-compose up

Then, issue a request via your browser or curl, and watch the response, as well as container log output.

    curl -k -X PUT -H "Arbitrary:Header" -d aaa=bbb https://localhost:8443/hello-world


## Choose your ports

You can choose a different internal port instead of 8080 and 8443 with the `HTTP_PORT` and `HTTPS_PORT` environment variables.

In this example I'm setting http to listen on 8888, and https to listen on 9999.

     docker run -e HTTP_PORT=8888 -e HTTPS_PORT=9999 -p 8080:8888 -p 8443:9999 --rm -t mendhak/http-https-echo:25


With docker compose, this would be:

    my-http-listener:
        image: mendhak/http-https-echo:25
        environment:
            - HTTP_PORT=8888
            - HTTPS_PORT=9999
        ports:
            - "8080:8888"
            - "8443:9999"


## Use your own certificates

Use volume mounting to substitute the certificate and private key with your own. This example uses the snakeoil cert.

    my-http-listener:
        image: mendhak/http-https-echo:25
        ports:
            - "8080:8080"
            - "8443:8443"
        volumes:
            - /etc/ssl/certs/ssl-cert-snakeoil.pem:/app/fullchain.pem
            - /etc/ssl/private/ssl-cert-snakeoil.key:/app/privkey.pem



## Decode JWT header

If you specify the header that contains the JWT, the echo output will contain the decoded JWT.  Use the `JWT_HEADER` environment variable for this.

    docker run -e JWT_HEADER=Authentication -p 8080:8080 -p 8443:8443 --rm -it mendhak/http-https-echo:25


Now make your request with `Authentication: eyJ...` header (it should also work with the `Authentication: Bearer eyJ...` schema too):

     curl -k -H "Authentication: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" http://localhost:8080/

And in the output you should see a `jwt` section.

## Disable ExpressJS log lines

In the log output set the environment variable `DISABLE_REQUEST_LOGS` to true, to disable the specific ExpressJS request log lines. The ones like `::ffff:172.17.0.1 - - [03/Jan/2022:21:31:51 +0000] "GET /xyz HTTP/1.1" 200 423 "-" "curl/7.68.0"`.  The JSON output will still appear.

    docker run --rm -e DISABLE_REQUEST_LOGS=true --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:25


## Do not log specific path

Set the environment variable `LOG_IGNORE_PATH` to a path you would like to exclude from verbose logging to stdout.
This can help reduce noise from healthchecks in orchestration/infrastructure like Swarm, Kubernetes, ALBs, etc.

     docker run -e LOG_IGNORE_PATH=/ping -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:25


With docker compose, this would be:

    my-http-listener:
        image: mendhak/http-https-echo:25
        environment:
            - LOG_IGNORE_PATH=/ping
        ports:
            - "8080:8080"
            - "8443:8443"


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

## Send an empty response

You can disable the JSON output in the response by setting the environment variable `ECHO_BACK_TO_CLIENT`. For example,

```bash
docker run -e ECHO_BACK_TO_CLIENT=false -p 8080:8080 -p 8443:8443 --rm -t mendhak/http-https-echo:25
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
docker run -d --rm -e ECHO_INCLUDE_ENV_VARS=1 --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:25
```

Then do a normal request via curl or browser, and you will see the `env` property in the response body.  


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


## Output

#### Curl output

![curl](https://raw.githubusercontent.com/mendhak/docker-http-https-echo/master/screenshots/screenshot2.png)

#### `docker logs` output

![dockerlogs](https://raw.githubusercontent.com/mendhak/docker-http-https-echo/master/screenshots/screenshot3.png)



## Building

    docker build -t mendhak/http-https-echo .

Run some tests to make sure features are working as expected.

    ./tests.sh

To create a new image on Docker Hub, I need to create a tag and push it.

    git tag -s 16
    git push --tags


## Changelog

See the [changelog](CHANGELOG.md)