FROM node:24-alpine
WORKDIR /app
COPY package.json server.mjs ./
ENV HOST=0.0.0.0 PORT=5174
EXPOSE 5174
RUN mkdir -p /app/state && chown node:node /app/state
USER node
CMD ["node","server.mjs"]

