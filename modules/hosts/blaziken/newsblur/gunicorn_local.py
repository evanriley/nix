from config.gunicorn_conf import *  # noqa: F403

bind = "127.0.0.1:8000"
workers = 3
reload = False
