#!/usr/bin/env bash
# Convert different input files to markdown using pandoc
# using `-t markdown` because it prioritizes document portabily by
# adhering to core specs, whereas `-t gfm` (Github) adds extras with
# focus on web readability

# check if a variable is given
if [ -z "$1" ]; then
    echo "Usage: to-md <input_file> or"
    echo "Usage: to-md <directory_containing_files_to_convert>"
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
        echo "No other input files are supported yet."
        exit 1
    fi
    echo "Converting all files in directory '$1'"
    for f in "$1"/*.epub; do
    pandoc "$f" -o "${f%.epub}.md" -t markdown
    done
    echo "Converted files in folder '$1' to markdown"
    exit
fi

# check if the file is an epub file
if [[ ! "$1" == *.epub ]]; then
    echo "Error: File must be an .epub file"
    exit 1
fi

# convert
pandoc "$1" -o "${1%.epub}.md" -t markdown
echo "Converted '$1' to markdown"
