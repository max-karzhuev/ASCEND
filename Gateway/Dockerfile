FROM node:24-alpine
WORKDIR /app
COPY package.json server.mjs providers.mjs schema.mjs ./
RUN mkdir /data && chown node:node /data
USER node
ENV HOST=0.0.0.0 PORT=8787 STATE_DIR=/data
EXPOSE 8787
CMD ["node", "server.mjs"]
