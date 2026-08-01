# LLM-SQL Review UI

저장소 최상단 `workspace`의 JSON과 SQL 산출물을 사람이 읽기 쉬운 화면으로 보여주는
로컬 전용 검토 도구입니다. 모델 간 교환 JSON은 수정하지 않으며 화면에서도 승인이나
파일 변경을 수행하지 않습니다.

## 시작

저장소 루트에서 실행합니다.

```bash
python3 ReviewUI/server.py
```

브라우저에서 `http://127.0.0.1:8765`를 엽니다. 다른 workspace를 보려면:

```bash
python3 ReviewUI/server.py --workspace /absolute/path/to/workspace
```

기본 bind 주소는 `127.0.0.1`입니다. 회사 SQL과 DB metadata가 다른 장비에 노출되지
않도록 특별한 접근 제어 없이 `--host 0.0.0.0`으로 바꾸지 마세요.

## 화면 구성

- 현재 실행 및 `workspace/archive/**`의 보존 실행 목록
- 쿼리별 SUCCESS/PARTIAL/FAILED 상태와 최종 gate
- 원본 SQL과 튜닝 SQL의 줄 단위 비교
- writer의 `why`, `risk`, `check`
- DeepSeek/Nemotron critic의 차단 사유, 의미 위험, 수정 제안
- Oracle parse/plan/snapshot/sample 검증 JSON
- benchmark 개선율과 원본/튜닝 metric
- writer와 critic에 실제 주입된 `db_context`
- 문제 확인을 위한 원본 JSON 탭

화면은 5초마다 현재 스크롤 위치를 보존하면서 자동 갱신됩니다. 외부 CDN,
JavaScript package, 필수 추가 Python package를 사용하지 않으므로 폐쇄망에서도
Python 3만으로 실행할 수 있습니다. `prometheus-client`가 설치되어 있으면 `/metrics`
관측값도 제공하고, 설치되지 않았으면 리뷰 화면만 정상 동작합니다.

## 보안 경계

- 읽을 수 있는 범위는 `--workspace` 아래로 제한합니다.
- API는 실행 목록과 그 목록에 실제 존재하는 query 이름만 허용합니다.
- 절대 경로와 상위 디렉터리 이동을 차단합니다.
- 5 MiB보다 큰 단일 산출물은 화면에 로드하지 않습니다.
- 쓰기/승인 API는 제공하지 않습니다.

사람의 승인 기록이 필요해지면 기존 산출물을 덮어쓰지 말고 별도
`workspace/approvals/<query>.json` 계약과 인증 정책을 먼저 정의해야 합니다.

## 테스트

```bash
python3 -m unittest discover -s ReviewUI/tests -v
```
