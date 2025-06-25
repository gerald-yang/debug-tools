#!/bin/bash

set -e

# Function to download and build a package
build_package() {
    local source_pkg=$1
    local version=$2
    local series=$3
    
    echo "Processing source package: $source_pkg (version: $version)"
    
    # Create build directory in current folder
    build_dir="builds/${source_pkg}_${version}"
    if [ -d "$build_dir" ]; then
        echo "Build directory already exists: $build_dir"
        return 0
    fi
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    # Download source package
    local download_fail="false"
    echo "Downloading source package..."
    apt-get source "$source_pkg=$version" || {
        download_fail="true"
    }

    if [ "$download_fail" = "true" ]; then
        cd - > /dev/null
        echo "Download failed $source_pkg=$version" >> fail.list
	echo "Download failed $source_pkg=$version"
	return 0
    fi

    dsc_file=$(find . -maxdepth 1 -type f -name "*.dsc")
    
    # Build the package
    local build_fail="false"
    echo "Building package... ${dsc_file}"
    sbuild -d "$series" "${dsc_file}" || {
        build_fail="true"
    }

    cd - > /dev/null
    
    if [ "$build_fail" = "true" ]; then
        echo "Build failed $source_pkg=$version" >> fail.list
        echo "Build failed $source_pkg=$version"
    else
        echo "Successfully built $source_pkg=$version"
    fi
    date
    
    echo "----------------------------------------"
}

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <package list file> <ubuntu series>"
    exit 1
fi

# Create builds directory if it doesn't exist
mkdir -p builds

# Read the package list and process each package
while IFS= read -r line; do
    if [[ $line =~ ^Package:[[:space:]]*(.+)$ ]]; then
        package="${BASH_REMATCH[1]}"
        # Read the next line for version
        read -r version_line
        if [[ $version_line =~ ^Version:[[:space:]]*(.+)$ ]]; then
            version="${BASH_REMATCH[1]}"
            build_package "$package" "$version" "$2"
        fi
    fi
done < "$1"

