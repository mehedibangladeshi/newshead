#!/usr/bin/env python3
"""One-off / re-runnable audit tool: dumps every raw section (slug + name)
each source's own nav exposes, bypassing the curated allowlist/denylist
each source module normally applies in discover_sections(). Used to design
(or re-audit, if a source redesigns its nav later) the app's canonical
category taxonomy and the SECTION_CATEGORY_MAP in scraper/generate_data.py.

Run manually:
    python scripts/discover_sections.py
"""
import importlib
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scraper import config

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

REPORT_PATH = os.path.join(config.PROJECT_ROOT, "docs", "section-discovery-report.md")


def discover_all_sections():
    """Returns {source_slug: [(section_slug, section_name), ...]} using each
    source's full, unfiltered nav. Skips (with a warning) any source whose
    discovery fails outright, mirroring generate_data.py's per-source
    try/except pattern."""
    results = {}
    for source_slug in config.SOURCES:
        module = importlib.import_module(f"scraper.sources.{source_slug}")
        try:
            sections = module.discover_sections(include_all=True)
        except Exception as exc:
            logger.warning("Skipping %s: could not discover sections: %s", source_slug, exc)
            continue
        results[source_slug] = sections
    return results


def render_report(results):
    """Pure formatting step: {source_slug: [(slug, name), ...]} -> markdown."""
    lines = [
        "# Section Discovery Report",
        "",
        "Every raw nav section per source, bypassing each source's curated "
        "allowlist/denylist. Regenerate with `python scripts/discover_sections.py`.",
        "",
    ]
    for source_slug, sections in results.items():
        lines.append(f"## {source_slug} ({len(sections)} sections)")
        lines.append("")
        for slug, name in sections:
            lines.append(f"- `{slug}` — {name}")
        lines.append("")
    return "\n".join(lines)


def main():
    results = discover_all_sections()
    report = render_report(results)

    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write(report)

    total = sum(len(sections) for sections in results.values())
    logger.info("Wrote %d section(s) across %d source(s) to %s", total, len(results), REPORT_PATH)
    print(report)


if __name__ == "__main__":
    main()
