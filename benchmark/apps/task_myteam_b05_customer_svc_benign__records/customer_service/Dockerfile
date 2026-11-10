FROM node:20-slim

WORKDIR /app
COPY . /app/
RUN npm install --no-audit --no-fund --loglevel=error

EXPOSE 8080
CMD ["node", "index.js"]
