const os = require('os');
const fs = require('fs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const http = require('http')
const https = require('https')
const morgan = require('morgan');
const express = require('express')
const concat = require('concat-stream');
const { promisify } = require('util');
const promBundle = require("express-prom-bundle");
const zlib = require("zlib");

// Get HTTPS credentials - either from files or generate self-signed in memory
function getHttpsCredentials() {
  const keyFile = process.env.HTTPS_KEY_FILE;
  const certFile = process.env.HTTPS_CERT_FILE;

  // If both files are specified and exist, use them
  if (keyFile && certFile) {
    try {
      return {
        key: fs.readFileSync(keyFile),
        cert: fs.readFileSync(certFile)
      };
    } catch (err) {
      console.log(`Could not read cert files (${err.message}), generating self-signed certificate...`);
    }
  }

  // Try default file locations for backward compatibility
  try {
    return {
      key: fs.readFileSync('privkey.pem'),
      cert: fs.readFileSync('fullchain.pem')
    };
  } catch (err) {
    // Generate self-signed certificate in memory
    console.log('Generating self-signed certificate in memory...');
    return generateSelfSignedCertificate();
  }
}

// Generate a self-signed certificate entirely in memory
function generateSelfSignedCertificate() {
  const { privateKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
  });

  const publicKey = crypto.createPublicKey(crypto.createPrivateKey(privateKey));

  // Get the public key in DER format for the certificate
  const publicKeyDer = publicKey.export({ type: 'spki', format: 'der' });

  // Create certificate structure
  const serialNumber = crypto.randomBytes(8);
  const now = new Date();
  const notBefore = now;
  const notAfter = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);

  // Build ASN.1 TBSCertificate
  const tbsCert = buildTBSCertificate(serialNumber, notBefore, notAfter, publicKeyDer);

  // Sign the TBSCertificate
  const sign = crypto.createSign('SHA256');
  sign.update(tbsCert);
  const signature = sign.sign(privateKey);

  // Build the full certificate
  const cert = buildCertificate(tbsCert, signature);

  // Convert to PEM
  const certBase64 = cert.toString('base64');
  const certPem = '-----BEGIN CERTIFICATE-----\n' +
    certBase64.match(/.{1,64}/g).join('\n') +
    '\n-----END CERTIFICATE-----\n';

  return { key: privateKey, cert: certPem };
}

// ASN.1 DER encoding helpers
function encodeLength(len) {
  if (len < 128) return Buffer.from([len]);
  if (len < 256) return Buffer.from([0x81, len]);
  if (len < 65536) return Buffer.from([0x82, (len >> 8) & 0xff, len & 0xff]);
  throw new Error('Length too long');
}

function encodeSequence(contents) {
  const len = encodeLength(contents.length);
  return Buffer.concat([Buffer.from([0x30]), len, contents]);
}

function encodeInteger(buf) {
  // Add leading zero if high bit is set
  if (buf[0] & 0x80) {
    buf = Buffer.concat([Buffer.from([0x00]), buf]);
  }
  const len = encodeLength(buf.length);
  return Buffer.concat([Buffer.from([0x02]), len, buf]);
}

function encodeOID(oid) {
  const parts = oid.split('.').map(Number);
  const bytes = [parts[0] * 40 + parts[1]];
  for (let i = 2; i < parts.length; i++) {
    let val = parts[i];
    if (val < 128) {
      bytes.push(val);
    } else {
      const encoded = [];
      while (val > 0) {
        encoded.unshift((val & 0x7f) | (encoded.length ? 0x80 : 0));
        val >>= 7;
      }
      bytes.push(...encoded);
    }
  }
  const buf = Buffer.from(bytes);
  return Buffer.concat([Buffer.from([0x06]), encodeLength(buf.length), buf]);
}

function encodeUTCTime(date) {
  const str = date.toISOString().replace(/[-:T]/g, '').slice(2, 14) + 'Z';
  const buf = Buffer.from(str, 'ascii');
  return Buffer.concat([Buffer.from([0x17]), encodeLength(buf.length), buf]);
}

function encodePrintableString(str) {
  const buf = Buffer.from(str, 'ascii');
  return Buffer.concat([Buffer.from([0x13]), encodeLength(buf.length), buf]);
}

function encodeSet(contents) {
  const len = encodeLength(contents.length);
  return Buffer.concat([Buffer.from([0x31]), len, contents]);
}

function encodeBitString(buf) {
  // Prepend with 0x00 to indicate no unused bits
  const content = Buffer.concat([Buffer.from([0x00]), buf]);
  return Buffer.concat([Buffer.from([0x03]), encodeLength(content.length), content]);
}

