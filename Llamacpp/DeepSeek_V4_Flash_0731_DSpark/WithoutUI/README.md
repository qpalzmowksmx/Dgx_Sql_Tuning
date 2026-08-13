# DSpark API without Open WebUI

`AutorunEnum_Final/run_files.sh` uses this launcher for its DeepSeek final
rewrite stage.

```bash
./start.sh
./health_check.sh
./stop.sh
```

It starts only the local OpenAI-compatible API on `127.0.0.1:8080`. Greedy
requests use DSpark; sampled requests fall back to target-only decoding.
