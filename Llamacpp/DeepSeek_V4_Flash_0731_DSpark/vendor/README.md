# Pinned ds4 source

Run `../prepare_online.sh --source-only` on an internet-connected machine. It
creates `vendor/ds4-src` at the immutable antirez/ds4 commit pinned in
`config.env`.

`vendor/ds4-src` is intentionally ignored by Git. Copy the whole
`DeepSeek_V4_Flash_0731_DSpark` directory to the closed network so Docker can
build from this local source without contacting GitHub.
