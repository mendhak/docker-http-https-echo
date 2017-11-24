FROM yolean/node
COPY . /app
WORKDIR /app
RUN npm install
CMD npm start
