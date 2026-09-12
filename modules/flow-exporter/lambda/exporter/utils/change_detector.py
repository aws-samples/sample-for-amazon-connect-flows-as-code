# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Change detector utility for Amazon Connect resource exports.

Detects changes between exported content and existing S3 objects
to prevent unnecessary writes and version history noise.
"""

import logging

logger = logging.getLogger(__name__)


class ChangeDetector:
    """Detect content changes against existing S3 objects."""

    def __init__(self, s3_client, bucket, prefix=""):
        self._s3 = s3_client
        self._bucket = bucket

        # `prefix` is accepted for call-compatibility but deliberately NOT applied
        # to keys. Callers hand us the key produced by BaseExporter._s3_key(),
        # which already includes the prefix, and _write_to_s3() writes that key
        # verbatim. Prepending it again read s3://bucket/source/source/... which
        # never exists, so has_changed() always returned True and every save
        # rewrote an identical object -- growing version history and defeating the
        # skip this class exists to perform.
        self._prefix = prefix

    def get_existing_content(self, key):
        """Retrieve existing S3 object content, or None if not found."""
        try:
            resp = self._s3.get_object(Bucket=self._bucket, Key=key)
            return resp["Body"].read().decode("utf-8")
        except self._s3.exceptions.NoSuchKey:
            logger.debug("Object does not exist: s3://%s/%s", self._bucket, key)
            return None
        except Exception as e:
            error_code = getattr(e, "response", {}).get("Error", {}).get("Code", "")
            if error_code == "NoSuchKey":
                return None
            logger.warning("Error retrieving s3://%s/%s: %s", self._bucket, key, e)
            return None

    def has_changed(self, key, content):
        """Return True if content differs from existing S3 object or object doesn't exist."""
        existing = self.get_existing_content(key)
        if existing is None:
            logger.info("No existing content for s3://%s/%s - marking as changed", self._bucket, key)
            return True
        changed = content != existing
        if changed:
            logger.info("Content changed for s3://%s/%s - write required", self._bucket, key)
        else:
            logger.info("Content unchanged for s3://%s/%s - skipping write", self._bucket, key)
        return changed
