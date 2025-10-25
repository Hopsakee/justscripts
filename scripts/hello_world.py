#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# ///
"""
Simple hello world script.
Demonstrates a basic self-contained Python script that can be run with uv.
"""


def main():
    print("Hello, World!")
    print("This script was run using uv!")


if __name__ == "__main__":
    main()
