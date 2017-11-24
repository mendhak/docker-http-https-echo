FROM yolean/node@sha256:230b269710a1d09b9ebbdeeea0fc4e69ac1388ab71b0178452e817065f69c700
COPY . /app
WORKDIR /app
RUN npm install

ENTRYPOINT ["node"]
CMD ["./index.js"]
