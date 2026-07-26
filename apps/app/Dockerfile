# AllisWell web — published as ghcr.io/<owner>/alliswell-web on every version tag.
# Build context is the REPO ROOT.
#
# The bundle is architecture-independent JavaScript, so the Flutter stage pins
# itself to the BUILD platform: a multi-arch image then costs one compile, not
# one per architecture under QEMU emulation.
FROM --platform=$BUILDPLATFORM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /src
# Warm the pub cache on the manifest alone, so dependency resolution is not
# redone every time application code changes.
COPY apps/app/pubspec.yaml apps/app/pubspec.lock ./apps/app/
COPY apps/app/packages ./apps/app/packages
RUN cd apps/app && flutter pub get

COPY apps/app ./apps/app
# No --dart-define here on purpose: the API address is injected at CONTAINER
# START (see the entrypoint), which is what lets one published image serve
# every self-hoster's own domain.
RUN cd apps/app && flutter build web --release

FROM nginx:1.27-alpine

COPY --from=build /src/apps/app/build/web /usr/share/nginx/html
COPY docker/web-nginx.conf /etc/nginx/conf.d/default.conf
COPY docker/web-entrypoint.sh /docker-entrypoint.d/40-alliswell-config.sh
RUN chmod +x /docker-entrypoint.d/40-alliswell-config.sh

# Where the browser should reach the API, e.g. https://api.your-domain.example.
# Required: without it the bundle falls back to http://localhost:3000, which is
# almost never right for a served page.
ENV ALLISWELL_API_URL=""

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
