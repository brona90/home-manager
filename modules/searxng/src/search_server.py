#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.2.0", "httpx>=0.27.0"]
# ///
"""web-search MCP server backed by a local SearXNG instance.

Gives any Claude instance private web search — no API key, no rate limits, nothing
leaving the machine beyond the actual search queries SearXNG forwards to engines.

Config: SEARXNG_URL (default http://localhost:8888)
"""
import os
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

SEARXNG_URL = os.environ.get("SEARXNG_URL", "http://localhost:8888").rstrip("/")
mcp = FastMCP("searxng")
_http = httpx.Client(timeout=30.0, headers={"User-Agent": "claude-searxng-mcp/1.0"})


def _search(query: str, count: int, categories: str, language: str) -> list[dict]:
    r = _http.get(f"{SEARXNG_URL}/search", params={
        "q": query, "format": "json", "categories": categories, "language": language,
    })
    r.raise_for_status()
    results = r.json().get("results", [])
    out = []
    for item in results[:count]:
        out.append({"title": item.get("title"), "url": item.get("url"),
                    "content": item.get("content"), "engine": item.get("engine")})
    return out


@mcp.tool()
def web_search(query: str, count: int = 5, categories: str = "general",
               language: str = "en") -> list[dict[str, Any]]:
    """Search the web via the local SearXNG instance. Returns title/url/snippet results.

    `categories` can be e.g. general, news, science, it, images, videos (comma-separated).
    Use this for current information, documentation, or anything beyond training data.
    """
    return _search(query, count, categories, language)


@mcp.tool()
def web_news(query: str, count: int = 5, language: str = "en") -> list[dict[str, Any]]:
    """Search recent news for a query via SearXNG."""
    return _search(query, count, "news", language)


if __name__ == "__main__":
    mcp.run()
