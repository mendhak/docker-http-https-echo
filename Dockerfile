FROM node:9.2-alpine

WORKDIR /app

COPY . .

RUN npm install --production

RUN apk --no-cache add openssl && sh generate-cert.sh && rm -rf /var/cache/apk/*

EXPOSE 80 443


ENTRYPOINT ["node", "./index.js"]
CMD []
