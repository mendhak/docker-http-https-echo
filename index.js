var express = require('express')
const morgan = require('morgan');
var app = express()
const os = require('os');
const jwt = require('jsonwebtoken');

app.set('json spaces', 2);

app.use(morgan('combined'));

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
    }
  };
  if (process.env.JWT_HEADER) {
    const token = req.headers[process.env.JWT_HEADER.toLowerCase()];
    if (!token) {
      echo.jwt = token;
    } else {
      const decoded = jwt.decode(token, {complete: true});
      echo.jwt = decoded;
    }
  }
  res.json(echo);
})

app.listen(process.env.PORT || 80)
