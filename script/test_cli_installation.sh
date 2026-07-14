#!/bin/sh

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <SSD_Remover executable> [temporary bin directory]" >&2
    exit 64
fi

executable=$1
bin_directory=${2:-"${TMPDIR:-/tmp}/ssd-remover-cli-install-$$"}
command_path="$bin_directory/ssd-remover"
created_directory=0
created_link=0

if [ ! -x "$executable" ]; then
    echo "CLI executable is missing or not executable: $executable" >&2
    exit 1
fi

if [ ! -d "$bin_directory" ]; then
    mkdir -p "$bin_directory"
    created_directory=1
fi

if [ -e "$command_path" ] || [ -L "$command_path" ]; then
    echo "Refusing to replace an existing command during the smoke test: $command_path" >&2
    if [ "$created_directory" -eq 1 ]; then
        rmdir "$bin_directory" 2>/dev/null || true
    fi
    exit 1
fi

cleanup() {
    if [ "$created_link" -eq 1 ]; then
        rm -f "$command_path"
    fi
    if [ "$created_directory" -eq 1 ]; then
        rmdir "$bin_directory" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM

ln -s "$executable" "$command_path"
created_link=1

help_output=$($command_path --help)
version_output=$($command_path --version)

printf '%s\n' "$help_output" | grep -F "Usage: SSD_Remover" >/dev/null
printf '%s\n' "$version_output" | grep -F "SSD_Remover" >/dev/null

echo "CLI installation smoke test passed: $command_path"
