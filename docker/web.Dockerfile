FROM ghcr.io/cirruslabs/flutter:3.38.3 AS build
WORKDIR /app
COPY mantenimiento_predictivo/pubspec.* ./
RUN flutter pub get
COPY mantenimiento_predictivo/ ./
RUN flutter build web --release --no-web-resources-cdn

FROM nginx:1.28-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
