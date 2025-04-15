variable "jgitver_used_version" {
  default = "@jgitver.used_version@"
}

variable "jgitver_git_sha1_full" {
  default = "@jgitver.git_sha1_full@"
}

variable "jgitver_commit_timestamp" {
  default = "@jgitver.commit_timestamp@"
}

variable "jgitver_head_committer_name" {
  default = "@jgitver.head_committer_name@"
}

variable "jgitver_head_committer_email" {
 default = "@jgitver.head_commiter_email@"
}

variable "jgitver_dirty" {
  default = "@jgitver.dirty@"
}

target "labels" {
  args = {
    "org.opencontainers.image.version" = "${jgitver_used_version}"
    "org.opencontainers.image.revision" = "${jgitver_git_sha1_full}"
    "org.opencontainers.image.created" = "${jgitver_commit_timestamp}"
    "com.nuxeo.nos.committer" = "${jgitver_head_committer_name}"
    "com.nuxeo.nos.committer.email" = "${jgitver_head_committer_email}"
    "com.nuxeo.nos.dirty" = "${jgitver_dirty}"
  }
}

target "common" {
  inherits = [ "labels" ]
}
