# Dockerfile-ssl
FROM alpine/openssl:latest AS ssl-builder
SHELL [ "/usr/bin/env", "sh", "-xec" ]

ARG TARGET_STAGE

COPY <<~ /etc/ssl/openssl-internal.cnf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
xcountryName = FR

[req_distinguished_name]
CN = docker-registry.lima.internal

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = host.containers.internal  # Replace with your domain or server hostname
~

FROM ssl-builder AS ssl-internal-certs

# Only execute the SSL certificate generation steps if the target stage is 'ssl'
RUN <<~
  cd /etc/ssl/certs
  openssl genpkey -algorithm RSA -out internal.key
  openssl req -new -x509 -sha256 -key internal.key -out internal.crt -days 365 -config /etc/ssl/openssl-internal.cnf
~

VOLUME /etc/ssl/certs

# Main Nginx Dockerfile
FROM nginx:latest as ssl-proxy
SHELL [ "/usr/bin/env", "bash", "-xec" ]

# Copy the generated certificate files from the ssl-builder stage
COPY --from=ssl-internal-certs --chmod=0222 /etc/ssl/certs/ /etc/nginx/certs.d/

# Install the proxy config
COPY <<'~' /etc/nginx/conf.d/docker-registry-upstream.conf
    upstream docker-registry {
      server registry:5000;
    }

    ## Set a variable to help us decide if we need to add the
    ## 'Docker-Distribution-Api-Version' header.
    ## The registry always sets this header.
    ## In the case of nginx performing auth, the header is unset
    ## since nginx is auth-ing before proxying.
    map $upstream_http_docker_distribution_api_version $docker_distribution_api_version {
      '' 'registry/2.0';
    }
~

# Install the proxy config
COPY <<'~' /etc/nginx/conf.d/registry.conf
  server {
    listen 443 ssl;
    server_name host.lima.internal;

    # SSL
    ssl_certificate /etc/nginx/certs.d/internal.crt;
    ssl_certificate_key /etc/nginx/certs.d/internal.key;

    # Recommendations from https://raymii.org/s/tutorials/Strong_SSL_Security_On_nginx.html
    ssl_protocols TLSv1.1 TLSv1.2;
    ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    # disable any limits to avoid HTTP 413 for large image uploads
    client_max_body_size 0;

    # required to avoid HTTP 411: see Issue #1486 (https://github.com/moby/moby/issues/1486)
    chunked_transfer_encoding on;

    location /v2/ {
      # Do not allow connections from docker 1.5 and earlier
      # docker pre-1.6.0 did not properly set the user agent on ping, catch "Go *" user agents
      if ($http_user_agent ~ "^(docker\/1\.(3|4|5(?!\.[0-9]-dev))|Go ).*$" ) {
	return 404;
      }

      # To add basic authentication to v2 use auth_basic setting.
      #auth_basic "Registry realm";
      #auth_basic_user_file /etc/nginx/conf.d/nginx.htpasswd;

      ## If $docker_distribution_api_version is empty, the header is not added.
      ## See the map directive above where this variable is defined.
      add_header 'Docker-Distribution-Api-Version' $docker_distribution_api_version always;

      proxy_pass                          http://registry;
      proxy_set_header  Host              $http_host;   # required for docker client's sake
      proxy_set_header  X-Real-IP         $remote_addr; # pass on real client's IP
      proxy_set_header  X-Forwarded-For   $proxy_add_x_forwarded_for;
      proxy_set_header  X-Forwarded-Proto $scheme;
      proxy_read_timeout                  900;
    }
  }
~

VOLUME /etc/nginx

FROM registry:2 AS server

RUN <<~
  apk add curl
~

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:5000/v2/
