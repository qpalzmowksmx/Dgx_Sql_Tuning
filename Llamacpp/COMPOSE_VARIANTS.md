# 모델별 UI/비-UI Docker 구성

각 모델 디렉터리에는 두 실행 구성이 있습니다.

- `WithUI`: 모델 API와 Open WebUI를 함께 실행합니다.
- `WithoutUI`: 모델 API만 실행하며 Open WebUI 컨테이너와 3000번 포트를 사용하지 않습니다.

두 구성은 `.env` 연결을 통해 모델 디렉터리의 `config.env`를 자동으로 공유합니다. 따라서 각 변형 디렉터리에서 일반 Compose 명령을 바로 사용할 수 있습니다.

```bash
docker compose up -d
docker compose down
```

다른 모델이나 UI 변형에서 안전하게 전환할 때는 잔류 스택을 먼저 정리하는 `start.sh`, `stop.sh`를 사용합니다.

```bash
cd Qwen/WithoutUI
./start.sh
./stop.sh
```

Python 관제 프로그램에서는 `WithoutUI/start.sh`를 실행하거나 해당 디렉터리의 Compose 파일을 직접 사용할 수 있습니다.

```python
import subprocess

subprocess.run(["./start.sh"], cwd="Qwen/WithoutUI", check=True)
```

모든 모델 API가 호스트의 `127.0.0.1:8080`을 사용하므로 한 번에 한 모델만 실행해야 합니다. 기존 Compose 파일이 변경되면 다음 명령으로 두 변형을 동기화합니다.

```bash
./sync-compose-variants.sh
```
