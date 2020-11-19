#!/usr/bin/env bash

function message {
    echo ""
    echo "---------------------------------------------------------------"
    echo $1
    echo "---------------------------------------------------------------"
}

RESTORE=$(echo -en '\033[0m')
RED=$(echo -en '\033[01;31m')
GREEN=$(echo -en '\033[01;32m')
YELLOW=$(echo -en '\033[00;33m')
BLUE=$(echo -en '\033[00;34m')
MAGENTA=$(echo -en '\033[00;35m')
PURPLE=$(echo -en '\033[00;35m')
CYAN=$(echo -en '\033[00;36m')
LIGHTGRAY=$(echo -en '\033[00;37m')
LRED=$(echo -en '\033[01;31m')
LGREEN=$(echo -en '\033[01;32m')
LYELLOW=$(echo -en '\033[01;33m')
LBLUE=$(echo -en '\033[01;34m')
LMAGENTA=$(echo -en '\033[01;35m')
LPURPLE=$(echo -en '\033[01;35m')
LCYAN=$(echo -en '\033[01;36m')
WHITE=$(echo -en '\033[01;37m')



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


message " Build image "
docker build -t mendhak/http-https-echo:latest .

mkdir -p testarea
pushd testarea

message " Cleaning up from previous test run "
docker ps -q --filter "name=http-echo-tests" | grep -q . && docker stop http-echo-tests

message " Start container "
docker run -d --rm --name http-echo-tests -p 8080:80 -p 8443:443 -t mendhak/http-https-echo
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

message " Stop containers "
docker stop http-echo-tests 

message " Start container with different internal ports "
docker run -d --rm -e HTTP_PORT=8888 -e HTTPS_PORT=9999 --name http-echo-tests -p 8080:8888 -p 8443:9999 -t mendhak/http-https-echo
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


message " Start container with JWT_HEADER "
docker run -d --rm -e JWT_HEADER=Authentication --name http-echo-tests -p 8080:80 -p 8443:443 -t mendhak/http-https-echo
sleep 5

REQUEST=$(curl -s -k -H "Authentication: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" https://localhost:8443/ )
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





popd
rm -rf testarea