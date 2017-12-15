FROM node:9.2-alpine

WORKDIR /app

COPY . .

RUN rm -rf screenshots/

RUN npm install --production

RUN apk --no-cache add openssl

RUN sh generate-cert.sh

EXPOSE 80 443


ENTRYPOINT ["node", "./index.js"]
CMD []
