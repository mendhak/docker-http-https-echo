FROM solsson/node:8
COPY . /app
WORKDIR /app
RUN npm install
CMD npm start
