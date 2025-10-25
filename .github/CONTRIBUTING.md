# Contributing to justscripts

Thank you for your interest in contributing to justscripts! This guide will help you add new scripts to the repository.

## Adding a New Script

### 1. Create Your Script

Create a new Python file in the `scripts/` directory with the following structure:

```python
#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "your-package>=1.0.0",
#   "another-package",
# ]
# ///
"""
Brief description of what your script does.
"""

import sys
# Your imports here


def main():
    # Your code here
    pass


if __name__ == "__main__":
    main()
```

### 2. Script Guidelines

- **Shebang**: Always start with `#!/usr/bin/env -S uv run`
- **Metadata**: Include the `# /// script` block with dependencies
- **Documentation**: Add a docstring explaining what the script does
- **Error Handling**: Handle errors gracefully and provide helpful error messages
- **Usage Info**: If the script takes arguments, print usage information when run incorrectly
- **Exit Codes**: Use appropriate exit codes (0 for success, non-zero for errors)

### 3. Make It Executable

```bash
chmod +x scripts/your_script.py
```

### 4. Test Your Script

Test your script locally with uv:

```bash
uv run scripts/your_script.py [arguments]
```

### 5. Update Documentation

Add your script to the "Available Scripts" section in `README.md`:

```markdown
- **your_script.py**: Brief description of what it does (list key dependencies)
```

### 6. (Optional) Add a Justfile Recipe

If your script would benefit from a dedicated recipe, add it to the `justfile`:

```just
# Description of what the recipe does
# Usage: just recipe-name <args>
recipe-name ARG:
    uv run scripts/your_script.py {{ARG}}
```

### 7. Submit a Pull Request

1. Fork the repository
2. Create a new branch for your script
3. Commit your changes
4. Push to your fork
5. Open a pull request

## Script Ideas

Here are some ideas for useful scripts:

- File manipulation utilities
- Data processing scripts
- API interaction tools
- System administration helpers
- Development workflow automation
- Text processing utilities
- Media file converters
- Web scraping tools
- Data visualization scripts
- Configuration generators

## Best Practices

1. **Keep it simple**: Each script should do one thing well
2. **Self-contained**: All dependencies should be in the script metadata
3. **Clear output**: Provide informative output and error messages
4. **Help text**: Include usage information for scripts with arguments
5. **Cross-platform**: Consider compatibility across different operating systems
6. **Security**: Don't include sensitive data or credentials in scripts
7. **Performance**: Optimize for reasonable performance but prioritize clarity

## Questions?

If you have questions or need help, please open an issue on GitHub.
