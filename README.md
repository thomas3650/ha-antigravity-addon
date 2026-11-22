# HA Antigravity add-on

A Home Assistant add-on that runs the Google Antigravity CLI (`agy`) with Remote
Control as an always-on assistant. See
[the add-on documentation](ha-antigravity/DOCS.md).

## Development

    brew install bats-core shellcheck jq
    bats tests/
    shellcheck -x -s bash ha-antigravity/rootfs/usr/local/lib/ha-antigravity/*.sh tests/container.sh \
      $(ls ha-antigravity/rootfs/usr/local/bin/* | grep -v -e '/ha-antigravity-jobs-mcp$' -e '/ha-antigravity-docs-mcp$')

With Docker available:

    docker build -t ha-antigravity:dev ha-antigravity
    tests/container.sh ha-antigravity:dev
