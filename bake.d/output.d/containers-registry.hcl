variable "GITHUB_REPOSITORY" {
  default = "nuxeo/nos"
}

variable DOCKER_UPSTREAM {
  default = "host.containers.internal:5000"
}

target common {
  args = {
    "org.opencontainers.image.url" = "http://${DOCKER_UPSTREAM}"
    "org.opencontainers.image.source" = "https://github.com/${GITHUB_REPOSITORY}"
  }
  driver = "docker-container"
  cache-from = [ "type=gha" ]
  cache-to = [ "type=gha,mode=max" ]
  output = [ "type=registry" ]
}