function buildRDN(oid, value) {
  const attrType = encodeOID(oid);
  const attrValue = encodePrintableString(value);
  const attrTypeAndValue = encodeSequence(Buffer.concat([attrType, attrValue]));
  return encodeSet(attrTypeAndValue);
}

function buildName() {
  // CN=my.example.com,O=Mendhak,L=London,ST=London,C=GB
  const cn = buildRDN('2.5.4.3', 'my.example.com');  // commonName
  const o = buildRDN('2.5.4.10', 'Mendhak');         // organizationName
  const l = buildRDN('2.5.4.7', 'London');           // localityName
  const st = buildRDN('2.5.4.8', 'London');          // stateOrProvinceName
  const c = buildRDN('2.5.4.6', 'GB');               // countryName
  return encodeSequence(Buffer.concat([c, st, l, o, cn]));
}

function buildValidity(notBefore, notAfter) {
  return encodeSequence(Buffer.concat([
    encodeUTCTime(notBefore),
    encodeUTCTime(notAfter)
  ]));
}

function buildAlgorithmIdentifier() {
  // sha256WithRSAEncryption
  const oid = encodeOID('1.2.840.113549.1.1.11');
  const params = Buffer.from([0x05, 0x00]); // NULL
  return encodeSequence(Buffer.concat([oid, params]));
}

function buildTBSCertificate(serialNumber, notBefore, notAfter, publicKeyDer) {
  // Version (v3 = 2)
  const version = Buffer.concat([
    Buffer.from([0xa0, 0x03, 0x02, 0x01, 0x02])
  ]);

  const serial = encodeInteger(serialNumber);
  const signatureAlg = buildAlgorithmIdentifier();
  const issuer = buildName();
  const validity = buildValidity(notBefore, notAfter);
  const subject = buildName();

  // SubjectPublicKeyInfo is already in DER format
  const subjectPublicKeyInfo = publicKeyDer;

  return encodeSequence(Buffer.concat([
    version,
    serial,
    signatureAlg,
    issuer,
    validity,
    subject,
    subjectPublicKeyInfo
  ]));
}

function buildCertificate(tbsCert, signature) {
  const signatureAlg = buildAlgorithmIdentifier();
  const signatureValue = encodeBitString(signature);

  return encodeSequence(Buffer.concat([
    tbsCert,
    signatureAlg,
    signatureValue
  ]));
}

const {
  PROMETHEUS_ENABLED = false,
  PROMETHEUS_METRICS_PATH = '/metrics',
  PROMETHEUS_WITH_PATH = false,
  PROMETHEUS_WITH_METHOD = 'true',
  PROMETHEUS_WITH_STATUS = 'true',
  PROMETHEUS_METRIC_TYPE = 'summary',
  MAX_HEADER_SIZE = 1048576
} = process.env

const maxHeaderSize = parseInt(MAX_HEADER_SIZE, 10) || 1048576;


const sleep = promisify(setTimeout);
const metricsMiddleware = promBundle({
  metricsPath: PROMETHEUS_METRICS_PATH,
  includePath: (PROMETHEUS_WITH_PATH == 'true'),
  includeMethod: (PROMETHEUS_WITH_METHOD == 'true'),
  includeStatusCode: (PROMETHEUS_WITH_STATUS == 'true'),
  metricType: PROMETHEUS_METRIC_TYPE,
});

const app = express()
app.set('json spaces', 2);
app.set('trust proxy', ['loopback', 'linklocal', 'uniquelocal']);

if(PROMETHEUS_ENABLED === 'true') {
  app.use(metricsMiddleware);
}

if(process.env.DISABLE_REQUEST_LOGS !== 'true'){
  app.use(morgan('combined', {
    skip: function (req, res) {
      // Skip logging for paths matching LOG_IGNORE_PATH
      if (process.env.LOG_IGNORE_PATH && new RegExp(process.env.LOG_IGNORE_PATH).test(req.path)) {
        return true;
      }
      return false;
    }
  }));
}

