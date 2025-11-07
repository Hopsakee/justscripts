#!/usr/bin/env bash
# Convert markdown to PDF using pandoc

pandoc "$1" -o "${1%.md}.pdf"
