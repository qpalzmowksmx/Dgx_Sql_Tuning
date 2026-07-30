from enum import Enum, auto

class PipelineState(Enum):
    # SQL 수집
    COLLECT_SQL = auto()

    # 메타데이터 수집
    COLLECT_METADATA = auto()

    # RAG 생성
    BUILD_RAG = auto()

    # 1차 분석
    ANALYZE = auto()

    # 튜닝
    TUNE = auto()

    # 성능측정
    BENCHMARK = auto()

    # 비판 모델 검토
    CRITIQUE = auto()

    # Oracle Parse/Explain/샘플 검증
    VALIDATE_ORACLE = auto()

    # 결과검증
    VERIFY = auto()

    # 재분석
    REANALYZE = auto()

    # 사용자 승인 대기
    WAIT_USER = auto()

    # 완료
    SUCCESS = auto()

    # 실패
    FAILED = auto()
