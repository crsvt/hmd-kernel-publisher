#!/usr/bin/env bash
set -euo pipefail

# --- Script Config ---
GITHUB_ORG="HMD-OSS-Archive"
PROFILE_REPO_NAME=".github"
PROFILE_REPO_URL="https://github.com/${GITHUB_ORG}/${PROFILE_REPO_NAME}.git"
README_PATH="profile/README.md"
TMP_DIR="./dashboard_repo"

# --- Validation ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: Missing required tool: '$1'." >&2; exit 1; }; }
need git; need gh

if [ -z "${1-}" ]; then
  echo "Usage: $0 <github_token>" >&2
  exit 1
fi
GH_TOKEN="$1"

# --- Auth ---
echo "$GH_TOKEN" | gh auth login --with-token
gh auth setup-git

# --- Clone Profile Repo ---
echo "-> Cloning the profile repository..."
rm -rf "$TMP_DIR"
git clone "$PROFILE_REPO_URL" "$TMP_DIR"
cd "$TMP_DIR"

# --- Build README Content ---
echo "-> Building new README content..."
{
  # --- START: Enhanced Disclaimer ---
  echo "# HMD/Nokia Kernel Source Archive"
  echo ""
  echo "> **Disclaimer: This is an Unofficial Community Archive**"
  echo ">"
  echo "> This organization is an independent, community-driven effort to archive kernel source code for HMD/Nokia devices. **It is not affiliated with, endorsed by, or sponsored by HMD Global or Nokia.**"
  echo ">"
  echo "> The source code is provided **\"as-is\"** without warranty of any kind. All code is subject to the licenses included within the archives (typically GPLv2). **You are solely responsible for ensuring your use of the code complies with these licenses.** The maintainers of this archive are not responsible for any misuse."
  echo ""
  echo "---"
  # --- END: Enhanced Disclaimer ---
  echo ""
  echo "## How to Use This Archive"
  echo ""
  echo "Each device has its own dedicated repository. The history of the main branch in each repository reflects the latest available kernel source."
  echo ""
  echo "### Finding a Specific Version"
  echo ""
  echo "Every official kernel source release is tied to a unique **Git tag**. To find the source code for a specific firmware version (e.g., \`NE1_00WW_4_14F\`):"
  echo ""
  echo "1.  Navigate to the device's repository."
  echo "2.  Click on the \"Releases\" or \"Tags\" section."
  echo "3.  You can download the source as a \`.zip\` or \`.tar.gz\` file for that specific tag, or check out the tag directly using Git."
  echo ""
  echo "### Understanding the Dashboard"
  echo ""
  echo "The table below provides a summary of all archived devices."
  echo ""
  echo "-   **Latest Kernel Version**: Shows the most recent version successfully imported."
  echo "    -   A warning icon (**⚠️**) indicates that the *latest* scheduled import for that device failed (e.g., the download link was broken or the archive was invalid), but a previous version is available."
  echo "    -   \`*Import Failed*\` means the automation was never able to import a valid kernel for that device."
  echo ""
  echo "---"
  echo ""
  echo "## Device Kernel Repositories"
  echo ""
  # Table Header
  echo "| Device Name | Latest Kernel Version | Last Updated | Repository Link |"
  echo "|-------------|-----------------------|--------------|-----------------|"

  # Fetch repo data and generate table rows
  gh repo list "$GITHUB_ORG" --limit 1000 --json name,description,pushedAt,url --jq '.[] | select(.name | startswith("android_kernel_"))' | while read -r line; do
    REPO_NAME=$(echo "$line" | jq -r '.name')
    REPO_URL=$(echo "$line" | jq -r '.url')
    DEVICE_NAME=$(echo "$line" | jq -r '.description' | sed 's/Kernel source for //')
    LAST_UPDATED=$(echo "$line" | jq -r '.pushedAt' | sed 's/T.*$//')

    ALL_TAGS_JSON=$(gh api "repos/${GITHUB_ORG}/${REPO_NAME}/tags" --paginate)
    ABSOLUTE_LATEST_TAG=$(echo "$ALL_TAGS_JSON" | jq -r '.[0].name // ""')
    LATEST_GOOD_TAG_BY_NAME=$(echo "$ALL_TAGS_JSON" | jq -r '[.[] | .name | select(contains("MISSING") | not) | select(contains("CORRUPTED") | not)][0] // ""')

    VERSION_CELL=""
    IS_LATEST_TAG_BAD=false

    # *** NEW BACKWARD-COMPATIBILITY LOGIC ***
    if [ -n "$ABSOLUTE_LATEST_TAG" ]; then
        # Check if the latest tag is bad based on the NEW naming convention
        if [[ "$ABSOLUTE_LATEST_TAG" == *"-MISSING"* || "$ABSOLUTE_LATEST_TAG" == *"-CORRUPTED"* ]]; then
            IS_LATEST_TAG_BAD=true
        else
            # If the name looks fine, check for the OLD failure style by inspecting the commit message.
            # This handles repositories created with the old, flawed script.
            COMMIT_SHA=$(echo "$ALL_TAGS_JSON" | jq -r '.[0].commit.sha // ""')
            if [ -n "$COMMIT_SHA" ]; then
                COMMIT_MESSAGE=$(gh api "repos/${GITHUB_ORG}/${REPO_NAME}/commits/${COMMIT_SHA}" --jq '.commit.message' 2>/dev/null || echo "")
                if [[ "$COMMIT_MESSAGE" == *"download failed"* || "$COMMIT_MESSAGE" == *"corrupted archive"* || "$COMMIT_MESSAGE" == *"invalid content"* ]]; then
                    IS_LATEST_TAG_BAD=true
                fi
            fi
        fi
    fi

    if [ -z "$ABSOLUTE_LATEST_TAG" ]; then
        VERSION_CELL="*pending*"
    elif [ "$IS_LATEST_TAG_BAD" = true ]; then
        if [ -n "$LATEST_GOOD_TAG_BY_NAME" ] && [ "$LATEST_GOOD_TAG_BY_NAME" != "$ABSOLUTE_LATEST_TAG" ]; then
             # A previous good version exists
            VERSION_CELL="\`${LATEST_GOOD_TAG_BY_NAME}\` (⚠️ Latest Failed)"
        else
            # No good versions exist at all
            VERSION_CELL="*Import Failed*"
        fi
    else
        # The latest tag is a good one
        VERSION_CELL="\`${ABSOLUTE_LATEST_TAG}\`"
    fi
    # *** END OF NEW LOGIC ***

    echo "| **${DEVICE_NAME}** | ${VERSION_CELL} | ${LAST_UPDATED} | [${REPO_NAME}](${REPO_URL}) |"
  done
} > "$README_PATH"

echo "-> Generated README:"
cat "$README_PATH"

# --- Commit and Push ---
git config --global user.name "GitHub Actions Bot"
git config --global user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git diff --quiet "$README_PATH"; then
  echo "-> No changes to the dashboard. Exiting."
else
  echo "-> Changes detected. Committing and pushing..."
  git add "$README_PATH"
  git commit -m "docs: Update device dashboard [skip ci]"
  git push
  echo "-> Dashboard updated successfully!"
fi
