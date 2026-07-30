# DeepSeekV4FlashDgxSpark WithoutUI

This variant starts model API only (no Open WebUI container).

- Direct start: `docker compose up -d`
- Safe model switch/start: `./start.sh`
- Direct stop: `docker compose down`
- Safe stop: `./stop.sh`
- Status: `docker compose --env-file ../config.env ps`
- API: `http://127.0.0.1:8080/v1/models`
- Port 3000 and the Open WebUI container are not used.

The model configuration is shared from `../config.env`.
