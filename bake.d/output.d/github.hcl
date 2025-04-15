variable "GITHUB_ACTOR" {
  default = "nuxeo"
}

variable "GITHUB_REPOSITORY" {
  default = "nuxeo/nos"
}

variable "GITHUB_UPSTREAM" {
  default = "ghrc.io/${GITHUB_ACTOR}"
}

target common {
  args = {
    "org.opencontainers.image.url" = "https://github.com/${GITHUB_REPOSITORY}"
    "org.opencontainers.image.source" = "https://github.com/${GITHUB_REPOSITORY}"
  }
  driver = "docker-container"
  cache-from = [ "type=gha" ]
  cache-to = [ "type=gha,mode=max" ]
  output = [ "type=registry" ]
}
