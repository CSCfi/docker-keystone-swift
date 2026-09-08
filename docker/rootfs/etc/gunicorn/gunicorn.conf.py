# gunicorn config file for the keystone WSGI service (Reference:
# https://gunicorn.org/reference/settings/).
#
# IMPORTANT: gunicorn must be invoked here with NO CLI arguments at all (not even
# --bind or the app spec) -- see docker/rootfs/etc/s6-overlay/s6-rc.d/keystone/run
# and the "Prepare" RUN block in the Dockerfile, both of which `cd` into this
# directory so gunicorn auto-discovers this file.
#
# Why: keystone's own keystone/server/__init__.py:configure() calls oslo.config's
# CONF(project='keystone', ...) without passing args=[], so oslo.config defaults to
# parsing sys.argv[1:] itself. If gunicorn is given CLI flags (e.g. `gunicorn --bind
# 0.0.0.0:5000 keystone.wsgi.api:application`), those flags are still sitting in
# sys.argv when gunicorn imports the app -- and keystone's own config parser then
# rejects them as unrecognized *keystone* options. Because argparse's default `prog`
# is derived from sys.argv[0] (the gunicorn binary), that error is confusingly
# displayed as "gunicorn: error: unrecognized arguments: ...", even though it's
# keystone's parser raising it, not gunicorn's. keystone-wsgi-public (removed in
# keystone 2025.2) never hit this because it wasn't a generic WSGI server importing
# an arbitrary app with its own CLI flags still in sys.argv.
#
# Keeping the app spec and bind address here (rather than on gunicorn's CLI) means
# gunicorn can be invoked as plain `gunicorn` -- sys.argv[1:] stays empty, so
# keystone's CONF() call has nothing left over to choke on.

bind = "0.0.0.0:5000"
wsgi_app = "keystone.wsgi.api:application"

# Disable gunicorn's runtime control socket (added in 25.1.0, used by the
# `gunicornc` CLI -- unused here). Without this it defaults to
# $HOME/.gunicorn/gunicorn.ctl, but the keystone service is started via
# `s6-setuidgid keystone gunicorn` (see .../s6-rc.d/keystone/run), which
# changes uid/gid but not $HOME -- so it's left as /root (inherited from the
# root-owned s6 supervision tree) and the unprivileged `keystone` user can't
# mkdir there. Harmless (logged as a non-fatal "Control server error" after
# the worker's already booted), but disabling it avoids the noise.
control_socket_disable = True
