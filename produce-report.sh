#!/bin/zsh
setopt null_glob

output_file="${1:-report.tsv}"
base_date="2023-06-01"
platform=$(uname)

if [ ! -d gradle ]; then
    echo "Cloning repository and checking out master"
    git clone -q https://github.com/gradle/gradle.git
    git -C gradle checkout -q master
else
    echo "Resetting repository to current master"
    git -C gradle fetch --all -q
    git -C gradle reset --hard -q origin/master
    git -C gradle clean -qfdx
fi

git_cmd() {
    git -C gradle "$@"
}

getCommitFromOneWeekBefore() {
    commit=$1
    if [[ "$platform" == "Darwin" ]]; then
        ONE_WEEK_BEFORE=$(date -j -f "%Y-%m-%d" -v-1w "+%Y-%m-%d" $(git_cmd log -1 --format="%cd" --date=short ${commit}))
    else
        ONE_WEEK_BEFORE=$(date -d "$(git_cmd log -1 --format="%cd" --date=short ${commit}) - 1 week" "+%Y-%m-%d")
    fi
    git_cmd log -1 --merges --since="$base_date" --before="$ONE_WEEK_BEFORE" --format="%H"
}

echo "Finding weekly commits going back to $base_date"
next_commit=$(git_cmd log -1 --format="%H")
all_commits=($next_commit)
while [[ "$next_commit" != "" ]] ; do
    next_commit=$(getCommitFromOneWeekBefore $next_commit)
    all_commits+=($next_commit)
done

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

count_files() {
  local target=$1

  # Run cloc and extract the total lines of code from its output
  total_files=$(find $target -type f | wc -l)
  echo "$total_files"
}

process_version() {
    commit=$1

    # commit_count=$(git_cmd rev-list --count $tag)
    # printf "Commits\t%s\t%d\n" commit $commit_count >> $output_file

    git_cmd checkout -q $commit
    git_cmd clean -qfdx

    # Find all subprojects

    all_subproject_dirs=($(get_child_directories gradle/subprojects 1))

    date=$(git_cmd show -s --format="%cs" $commit)
    echo "Processing: $commit from $date with ${#all_subproject_dirs} subprojects"

    for subproject_dir in $all_subproject_dirs; do
        if [ ! -d "$subproject_dir/src/main" ]; then
            continue
        fi
        subproject=":$(basename $subproject_dir)"
        total_prod_files=$(count_files "$subproject_dir/src/main")

        if [ ! -d "$subproject_dir/src/test" ]; then
            total_test_files=0
        else
            total_test_files=$(count_files "$subproject_dir/src/test")
        fi

        if [ ! -d "$subproject_dir/src/integTest" ]; then
            total_integTest_files=0
        else
            total_integTest_files=$(count_files "$subproject_dir/src/integTest")
        fi

        total_files=$((total_prod_files + total_test_files + total_integTest_files))

        printf "%s\t%s\t%d\n" "$subproject" "$date" "$total_files" >>$output_file
    done
}

printf "Subproject\tDate\tFiles\n" >$output_file

reversed_commits=()
for (( i=${#all_commits[@]} ; i>=0 ; i-- )); do
    reversed_commits+=(${all_commits[$i]})
done

for commit in ${reversed_commits}; do
    #git_cmd log -1 ${commit}
    process_version $commit
done
