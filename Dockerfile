# syntax=docker/dockerfile:1

# --- Build stage -----------------------------------------------------------
# Using the tag here for readability; CI pins it by digest. Keep this current —
# the Grype scan flags critical CVEs in the Go stdlib baked into the binary, so
# an out-of-date builder fails the pipeline.
FROM golang:1.26 AS build

WORKDIR /src

# Copy go.mod first so module download caches separately from source.
COPY go.mod ./
RUN go mod download

COPY . .

# VERSION comes from the pipeline (git tag or short SHA) and gets baked into the
# binary. CGO off so we get a static binary that works on distroless.
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags "-s -w -X github.com/brawndon-manu/nahui/internal/server.Version=${VERSION}" \
    -o /out/nahui-app ./cmd/nahui-app

# --- Runtime stage ---------------------------------------------------------
# Distroless: no shell, no package manager. Keeps the SBOM and attack surface
# small. Runs as the built-in nonroot user.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/nahui-app /nahui-app

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/nahui-app"]
