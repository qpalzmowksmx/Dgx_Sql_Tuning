# DeepSeekV4FlashDgxSpark WithUI

This variant starts model API and Open WebUI.

- Direct start: `docker compose up -d`
- Safe model switch/start: `./start.sh`
- Direct stop: `docker compose down`
- Safe stop: `./stop.sh`
- Status: `docker compose --env-file ../config.env ps`
- API: `http://127.0.0.1:8080/v1/models`
- Web UI: `http://127.0.0.1:3000`

The model configuration is shared from `../config.env`.
