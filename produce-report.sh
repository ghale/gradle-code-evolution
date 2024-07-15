#!/bin/zsh
setopt null_glob

output_file="${1:-report.tsv}"
base_tag="v0.7.0"

if [ ! -d gradle ]; then
    git clone -q https://github.com/gradle/gradle.git
else
    git -C gradle fetch --all -q
    git -C gradle reset --hard -q
    git -C gradle clean -qfdx
fi

git_cmd() {
    git -C gradle "$@"
}

# Function to compare versions
version_greater() {
    # Remove 'v' from tags and compare as integers
    [ "$(echo "$1" | tr -d 'v' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')" -gt "$(echo "$2" | tr -d 'v' | awk -F. '{ printf("%d%03d%03d\n", $1,$2,$3); }')" ]
}

# Function to convert a semantic version string to a sortable string
sortable_version() {
    local version=$1
    # Remove the 'v' prefix
    version=${version#v}
    # Pad each part of the version with leading zeros to ensure proper sorting
    echo $version | awk -F. '{ printf("%03d.%03d.%03d\n", $1, $2, $3); }'
}

typeset -A sorted_versions
for tag in $(git_cmd tag -l 'v[0-9]*\.[0-9]*\.0'); do
    if ! version_greater $base_tag $tag; then
        sortable=$(sortable_version $tag)
        sorted_versions[$sortable]=$tag
    fi
done

# Sort the keys of the associative array
sorted_keys=(${(On)${(k)sorted_versions}})

versions=()
for key in $sorted_keys; do
    versions=(${sorted_versions[$key]} ${versions[@]})
done

versions+=("release" "master")
#versions+="master"

get_child_directories() {
    local root_dir=$1
    local depth=$2
    local -a directories

    if [ -d "$root_dir" ]; then
        directories=($(find "$root_dir" -mindepth "$depth" -maxdepth "$depth" -type d))
    else
        directories=()
    fi

    echo "${directories[@]}"
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
  local target=$1

  # Run cloc and extract the total lines of code from its output
  total_lines=$(cloc --json "$target" | jq '.SUM.code')
  echo "$total_lines"
}

process_version() {
    tag=$1
    versions=$2

    # commit_count=$(git_cmd rev-list --count $tag)
    # printf "Commits\t%s\t%d\n" $version $commit_count >> $output_file

    git_cmd checkout -q $tag
    git_cmd clean -qfdx

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

    # Find all subprojects

    old_subprojects_dirs=($(get_child_directories gradle/subprojects 1))
    platform_dirs=($(get_child_directories gradle/platforms 2))
    testing_dirs=($(get_child_directories gradle/testing 1))

    all_subproject_dirs=(gradle ${old_subprojects_dirs[@]} ${platform_dirs[@]} ${testing_dirs[@]})

    build_logic_dirs=($(get_child_directories gradle/build-logic 1))
    build_logic_commons_dirs=($(get_child_directories gradle/build-logic-commons 1))
    build_logic_settings_dirs=($(get_child_directories gradle/build-logic-settings 1))

    all_build_logic_dirs=(gradle/buildSrc ${build_logic_dirs[@]} ${build_logic_commons_dirs[@]} ${build_logic_settings_dirs[@]})

    all_dirs=(${all_subproject_dirs[@]} ${all_build_logic_dirs[@]})

    echo "Processing: $version with ${#all_subproject_dirs} subprojects and ${#all_build_logic_dirs} build logic dirs"

    for subproject_dir in $all_subproject_dirs; do
        if [ ! -d "$subproject_dir/src/main" ]; then
            continue
        fi
        subproject=":$(basename $subproject_dir)"
        total_lines=$(count_lines_of_code "$subproject_dir/src/main")
        printf "%s\t%s\t%d\n" "$subproject" "$version" "$total_lines" >>$output_file
    done

    for build_logic_dir in $all_build_logic_dirs; do
        if [ ! -d "$build_logic_dir/src/main" ]; then
            continue
        fi
        subproject=":$(basename $build_logic_dir)"
        total_lines=$(count_lines_of_code "$build_logic_dir/src/main")
        printf "%s\t%s\t-%d\n" "$subproject" "$version" "$total_lines" >>$output_file
    done

    total_build_script_lines=0
    for dir in $all_dirs; do
        build_files=($dir/build.gradle* $dir/settings.gradle*)
        for build_file in $build_files; do
            if [ -f "$build_file" ]; then
                lines=$(count_lines_of_code "$build_file")
                (( total_build_script_lines += lines ))
            fi
        done
    done
    printf "Build scripts\t%s\t-%d\n" "$version" "$total_build_script_lines" >>$output_file
}

printf "Subproject\tVersion\tLOC\n" >$output_file

for version in $versions; do
    process_version $version $versions
done
