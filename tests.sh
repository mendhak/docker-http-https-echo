#!/usr/bin/env bash

set -euo pipefail

function message {
    echo ""
    echo "---------------------------------------------------------------"
    echo $1
    echo "---------------------------------------------------------------"
}

RESTORE=$(echo -en '\033[0m')
RED=$(echo -en '\033[01;31m')
GREEN=$(echo -en '\033[01;32m')

function failed {
    echo ${RED}✗$1${RESTORE}
}

function passed {
    echo ${GREEN}✓$1${RESTORE}
}

if ! [ -x "$(command -v jq)" ]; then
    message "JQ not installed. Installing..."
    sudo apt -y install jq
fi

message " Check if we're in Github Actions or local run "
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo " Github Actions. Image should already be built."
    docker images
    if [ -z "$(docker images -q mendhak/http-https-echo:testing 2> /dev/null)" ]; then
        echo "Docker image mendhak/http-https-echo:testing not found. Exiting."
        exit 1
    fi
else
    echo " Local run. Build image "
    docker build -t mendhak/http-https-echo:testing .
fi


mkdir -p testarea
pushd testarea

message " Cleaning up from previous test run "
docker ps -aq --filter "name=http-echo-tests" | grep -q . && docker stop http-echo-tests && docker rm -f http-echo-tests

message " Start container normally "
docker run -d --rm --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 10


message " Make http(s) request, and test the path, method, header and status code. "
REQUEST=$(curl -s -k -X PUT -H "Arbitrary:Header" -d aaa=bbb 'https://localhost:8443/hello-world?ccc=ddd&myquery=98765')
if [ $(echo $REQUEST | jq -r '.path') == '/hello-world' ] && \
   [ $(echo $REQUEST | jq -r '.method') == 'PUT' ] && \
   [ $(echo $REQUEST | jq -r '.query.myquery') == '98765' ] && \
   [ $(echo $REQUEST | jq -r '.headers.arbitrary') == 'Header' ]
then
    passed "HTTPS request passed."
else
    failed "HTTPS request failed."
    echo $REQUEST | jq
    exit 1
