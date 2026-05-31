# justfile for running self-contained Python scripts with uv
# See https://just.systems/ for more information about justfiles

# Default recipe - shows available commands
default:
  @just --list

# Run the hello world script
hello:
  uv run '{{home_dir()}}/justscripts/scripts/hello_world.py'

# Run the image info script with an image path
# Usage: just image-info <path_to_image>
image-info IMAGE_PATH:
  uv run '{{home_dir()}}/justscripts/scripts/image_info.py' "{{IMAGE_PATH}}"

# Get GitHub repository information
# Usage: just github-info <owner/repo>
github-info REPO:
  uv run '{{home_dir()}}/justscripts/scripts/github_repo_info.py' {{REPO}}

# List all available scripts
list-scripts:
  @echo "Available scripts:"
  @ls -1 {{home_dir()}}/justscripts/scripts/*.py | sed 's|scripts/||' | sed 's|\.py$||'

# Run any script by name (without .py extension)
# Usage: just run <script_name> [args...]
run SCRIPT *ARGS:
  uv run '{{home_dir()}}/justscripts/scripts/{{SCRIPT}}.py' "{{ARGS}}"

# Resize PNG images by a given factor
resize-images factor *files:
  cd {{invocation_directory_native()}} && uv run '{{home_dir()}}/justscripts/scripts/resize_images.py' {{factor}} {{files}}

# Convert any source (Markdown, EPUB, HTML file, or http(s) URL) to PDF with a selectable layout.
# Also accepts a directory: batch-converts every supported file inside it.
# (Recipe name is "to-pdf" because just recipe names cannot start with a digit; the script is 2pdf.sh.)
# Usage: just to-pdf <file|url|dir> [layout]    (default: boox-delight)
# Available layouts: boox-delight (default), boox, a4-work, a4-personal
to-pdf SOURCE LAYOUT="boox-delight":
  {{home_dir()}}/justscripts/scripts/2pdf.sh "{{SOURCE}}" "{{LAYOUT}}"

# Extract a PDF to <name>_text.md via pymupdf4llm (Tier 1)
# Usage: just pdf-extract <file.pdf> [--force] [--dry-run]
pdf-extract PDF *FLAGS:
  uv run '{{home_dir()}}/justscripts/scripts/pdf_extract.py' "{{PDF}}" {{FLAGS}}
