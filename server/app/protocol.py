"""The client and server contract constants.

The protocol version changes only when a client built for the previous
version can no longer sync correctly. Error codes are stable snake_case
identifiers: clients map them to localized messages, so a code is never
renamed once released.
"""

from enum import StrEnum

PROTOCOL_VERSION = 1


class ErrorCode(StrEnum):
    database_unavailable = "database_unavailable"
    unsupported_protocol = "unsupported_protocol"
