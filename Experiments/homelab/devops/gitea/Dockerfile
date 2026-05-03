FROM docker.gitea.com/gitea:1.26.0-rootless

COPY --chmod=755 work/entrypoint.sh /usr/local/bin/entrypoint-wrapper.sh

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint-wrapper.sh"]