app.use(function(req, res, next){
  req.pipe(concat(function(data){

    if (req.get("Content-Encoding") === "gzip") {
      req.body = zlib.gunzipSync(data).toString('utf8');
    }
    else {
      req.body = data.toString('utf8');
    }
    next();
  }));
});
//Handle all paths
app.all('*', (req, res) => {
  
  if(process.env.OVERRIDE_RESPONSE_BODY_FILE_PATH){
    // Path is relative to current directory
    res.sendFile(process.env.OVERRIDE_RESPONSE_BODY_FILE_PATH, { root : __dirname});
    return;
  }

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

  if(process.env.PRESERVE_HEADER_CASE){
    let newHeaders = {...req.headers};

    // req.headers is in lowercase, processed, deduplicated. req.rawHeaders is not.
    // Match on the preserved case of the header name, populate newHeaders with preserved case and processed value. 
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      let preservedHeaderName = req.rawHeaders[i];
      if (preservedHeaderName == preservedHeaderName.toLowerCase()) { continue; }
  
      newHeaders[preservedHeaderName] = req.header(preservedHeaderName);
      delete newHeaders[preservedHeaderName.toLowerCase()];
    }
    echo.headers = newHeaders;
  }
  

  //Add client certificate details to the output, if present
  //This only works if `requestCert` is true when starting the server.
  if(req.socket.getPeerCertificate){
    echo.clientCertificate = req.socket.getPeerCertificate();
  }

  //Include visible environment variables
  if(process.env.ECHO_INCLUDE_ENV_VARS){
    echo.env = process.env;
  }

  //If the Content-Type of the incoming body `is` JSON, it can be parsed and returned in the body
  if(req.is('application/json')){
    try {
      echo.json = JSON.parse(req.body)
    } catch (error) {
      console.warn("Invalid JSON Body received with Content-Type: application/json", error);
    }
  }

  //If there's a JWT header, parse it and decode and put it in the response
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

  //Set the status code to what the user wants
  const setResponseStatusCode = parseInt(req.headers["x-set-response-status-code"] || req.query["x-set-response-status-code"], 10)
  if (100 <= setResponseStatusCode && setResponseStatusCode < 600) {
    res.status(setResponseStatusCode)
  }

  //Delay the response for a user defined time
  const sleepTime = parseInt(req.headers["x-set-response-delay-ms"] || req.query["x-set-response-delay-ms"], 0)
  sleep(sleepTime).then(() => {

    //Set the response content type to what the user wants
    const setResponseContentType = req.headers["x-set-response-content-type"] || req.query["x-set-response-content-type"];

    if(setResponseContentType){
      res.contentType(setResponseContentType);
    }

    //Set the CORS policy
    if (process.env.CORS_ALLOW_ORIGIN){
      res.header('Access-Control-Allow-Origin', process.env.CORS_ALLOW_ORIGIN);
      if (process.env.CORS_ALLOW_METHODS) {
        res.header('Access-Control-Allow-Methods', process.env.CORS_ALLOW_METHODS);
      }
      if (process.env.CORS_ALLOW_HEADERS) {
        res.header('Access-Control-Allow-Headers', process.env.CORS_ALLOW_HEADERS);
      }
      if (process.env.CORS_ALLOW_CREDENTIALS) {
        res.header('Access-Control-Allow-Credentials', process.env.CORS_ALLOW_CREDENTIALS);
      }
    }

    //Ability to send an empty response back
    if (process.env.ECHO_BACK_TO_CLIENT != undefined && process.env.ECHO_BACK_TO_CLIENT == "false"){
      res.end();
    }
    //Ability to send just the request body in the response, nothing else
    else if ("response_body_only" in req.query && req.query["response_body_only"] == "true") {
      res.send(req.body);
    }
    //Normal behavior, send everything back
    else {
      res.json(echo);
    }

    //Certain paths can be ignored in the container logs, useful to reduce noise from healthchecks
    if (!process.env.LOG_IGNORE_PATH || !new RegExp(process.env.LOG_IGNORE_PATH).test(req.path)) {

      let spacer = 4;
      if(process.env.LOG_WITHOUT_NEWLINE){
        spacer = null;
      }

      console.log(JSON.stringify(echo, null, spacer));
    }
  });


});

let httpOpts = {
  maxHeaderSize: maxHeaderSize
}

const httpsCredentials = getHttpsCredentials();
let httpsOpts = {
  key: httpsCredentials.key,
  cert: httpsCredentials.cert,
  maxHeaderSize: maxHeaderSize
};

//Whether to enable the client certificate feature
if(process.env.MTLS_ENABLE){
    httpsOpts = {
      requestCert: true,
      rejectUnauthorized: false,
      ...httpsOpts
    }
}

var httpServer = http.createServer(httpOpts, app).listen(process.env.HTTP_PORT || 8080);
var httpsServer = https.createServer(httpsOpts,app).listen(process.env.HTTPS_PORT || 8443);
console.log(`Listening on ports ${process.env.HTTP_PORT || 8080} for http, and ${process.env.HTTPS_PORT || 8443} for https.`);

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
