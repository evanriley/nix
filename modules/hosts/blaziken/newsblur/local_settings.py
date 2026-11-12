import os

DEBUG = False
DEBUG_ASSETS = False
DEBUG_QUERIES = False
SENTRY_DSN = ""

NEWSBLUR_URL = "https://news.pis.fyi"
SESSION_COOKIE_DOMAIN = "news.pis.fyi"
CSRF_COOKIE_SECURE = True
IMAGES_URL = "https://news.pis.fyi/imageproxy"
PUSH_DOMAIN = "news.pis.fyi"
ENABLE_PUSH = True

DATABASES = {
    "default": {
        "ENGINE": "django_prometheus.db.backends.postgresql",
        "NAME": "newsblur",
        "USER": "newsblur",
        "HOST": "/run/postgresql",
    },
}

EMAIL_BACKEND = "django.core.mail.backends.smtp.EmailBackend"
EMAIL_HOST = "127.0.0.1"
EMAIL_PORT = 25
EMAIL_USE_TLS = False
HELLO_EMAIL = "news@pis.fyi"
SERVER_EMAIL = "news@pis.fyi"
DEFAULT_FROM_EMAIL = "NewsBlur <news@pis.fyi>"
ADMINS = (("Evan Riley", "evan@evanriley.com"),)

AUTO_PREMIUM_NEW_USERS = True
AUTO_ENABLE_NEW_USERS = True
SOCIAL_APPLE_CLIENT_IDS = []

BACKED_BY_AWS = {
    "pages_on_node": True,
    "pages_on_s3": False,
    "icons_on_s3": False,
}
S3_AVATARS_BUCKET_NAME = "newsblur-avatars"
S3_LISTEN_BUCKET_NAME = "newsblur-listen"

SECRET_KEY = os.environ["NEWSBLUR_SECRET_KEY"]
IMAGES_SECRET_KEY = os.environ["IMAGEPROXY_SIGNATUREKEY"]

with open("/run/secrets/anthropic-key") as _anthropic_key_file:
    ANTHROPIC_API_KEY = _anthropic_key_file.read().strip()

for _name in (
    "OPENAI_API_KEY",
    "ELEVENLABS_API_KEY",
    "YOUTUBE_API_KEY",
    "REDDIT_CLIENT_ID",
    "REDDIT_CLIENT_SECRET",
    "S3_ACCESS_KEY",
    "S3_SECRET",
    "S3_ENDPOINT_URL",
    "S3_AVATARS_URL",
    "GOOGLE_GEMINI_API_KEY",
    "XAI_GROK_API_KEY",
    "SCRAPINGBEE_API_KEY",
):
    if os.environ.get(_name):
        globals()[_name] = os.environ[_name]
