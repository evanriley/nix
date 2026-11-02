import email
import email.policy
import email.utils
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

EX_NOUSER = 67
EX_TEMPFAIL = 75
TIMEOUT_SECONDS = 30
HOST_HEADER = "haproxy"
RECEIVE_URL = os.environ.get(
    "NEWSBLUR_RECEIVE_URL", "http://127.0.0.1/newsletters/receive"
)


def body_text(message, kind):
    part = message.get_body(preferencelist=(kind,))
    if part is None:
        return None
    try:
        return part.get_content()
    except (LookupError, UnicodeError):
        payload = part.get_payload(decode=True) or b""
        return payload.decode("utf-8", errors="replace")


def epoch_seconds(message):
    date = message["Date"]
    if date is None:
        return None
    try:
        return int(email.utils.parsedate_to_datetime(str(date)).timestamp())
    except (TypeError, ValueError, IndexError):
        return None


def form_fields(message, recipient, sender):
    fields = {
        "recipient": recipient,
        "from": str(message["From"] or sender),
        "subject": str(message["Subject"] or ""),
        "message-headers": json.dumps(
            [[name, str(value)] for name, value in message.items()]
        ),
    }
    optional = {
        "body-plain": body_text(message, "plain"),
        "body-html": body_text(message, "html"),
        "signature": message["Message-Id"],
        "timestamp": epoch_seconds(message),
    }
    fields.update(
        {key: str(value) for key, value in optional.items() if value}
    )
    return fields


def deliver(fields):
    request = urllib.request.Request(
        RECEIVE_URL,
        data=urllib.parse.urlencode(fields).encode("ascii"),
        headers={"Host": HOST_HEADER},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS):
            return 0
    except urllib.error.HTTPError as error:
        reason = f"{RECEIVE_URL} answered {error.code} {error.reason}"
        if 400 <= error.code < 500:
            print(
                f"{reason}; the recipient is unknown or the message was"
                " rejected, bouncing",
                file=sys.stderr,
            )
            return EX_NOUSER
        print(f"{reason}; deferring for retry", file=sys.stderr)
        return EX_TEMPFAIL
    except OSError as error:
        print(
            f"Failed to reach {RECEIVE_URL}: {error}; expected NewsBlur"
            " to be running, deferring for retry",
            file=sys.stderr,
        )
        return EX_TEMPFAIL


def main(argv):
    if len(argv) not in (2, 3):
        print(
            "Usage: newsblur-newsletter RECIPIENT [SENDER] < message",
            file=sys.stderr,
        )
        return EX_TEMPFAIL
    recipient = argv[1]
    sender = argv[2] if len(argv) == 3 else ""
    try:
        message = email.message_from_binary_file(
            sys.stdin.buffer, policy=email.policy.default
        )
        fields = form_fields(message, recipient, sender)
    except Exception as error:
        print(
            f"Failed to parse the message for {recipient}: {error!r};"
            " deferring for retry",
            file=sys.stderr,
        )
        return EX_TEMPFAIL
    return deliver(fields)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
