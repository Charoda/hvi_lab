FROM node:20-bookworm-slim

WORKDIR /app

COPY nodejs/express-multer/package*.json ./nodejs/express-multer/
WORKDIR /app/nodejs/express-multer
RUN npm install --omit=dev

WORKDIR /app
COPY . .

WORKDIR /app/nodejs/express-multer
RUN mkdir -p uploads

EXPOSE 3000

CMD ["npm", "start"]
