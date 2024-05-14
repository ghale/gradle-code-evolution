#!/bin/bash

if [ ! -d gradle ]; then
    git clone https://github.com/gradle/gradle.git
fi

git="git -C gradle"

# Function to compare versions
version_greater() {
    # Remove 'v' from tags and compare as integers
    [ "$(echo "$1" | tr -d 'v' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')" -gt "$(echo "$2" | tr -d 'v' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')" ]
}

versions=""
base_tag="v7.0.0"
for tag in $($git tag -l 'v[0-9]*\.[0-9]*\.0'); do
    if version_greater $tag $base_tag; then
        versions="$versions $tag"
    fi
done

#versions="$base_tag $versions release master"
versions="master"

process_version() {
    echo "Processing: $1"
    $git checkout $1
    echo "Commits: $($git rev-list --count $1)"
}

for version in $versions; do
    process_version $version
done
