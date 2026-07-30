from enum import Enum, auto


class QueryStatus(Enum):
    WAITING = auto()

    ANALYZING = auto()

    TUNING = auto()

    BENCHMARKING = auto()

    CRITIQUING = auto()

    VALIDATING = auto()

    VERIFYING = auto()

    RETRY = auto()

    SUCCESS = auto()

    FAILED = auto()

    def __str__(self):
        return self.name
