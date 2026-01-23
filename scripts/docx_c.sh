#!/usr/bin/env bash
# Convert docx to PDF (default) or markdown using pandoc

# Default output format
OUTPUT_FORMAT="pdf"

while [[ $# -gt 0 ]]; do
  case $1 in
    -f)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      INPUT="$1"
      shift 1

if [ -z
      

  
