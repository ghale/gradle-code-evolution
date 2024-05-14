#!/bin/bash

output_file="${1:-report.tsv}"

if [ ! -d gradle ]; then
    git clone -q https://github.com/gradle/gradle.git
else
    git -C gradle fetch --all -q
    git -C gradle reset --hard -q
    git -C gradle clean -qfdx
fi

git="git -C gradle"

# Function to compare versions
version_greater() {
    # Remove 'v' from tags and compare as integers
    [ "$(echo "$1" | tr -d 'v' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')" -gt "$(echo "$2" | tr -d 'v' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')" ]
}

versions=""
base_tag="v8.0.0"
for tag in $($git tag -l 'v[0-9]*\.[0-9]*\.0'); do
    if version_greater $tag $base_tag; then
        versions="$versions $tag"
    fi
done

versions="$base_tag $versions release master"
#versions="master"

get_child_directories() {
    local root_dir=$1
    local depth=$2

    if [ -d "$root_dir" ]; then
        find "$root_dir" -mindepth "$depth" -maxdepth "$depth" -type d
    else
        echo ""
    fi
}

is_in_tags() {
    local tag=$1
    local tags_list=$2

    for t in $tags_list; do
        if [[ "$t" == "$tag" ]]; then
            return 0
        fi
    done
    return 1
}

count_lines_of_code() {
  local directory=$1

  # Run cloc and extract the total lines of code from its output
  total_lines=$(cloc --json "$directory" | jq '.SUM.code')
  echo "$total_lines"
}

process_version() {
    tag=$1
    versions=$2

    # commit_count=$($git rev-list --count $tag)
    # printf "Commits\t%s\t%d\n" $version $commit_count >> $output_file

    $git checkout -q $tag
    $git clean -qfdx

    if [[ "$tag" == v* ]]; then
        version=${tag#v}
    else
        gradle_version=$(cat gradle/version.txt)
        if [[ "$gradle_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            if is_in_tags "v$gradle_version.0" "$versions"; then
                echo "Skipping tag '$tag' with version '$gradle_version' as it has already been processed"
                return
            fi
            version="$gradle_version.0 ($tag)"
        else
            echo "Skipping tag '$tag' with version '$gradle_version' as it points to a patch release"
            return
        fi
    fi

    echo "Processing: $version"

    # Find all subprojects

    old_subprojects_dirs=$(get_child_directories gradle/subprojects 1)
    platform_dirs=$(get_child_directories gradle/platforms 2)
    testing_dirs=$(get_child_directories gradle/testing 1)

    subproject_dirs="$old_subprojects_dirs $platform_dirs $testing_dirs"

    for subproject_dir in $subproject_dirs; do
        subproject=":$(basename $subproject_dir)"
        if [ ! -d "$subproject_dir/src/main" ]; then
            continue
        fi
        total_lines=$(count_lines_of_code "$subproject_dir/src/main")
        printf "%s\t%s\t%d\n" "$subproject" "$version" "$total_lines" >>$output_file
    done
}

printf "Subproject\tVersion\tLOC\n" >$output_file

for version in $versions; do
    process_version $version $versions
done