fi
REQUEST_WITH_STATUS_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -H "x-set-response-status-code: 404" https://localhost:8443/hello-world)
REQUEST_WITH_STATUS_CODE_V=$(curl -v -k -o /dev/null -w "%{http_code}" -H "x-set-response-status-code: 404" https://localhost:8443/hello-world)
if [ $(echo $REQUEST_WITH_STATUS_CODE == '404') ]
then
    passed "HTTPS status code header passed."
else
    failed "HTTPS status code header failed."
    echo $REQUEST_WITH_STATUS_CODE_V
    exit 1
fi

REQUEST_WITH_STATUS_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" https://localhost:8443/status/test?x-set-response-status-code=419)
REQUEST_WITH_STATUS_CODE_V=$(curl -v -k -o /dev/null -w "%{http_code}" https://localhost:8443/hello-world?x-set-response-status-code=419)
if [ $(echo $REQUEST_WITH_STATUS_CODE == '419') ]
then
    passed "HTTPS status code querystring passed."
else
    failed "HTTPS status code querystring failed."
    echo $REQUEST_WITH_STATUS_CODE_V
    exit 1
fi

REQUEST_WITH_CONTENT_TYPE_HEADER=$(curl -o /dev/null -k -Ss -w "%{content_type}" -H "x-set-response-content-type: aaaa/bbbb" https://localhost:8443/)
if [[ "$REQUEST_WITH_CONTENT_TYPE_HEADER" == *"aaaa/bbbb"* ]]; then
  passed "Request with custom response type header, passed"
else
  echo $REQUEST_WITH_CONTENT_TYPE_HEADER
  failed "Request with custom response type header, failed."
  exit 1
fi

REQUEST_WITH_CONTENT_TYPE_PARAMETER=$(curl -o /dev/null -k -Ss -w "%{content_type}" https://localhost:8443/green/chocolate?x-set-response-content-type=jellyfish/cabbage)
if [[ "$REQUEST_WITH_CONTENT_TYPE_PARAMETER" == *"jellyfish/cabbage"* ]]; then
  passed "Request with custom response type parameter, passed"
else
  echo $REQUEST_WITH_CONTENT_TYPE_PARAMETER
  failed "Request with custom response type parameter, failed."
  exit 1
fi


REQUEST_WITH_SLEEP_MS=$(curl -o /dev/null -Ss -H "x-set-response-delay-ms: 6000" -k https://localhost:8443/ -w '%{time_total}')
if [[ $(echo "$REQUEST_WITH_SLEEP_MS>5" | bc -l) == 1 ]]; then
    passed "Request header with response delay passed"
else
    failed "Request header with response delay failed"
    echo $REQUEST_WITH_SLEEP_MS
    exit 1
fi

REQUEST_WITH_SLEEP_MS=$(curl -o /dev/null -Ss -k https://localhost:8443/sleep/test?x-set-response-delay-ms=5000 -w '%{time_total}')
if [[ $(echo "$REQUEST_WITH_SLEEP_MS>4" | bc -l) == 1 ]]; then
    passed "Request query with response delay passed"
else
    failed "Request query with response delay failed"
    echo $REQUEST_WITH_SLEEP_MS
    exit 1
fi

REQUEST_WITH_INVALID_SLEEP_MS=$(curl -o /dev/null -Ss -H "x-set-response-delay-ms: XXXX" -k https://localhost:8443/ -w '%{time_total}')
if [[ $(echo "$REQUEST_WITH_INVALID_SLEEP_MS<2" | bc -l) == 1 ]]; then
    passed "Request with invalid response delay passed"
else
    failed "Request with invalid response delay failed"
    echo $REQUEST_WITH_INVALID_SLEEP_MS
    exit 1
fi

REQUEST=$(curl -s -X PUT -H "Arbitrary:Header" -d aaa=bbb http://localhost:8080/hello-world)
if [ $(echo $REQUEST | jq -r '.path') == '/hello-world' ] && \
   [ $(echo $REQUEST | jq -r '.method') == 'PUT' ] && \
   [ $(echo $REQUEST | jq -r '.headers.arbitrary') == 'Header' ]
then
    passed "HTTP request with arbitrary header passed."
else
    failed "HTTP request with arbitrary header failed."
    echo $REQUEST | jq
    exit 1
fi

message " Make JSON request, and test that json is in the output. "
REQUEST=$(curl -s -X POST -H "Content-Type: application/json" -d '{"a":"b"}' http://localhost:8080/)
if [ $(echo $REQUEST | jq -r '.json.a') == 'b' ]
then
    passed "JSON test passed."
else
    failed "JSON test failed."
    echo $REQUEST | jq
    exit 1
fi


message " Make JSON request with gzip Content-Encoding, and test that json is in the output. "
REQUEST=$(echo -n '{"a":"b"}' | gzip | curl -s -X POST -H "Content-Encoding: gzip" -H "Content-Type: application/json" --data-binary @- http://localhost:8080/)
if [ $(echo $REQUEST | jq -r '.json.a') == 'b' ]
then
    passed "JSON test passed."
else
    failed "JSON test failed."
    echo $REQUEST | jq
    exit 1
fi

REQUEST=$(curl -s -X POST -H "Content-Type: application/json" -d 'not-json' http://localhost:8080)
if [ $(echo $REQUEST | jq -r '.json') == 'null' ]; then
    passed "JSON with Invalid Body test passed."
else
    failed "JSON with Invalid Body test failed."
    echo $REQUEST | jq
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with different internal ports "
docker run -d --rm -e HTTP_PORT=8888 -e HTTPS_PORT=9999 --name http-echo-tests -p 8080:8888 -p 8443:9999 -t mendhak/http-https-echo:testing
sleep 5

message " Make http(s) request, and test the path, method and header. "
REQUEST=$(curl -s -k -X PUT -H "Arbitrary:Header" -d aaa=bbb https://localhost:8443/hello-world)
if [ $(echo $REQUEST | jq -r '.path') == '/hello-world' ] && \
   [ $(echo $REQUEST | jq -r '.method') == 'PUT' ] && \
   [ $(echo $REQUEST | jq -r '.headers.arbitrary') == 'Header' ]
then
    passed "HTTPS request passed."
else
    failed "HTTPS request failed."
    echo $REQUEST | jq
    exit 1
fi

REQUEST=$(curl -s -X PUT -H "Arbitrary:Header" -d aaa=bbb http://localhost:8080/hello-world)
if [ $(echo $REQUEST | jq -r '.path') == '/hello-world' ] && \
   [ $(echo $REQUEST | jq -r '.method') == 'PUT' ] && \
   [ $(echo $REQUEST | jq -r '.headers.arbitrary') == 'Header' ]
then
    passed "HTTP request passed."
else
    failed "HTTP request failed."
    echo $REQUEST | jq
    exit 1
fi


message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with empty responses "
docker run -d --rm -e ECHO_BACK_TO_CLIENT=false --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
REQUEST=$(curl -s -k http://localhost:8080/a/b/c)
if [[ -z ${REQUEST} ]]
then
    passed "Response is empty."
else
    failed "Expected empty response, but got a non-empty response."
    echo $REQUEST
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with response body only "
docker run -d --rm --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
RESPONSE=$(curl -s -k -X POST -d 'cauliflower' http://localhost:8080/a/b/c?response_body_only=true)
if [[ ${RESPONSE} == "cauliflower" ]]
then
    passed "Response body only received."
else
    failed "Expected response body only."
    echo $RESPONSE
    exit 1
fi


message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with JWT_HEADER "
docker run -d --rm -e JWT_HEADER=Authentication --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5

REQUEST=$(curl -s -k -H "Authentication: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" https://localhost:8443/ )
if [ $(echo $REQUEST | jq -r '.jwt.header.typ') == 'JWT' ] && \
   [ $(echo $REQUEST | jq -r '.jwt.header.alg') == 'HS256' ] && \
   [ $(echo $REQUEST | jq -r '.jwt.payload.sub') == '1234567890' ]
then
    passed "JWT request passed."
else
    failed "JWT request failed."
    echo $REQUEST | jq
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5


message " Start container with LOG_IGNORE_PATH (normal path)"
docker run -d --rm -e LOG_IGNORE_PATH=/ping --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X POST -d "banana" https://localhost:8443/ping > /dev/null

if [ $(docker logs http-echo-tests | wc -l) == 2 ] && \
   ! [ $(docker logs http-echo-tests | grep banana) ]
then
    passed "LOG_IGNORE_PATH ignored the /ping path"
else
    failed "LOG_IGNORE_PATH failed"
    docker logs http-echo-tests
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with LOG_IGNORE_PATH (regex path)"
docker run -d --rm -e LOG_IGNORE_PATH="^\/ping|^\/health|^\/metrics" --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X POST -d "banana" https://localhost:8443/metrics > /dev/null

if [ $(docker logs http-echo-tests | wc -l) == 2 ] && \
   ! [ $(docker logs http-echo-tests | grep banana) ]
then
    passed "LOG_IGNORE_PATH ignored the /metrics path"
else
    failed "LOG_IGNORE_PATH failed"
    docker logs http-echo-tests
    exit 1
fi

# Test a positive case where the path is not ignored
curl -s -k -X POST -d "strawberry" https://localhost:8443/veryvisible > /dev/null

if [[ $(docker logs http-echo-tests | grep strawberry) ]]
then
    passed "LOG_IGNORE_PATH didn't ignore the /veryvisible path"
else
    failed "LOG_IGNORE_PATH failed, it should not ignore the /veryvisible path"
    docker logs http-echo-tests
    exit 1
fi


message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with LOG_IGNORE_PATH (ignore all paths) "
docker run -d --rm -e LOG_IGNORE_PATH=".*" --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X POST -d "banana" https://localhost:8443/ > /dev/null

if [ $(docker logs http-echo-tests | wc -l) == 2 ] && \
   ! [ $(docker logs http-echo-tests | grep banana) ]
then
    passed "LOG_IGNORE_PATH ignored all paths"
else
    failed "LOG_IGNORE_PATH failed"
    docker logs http-echo-tests
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5


message " Start container with DISABLE_REQUEST_LOGS "
docker run -d --rm -e DISABLE_REQUEST_LOGS=true --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X GET https://localhost:8443/strawberry > /dev/null
if  [ $(docker logs http-echo-tests | grep -c "GET /strawberry HTTP/1.1") -eq 0 ]
then
    passed "DISABLE_REQUEST_LOGS disabled Express HTTP logging"
else
    failed "DISABLE_REQUEST_LOGS failed"
    docker logs http-echo-tests
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with CORS_CONFIG"
docker run -d --rm \
    -e CORS_ALLOW_ORIGIN="http://example.com" -e CORS_ALLOW_HEADERS="x-custom-test-header" \
    --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
# Check if the expected CORS headers are present in the response
if curl -s -i http://localhost:8080/ 2>&1 | grep -q -E \
    "Access-Control-Allow-Headers: x-custom-test-header" &&
    curl -s -i http://localhost:8080/ 2>&1 | grep -q -E \
    "Access-Control-Allow-Origin: http://example.com"; then
    passed "CORS_CONFIG expected CORS headers found in response"
else
    failed "CORS_CONFIG failed."
    docker logs http-echo-tests
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with LOG_WITHOUT_NEWLINE "
docker run -d --rm -e LOG_WITHOUT_NEWLINE=1 --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X POST -d "tiramisu" https://localhost:8443/ > /dev/null

if [ $(docker logs http-echo-tests | wc -l) == 3 ] && \
   [ $(docker logs http-echo-tests | grep tiramisu) ]
then
    passed "LOG_WITHOUT_NEWLINE logged output in single line"
else
    failed "LOG_WITHOUT_NEWLINE failed"
    docker logs http-echo-tests
    exit 1
fi


message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Check that container is running as a NON ROOT USER by default"
docker run -d --name http-echo-tests --rm mendhak/http-https-echo:testing

WHOAMI=$(docker exec http-echo-tests whoami)

if [ "$WHOAMI" == "node" ]
then
    passed "Running as non root user"
else
    failed "Running as root user"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Check that container is running as user different that the user defined in image"
IMAGE_USER="$(docker image inspect mendhak/http-https-echo:testing -f '{{ .Config.User }}')"
CONTAINER_USER="$((IMAGE_USER + 1000000))"
docker run -d --name http-echo-tests --rm -u "${CONTAINER_USER}" -p 8080:8080 mendhak/http-https-echo:testing
sleep 5
curl -s http://localhost:8080 > /dev/null

WHOAMI="$(docker exec http-echo-tests id -u)"

if [ "$WHOAMI" == "$CONTAINER_USER" ]
then
    passed "Running as $CONTAINER_USER user"
else
    failed "Not running as $CONTAINER_USER user or failed to start"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Check that mTLS server responds with client certificate details"
# Generate a new self signed cert locally
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout privkey.pem -out fullchain.pem \
       -subj "/CN=client.example.net" \
       -addext "subjectAltName=DNS:client.example.net"
docker run -d --rm -e MTLS_ENABLE=1 --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
COMMON_NAME="$(curl -sk --cert fullchain.pem --key privkey.pem  https://localhost:8443/ | jq -r  '.clientCertificate.subject.CN')"
SAN="$(curl -sk --cert fullchain.pem --key privkey.pem  https://localhost:8443/ | jq -r  '.clientCertificate.subjectaltname')"
if [ "$COMMON_NAME" == "client.example.net" ] && [ "$SAN" == "DNS:client.example.net" ]
then
    passed "Client certificate details are present in the output"
else
    failed "Client certificate details not found in output"
    exit 1
fi

message " Check if certificate is not passed, then client certificate details are empty"
CLIENT_CERT="$(curl -sk https://localhost:8443/ | jq -r  '.clientCertificate')"
if [ "$CLIENT_CERT" == "{}" ]
then
    passed "Client certificate details are not present in the response"
else
    failed "Client certificate details found in output? ${CLIENT_CERT}"
    exit 1
fi

message " Check that HTTP server does not have any client certificate property"
CLIENT_CERT=$(curl -sk --cert cert.pem --key privkey.pem  http://localhost:8080/  | jq  'has("clientCertificate")')
if [ "$CLIENT_CERT" == "false" ]
then
    passed "Client certificate details are not present in regular HTTP server"
else
    failed "Client certificate details found in output? ${CLIENT_CERT}"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Check that SSL certificate and private key are loaded from custom location"
cert_common_name="server.example.net"
https_cert_file="$(pwd)/server_fullchain.pem"
https_key_file="$(pwd)/server_privkey.pem"
# Generate a new self signed cert locally
openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout "${https_key_file}" -out "${https_cert_file}" \
       -subj "/CN=${cert_common_name}" \
       -addext "subjectAltName=DNS:${cert_common_name}"
chmod a+r "${https_cert_file}"
chmod a+r "${https_key_file}"
container_https_cert_file="/test/tls.crt"
container_https_key_file="/test/tls.key"
docker run -d --rm \
  -v "${https_cert_file}:${container_https_cert_file}:ro,z" \
  -e HTTPS_CERT_FILE="${container_https_cert_file}" \
  -v "${https_key_file}:${container_https_key_file}:ro,z" \
  -e HTTPS_KEY_FILE="${container_https_key_file}" \
  --name http-echo-tests -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5

REQUEST_WITH_STATUS_CODE="$(curl -s --cacert "$(pwd)/server_fullchain.pem" -o /dev/null -w "%{http_code}" \
  --resolve "${cert_common_name}:8443:127.0.0.1" "https://${cert_common_name}:8443/hello-world")"
if [ "${REQUEST_WITH_STATUS_CODE}" = 200 ]
then
    passed "Server certificate and private key are loaded from configured custom location"
else
    failed "Custom certificate location test failed"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Check that environment variables returned in response if enabled"
docker run -d --rm -e ECHO_INCLUDE_ENV_VARS=1 --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
RESPONSE_BODY="$(curl -sk https://localhost:8443/ | jq -r  '.env.ECHO_INCLUDE_ENV_VARS')"

if [ "$RESPONSE_BODY" == "1" ]
then
    passed "Environment variables present in the output"
else
    failed "Client certificate details found in output? ${RESPONSE_BODY}"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Check that environment variables are not present in response by default"
docker run -d --rm --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
RESPONSE_BODY_ENV_CHECK="$(curl -sk https://localhost:8443/ | jq 'has("env")')"

if [ "$RESPONSE_BODY_ENV_CHECK" == "false" ]
then
    passed "Environment variables not present in the output by default"
else
    failed "Environment variables found in output?"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with PROMETHEUS disabled "
docker run -d --rm --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X POST -d "tiramisu" https://localhost:8443/ > /dev/null

# grep for  http_request_duration_seconds_count ensure it is not present at /metric path

METRICS_CHECK="$(curl -sk http://localhost:8080/metrics | grep -v http_request_duration_seconds_count )"

if [[ "$METRICS_CHECK" == *"http_request_duration_seconds_count"* ]]
then
    failed "PROMETHEUS metrics are enabled"
    exit 1
else
    passed "PROMETHEUS metrics are disabled by default"
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with PROMETHEUS enabled "
docker run -d -e PROMETHEUS_ENABLED=true --rm --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing
sleep 5
curl -s -k -X POST -d "tiramisu" https://localhost:8443/ > /dev/null

METRICS_CHECK="$(curl -sk http://localhost:8080/metrics | grep http_request_duration_seconds_count )"

if [[ "$METRICS_CHECK" == *"http_request_duration_seconds_count"* ]]
then
    passed "PROMETHEUS metrics are enabled"
else
    failed "PROMETHEUS metrics are disabled"
    exit 1
fi


message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with PRESERVE_HEADER_CASE enabled "
docker run -d -e PRESERVE_HEADER_CASE=true --rm --name http-echo-tests -p 8080:8080 -p 8443:8443 -t mendhak/http-https-echo:testing

sleep 5
HEADER_CASE_CHECK=$(curl -s -H "prEseRVe-CaSE: A1b2C3" -H 'x-a-b: 999'  -H 'X-a-B: 13'  localhost:8080 | jq -r '.headers."prEseRVe-CaSE"')
if [[ "$HEADER_CASE_CHECK" == "A1b2C3" ]]
then
    passed "PRESERVE_HEADER_CASE enabled"
else
    failed "PRESERVE_HEADER_CASE failed"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

message " Start container with a custom response body from a file "
echo "<h1>Hello World</h1>" > test.html
docker run -d --rm -v ${PWD}/test.html:/app/test.html --name http-echo-tests -p 8080:8080 -e OVERRIDE_RESPONSE_BODY_FILE_PATH=/test.html -t mendhak/http-https-echo:testing
sleep 5
RESPONSE_BODY=$(curl -s http://localhost:8080)
if [[ "$RESPONSE_BODY" == "<h1>Hello World</h1>" ]]
then
    passed "Custom response body from file"
else
    failed "Custom response body from file failed"
    exit 1
fi

message " Stop containers "
docker stop http-echo-tests
sleep 5

popd
rm -rf testarea
message "DONE"
