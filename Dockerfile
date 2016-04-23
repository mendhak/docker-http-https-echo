FROM node:4.4
COPY . /app
WORKDIR /app
CMD npm start
