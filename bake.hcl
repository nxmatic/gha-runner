# Output manifests in docker by default using the latest tag and amd64 arch.

# Overriden by the pipeline, merging bake.d/*/github.hcl for pushing
# the manifests to github and building for amd64 and arm64.

variable "include-latest-tag" {
  default = "true"
}

variable "base-tags" {
  default = "0.0.0-dev"
}

function "get_tags" {
  params = [include_latest, base_tags]
  result = include_latest == "true" ? concat(split(",", base_tags), ["latest"]) : split(",", base_tags)
}

variable "tags" {
  default = get_tags(include-latest-tag, base-tags)
}

variable "branch" {
  default = "develop"
}

variable "builder-cache-buster" {
  default = "0"
}

target "common" {
  dockerfile = "Dockerfile"
}  

target "systemd" {
  context = "systemd"
  inherits = [ "common" ]
  name = "systemd-${stage}"
  matrix = {
    stage = [ "builder", "docker2mdns", "docker2mdns-debug", "avahi2dns" ]
  }
  tags = formatlist("${DOCKER_UPSTREAM}/systemd-${stage}:%s", tags)
  target = "${stage}"
  args = {
    TAG = "${tags[0]}"
    BRANCH = "${branch}"
    BUILDER_CACHE_BUSTER = "${builder-cache-buster}"
  }
}

target "novnc" {
  context = "novnc"
  inherits = [ "common" ]
  name = "novnc-${stage}"
  matrix = {
    stage = [ "novnc", "wine", "zen" ]
  }
  tags = formatlist("${DOCKER_UPSTREAM}/novnc-${stage}:%s", tags)
  target = "${stage}"
  args = {
    TAG = "${tags[0]}"
    BRANCH = "${branch}"
  }
}

target "gha" {
  context = "gha"
  inherits = [ "common" ]
  name = "gha-${stage}"
  matrix = {
    stage = [ "kms", "proxy-dns", "runner" ]
#    stage = [ "kms", "proxy-mdns", "proxy-mdns-builder", "proxy-dns", "runner" ]
  }
  secret = ["type=env,id=GITHUB_TOKEN"]
  tags = formatlist("${DOCKER_UPSTREAM}/gha-${stage}:%s", tags)
  target = "${stage}"
}

group "containers-gha" {
  targets = [ "gha-runner", "gha-kms" ]
}

group "containers-systemd" {
  targets = [ "systemd-avahi2dns", "systemd-docker2mdns" ]
}

group "containers-novnc" {
  targets = [ "novnc-novnc", "novnc-zen" ]
}

group "containers" {
  targets = [ "containers-systemd", "containers-novnc", "containers-gha" ]
}

group "default" {
  targets = [ "containers" ]
}
