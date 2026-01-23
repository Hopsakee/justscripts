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

# Convert a Markdown file to PDF
# Usage: just md2pdf <file.md>
md2pdf FILE:
  {{home_dir()}}/justscripts/scripts/md2pdf.sh "{{FILE}}"

# Convert a epub file to PDF
# Usage: just epub2pdf <file.epub>
# Usage: just epub2pdf <directory>
epub2pdf ARG:
  {{home_dir()}}/justscripts/scripts/epub2pdf.sh "{{ARG}}"
