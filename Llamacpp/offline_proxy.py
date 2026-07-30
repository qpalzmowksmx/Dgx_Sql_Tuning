#!/usr/bin/env python3
"""Localhost-only TCP proxy for an isolated model container."""

from __future__ import annotations

import argparse
import socket
import threading


def copy_stream(source: socket.socket, destination: socket.socket) -> None:
    try:
        while chunk := source.recv(1024 * 1024):
            destination.sendall(chunk)
    except (ConnectionError, OSError):
        pass
    finally:
        try:
            destination.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def proxy_connection(
    client: socket.socket, target_host: str, target_port: int
) -> None:
    try:
        upstream = socket.create_connection((target_host, target_port), timeout=30)
        upstream.settimeout(None)
        client.settimeout(None)
    except OSError:
        client.close()
        return

    left = threading.Thread(target=copy_stream, args=(client, upstream), daemon=True)
    right = threading.Thread(target=copy_stream, args=(upstream, client), daemon=True)
    left.start()
    right.start()
    left.join()
    right.join()
    client.close()
    upstream.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, required=True)
    parser.add_argument("--target-host", required=True)
    parser.add_argument("--target-port", type=int, required=True)
    args = parser.parse_args()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((args.listen_host, args.listen_port))
        server.listen(128)
        while True:
            client, _ = server.accept()
            threading.Thread(
                target=proxy_connection,
                args=(client, args.target_host, args.target_port),
                daemon=True,
            ).start()


if __name__ == "__main__":
    main()
