#!/usr/bin/env bash
# Convert epub to PDF using pandoc
# Using 'xelatex' enging because it supports more Unicode characters
#   than the default 'pdflatex'

SCRIPT_DIR="$(dirname "$0")"

# check if a variable is given
if [ -z "$1" ]; then
    echo "Usage: epub2pdf <epub_file> or"
    echo "Usage: epub2pdf <directory_containing_epub_files>"
    exit 1
fi

# check if the variable is a file or directory
if [[ ! ( -f "$1" || -d "$1" ) ]]; then
    echo "Error: '$1' not found"
    exit 1
fi

# check if the variable is a directory
if [ -d "$1" ]; then
    if ! compgen -G "$1/*.epub" > /dev/null; then
        echo "Error: No .epub files found in directory '$1'"
        exit 1
    fi
    echo "Converting all files in directory '$1'"
    for f in "$1"/*.epub; do
	pandoc "$f" -o "${f%.epub}.pdf" -d "$SCRIPT_DIR/epub2pdf.yaml" --pdf-engine-opt=-interaction=nonstopmode
	done
    exit
fi

# check if the file is an epub file
if [[ ! "$1" == *.epub ]]; then
    echo "Error: File must be an .epub file"
    exit 1
fi

# convert
pandoc "$1" -o "${1%.epub}.pdf" -d "$SCRIPT_DIR/epub2pdf.yaml" --pdf-engine-opt=-interaction=nonstopmode
