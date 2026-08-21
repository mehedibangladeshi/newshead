#!/usr/bin/env python3
"""CLI entry point: python scripts/generate.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from scraper.generate_data import main

if __name__ == "__main__":
    main()
