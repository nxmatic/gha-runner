variable "buildx-local-cache-dir" {
  default = "buildx-cache/from"
}

target "cache-from" {
  cache-from = [ "type=local,mode=max,src=${buildx-local-cache-dir}" ]
}
