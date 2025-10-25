#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "requests",
# ]
# ///
"""
Fetch and display GitHub repository information.
Demonstrates using requests library to interact with APIs.
"""

import sys
import requests


def main():
    if len(sys.argv) < 2:
        print("Usage: uv run scripts/github_repo_info.py <owner/repo>")
        print("\nExample: uv run scripts/github_repo_info.py python/cpython")
        sys.exit(1)
    
    repo_path = sys.argv[1]
    
    if '/' not in repo_path:
        print("Error: Repository must be in format 'owner/repo'")
        sys.exit(1)
    
    api_url = f"https://api.github.com/repos/{repo_path}"
    
    try:
        response = requests.get(api_url, timeout=10)
        response.raise_for_status()
        repo_data = response.json()
        
        print(f"\nGitHub Repository: {repo_data['full_name']}")
        print(f"  Description: {repo_data.get('description', 'No description')}")
        print(f"  Stars: {repo_data['stargazers_count']}")
        print(f"  Forks: {repo_data['forks_count']}")
        print(f"  Language: {repo_data.get('language', 'Not specified')}")
        print(f"  Open Issues: {repo_data['open_issues_count']}")
        print(f"  Created: {repo_data['created_at']}")
        print(f"  Updated: {repo_data['updated_at']}")
        print(f"  URL: {repo_data['html_url']}")
        
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            print(f"Error: Repository '{repo_path}' not found")
        else:
            print(f"HTTP Error: {e}")
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"Error fetching repository data: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
