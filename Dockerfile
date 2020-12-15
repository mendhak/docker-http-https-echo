# BUILD
# docker build \
# --force-rm=true \
# -f Dockerfile \
# -t docker-http-https-echo .

# RUN
# docker run --rm -it \
# -p 8080:8080 -p 8443:8443 \
# docker-http-https-echo

FROM node:14-alpine

WORKDIR /app
COPY . /app
ENV HTTP_PORT=8080 HTTPS_PORT=8443

RUN npm install --production
RUN apk --no-cache add openssl && sh generate-cert.sh && rm -rf /var/cache/apk/*

RUN chmod -R 775 /app
RUN chown -R node:node /app

USER 1000

CMD ["node", "./index.js"]
