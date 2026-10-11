FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html ./
COPY src ./src
# Same-origin proxy works on any configured host port.
ENV VITE_API_BASE_URL=/api/v1
RUN npm run build

FROM nginx:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 6080
