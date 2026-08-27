class AuthenticationError(Exception):
    """Base error for authentication flows that must not disclose sensitive details."""


class InvalidQuestion(ValueError):
    pass


class RateLimitExceeded(Exception):
    def __init__(self, retry_after: int) -> None:
        self.retry_after = retry_after


class InvalidCredentials(AuthenticationError):
    pass


class InvalidRefreshToken(AuthenticationError):
    pass


class RefreshTokenReuseDetected(AuthenticationError):
    pass
