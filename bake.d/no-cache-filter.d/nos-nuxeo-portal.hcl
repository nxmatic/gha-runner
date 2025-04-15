variable "cache-timestamp" {
  default = "0"
}

target "nos-nuxeo-portal" {
  args = {
    "zips-cache-timestamp" = "1"
  }
}
