FROM node:4.4
COPY . /app
WORKDIR /app
RUN npm install
CMD npm start
