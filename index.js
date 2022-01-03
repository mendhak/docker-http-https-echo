var express = require('express')
const morgan = require('morgan');
var http = require('http')
var https = require('https')
var app = express()
const os = require('os');
const jwt = require('jsonwebtoken');
var concat = require('concat-stream');
const { promisify } = require('util');
const sleep = promisify(setTimeout);

app.set('json spaces', 2);
app.set('trust proxy', ['loopback', 'linklocal', 'uniquelocal']);

if(process.env.DISABLE_REQUEST_LOGS !== 'true'){
  app.use(morgan('combined'));
}

app.use(function(req, res, next){
  req.pipe(concat(function(data){
    req.body = data.toString('utf8');
    next();
  }));
});

app.all('*', (req, res) => {
  const echo = {
    path: req.path,
    headers: req.headers,
    method: req.method,
    body: req.body,
    cookies: req.cookies,
    fresh: req.fresh,
    hostname: req.hostname,
    ip: req.ip,
    ips: req.ips,
    protocol: req.protocol,
    query: req.query,
    subdomains: req.subdomains,
    xhr: req.xhr,
    os: {
      hostname: os.hostname()
    },
    connection: {
      servername: req.connection.servername
    }
  };

  if(req.is('application/json')){
    echo.json = JSON.parse(req.body)
  }

  if (process.env.JWT_HEADER) {
    let token = req.headers[process.env.JWT_HEADER.toLowerCase()];
    if (!token) {
      echo.jwt = token;
    } else {
      token = token.split(" ").pop();
      const decoded = jwt.decode(token, {complete: true});
      echo.jwt = decoded;
    }
  }
  const setResponseStatusCode = parseInt(req.headers["x-set-response-status-code"] || req.query["x-set-response-status-code"], 10)
  if (100 <= setResponseStatusCode && setResponseStatusCode < 600) {
    res.status(setResponseStatusCode)
  }

  const sleepTime = parseInt(req.headers["x-set-response-delay-ms"] || req.query["x-set-response-delay-ms"], 0)
  sleep(sleepTime).then(() => {
    
    if (process.env.ECHO_BACK_TO_CLIENT != undefined && process.env.ECHO_BACK_TO_CLIENT == "false"){
      res.end();
    } else {
      res.json(echo);
    }

    if (process.env.LOG_IGNORE_PATH != req.path) {
 
      let spacer = 4;
      if(process.env.LOG_WITHOUT_NEWLINE){
        spacer = null;
      }
  
      console.log(JSON.stringify(echo, null, spacer));
    }
  });

  
});

const sslOpts = {
  key: require('fs').readFileSync('privkey.pem'),
  cert: require('fs').readFileSync('fullchain.pem'),
};

var httpServer = http.createServer(app).listen(process.env.HTTP_PORT || 8080);
var httpsServer = https.createServer(sslOpts,app).listen(process.env.HTTPS_PORT || 8443);
console.log(`Listening on ports ${process.env.HTTP_PORT || 8080} and ${process.env.HTTPS_PORT || 8443}`);

let calledClose = false;

process.on('exit', function () {
  if (calledClose) return;
  console.log('Got exit event. Trying to stop Express server.');
  server.close(function() {
    console.log("Express server closed");
  });
});

process.on('SIGINT', shutDown);
process.on('SIGTERM', shutDown);

function shutDown(){
  console.log('Got a kill signal. Trying to exit gracefully.');
  calledClose = true;
  httpServer.close(function() {
    httpsServer.close(function() {
      console.log("HTTP and HTTPS servers closed. Asking process to exit.");
      process.exit()
    });
  });
}
