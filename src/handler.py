"""Inquiry service Lambda: validate -> store in DynamoDB -> notify owner via SES.

Built by Dilan Patel for CS 79C.
"""
import json
import os
import re
import time
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])
SES = boto3.client("sesv2")
OWNER_EMAIL = os.environ["OWNER_EMAIL"]
SENDER_EMAIL = os.environ["SENDER_EMAIL"]

MAX_BODY_BYTES = 10_000
RETENTION_SECONDS = 90 * 24 * 3600
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
UUID_RE = re.compile(r"^[0-9a-fA-F-]{36}$")


def respond(status, payload):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(payload),
    }


def clean_line(value):
    """Single-line text: strip CR/LF so user input can never inject email headers."""
    return re.sub(r"[\r\n]+", " ", str(value or "")).strip()


def validate(data):
    name = clean_line(data.get("name"))
    email = clean_line(data.get("email"))
    phone = clean_line(data.get("phone"))
    message = str(data.get("message") or "").strip()

    if not 1 <= len(name) <= 100:
        return None, "Name is required (max 100 characters)."
    if not EMAIL_RE.match(email) or len(email) > 254:
        return None, "A valid email address is required."
    if phone and not re.fullmatch(r"[0-9+()\-\s.]{7,20}", phone):
        return None, "Phone number looks invalid."
    if not 1 <= len(message) <= 2000:
        return None, "Message is required (max 2000 characters)."
    return {"name": name, "email": email, "phone": phone, "message": message}, None


def lambda_handler(event, context):
    raw = event.get("body") or ""
    if len(raw.encode("utf-8")) > MAX_BODY_BYTES:
        return respond(413, {"error": "Request too large."})
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return respond(400, {"error": "Body must be JSON."})

    # Honeypot: real users never see this field. Bots fill it in. Pretend success.
    if data.get("website"):
        return respond(200, {"status": "received"})

    fields, error = validate(data)
    if error:
        return respond(400, {"error": error})

    # The browser sends a request id, so a double-click or retry cannot create
    # (or email) the same inquiry twice.
    request_id = str(data.get("requestId") or "")
    inquiry_id = request_id if UUID_RE.match(request_id) else str(uuid.uuid4())

    item = {
        "inquiryId": inquiry_id,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "expiresAt": int(time.time()) + RETENTION_SECONDS,
        "status": "NEW",
        **{k: v for k, v in fields.items() if v},
    }
    try:
        TABLE.put_item(Item=item, ConditionExpression="attribute_not_exists(inquiryId)")
    except ClientError as err:
        if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return respond(200, {"status": "received", "duplicate": True})
        print(f"dynamodb error inquiry={inquiry_id}: {err}")
        return respond(500, {"error": "Could not save your inquiry. Please try again."})

    status = "NOTIFIED"
    try:
        SES.send_email(
            FromEmailAddress=SENDER_EMAIL,
            Destination={"ToAddresses": [OWNER_EMAIL]},
            ReplyToAddresses=[fields["email"]],
            Content={
                "Simple": {
                    "Subject": {"Data": f"New inquiry from {fields['name']}"},
                    "Body": {
                        "Text": {
                            "Data": (
                                f"Name: {fields['name']}\n"
                                f"Email: {fields['email']}\n"
                                f"Phone: {fields['phone'] or '-'}\n\n"
                                f"{fields['message']}\n\n"
                                f"-- Inquiry {inquiry_id}\n"
                                "-- Sent by Dilan Patel's inquiry service (CS 79C)\n"
                            )
                        }
                    },
                }
            },
        )
    except ClientError as err:
        # The inquiry is already saved, so nothing is lost. Flag it for follow-up.
        print(f"ses error inquiry={inquiry_id}: {err}")
        status = "NOTIFY_FAILED"

    TABLE.update_item(
        Key={"inquiryId": inquiry_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": status},
    )
    print(f"inquiry={inquiry_id} status={status}")
    return respond(200, {"status": "received"})
