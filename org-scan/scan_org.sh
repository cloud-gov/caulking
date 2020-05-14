#!/bin/sh

CACHEDIR=${HOME}/Documents/caulking-org-scan/cache

list_repos() {
    for page in 1 2 3 4; do
    hub api /orgs/cloud-gov/repos\?per_page=100\&page=$page | 
        #jq -r '.[] | select (.archived == true ) | .name'
        jq -r '.[] | .name'
    done
}

scan() {
    config=gitleaks.toml
    if [ -r $repo.toml ]; then
        config=$repo.toml
        echo Using config: $config
    fi
    cmd='gitleaks --config=./$config --repo-path=$1'
    eval echo $cmd
    eval $cmd
}

cache(){
    local repo=$1
    git_url=git@github.com:cloud-gov/$repo.git
    if [ -d $cache_dir/$repo ] ; then

        echo ... fetching ...
        (cd $cache_dir/$repo; git fetch --all)
    else
        echo ... cloning ...
        git clone $git_url $cache_dir/$repo
    fi
}

# For finding commits to exclude, not currently used
commits() {
    cat $1 | grep -v WARN | jq '.commit' | sort | uniq >> gitleaks.toml
}

make_repo_list() {
  echo "Making repo list"
  list_repos | sort | 
    grep -v openbrokerapi |
    grep -v stratos |
    grep -v 'cg-release' | # never used by us
    grep -v 'cf-example-suitecrm' | # we haven't worked this in 4 years
    cat > repo_list
}

### MAIN

make_repo_list

cache_dir=$CACHEDIR
mkdir -p $cache_dir

today=$(date +%Y-%m-%d)
results_dir="results.${today}"
mkdir -p $results_dir

cat repo_list | while read repo; do
    echo 
    echo --- $repo ---
    echo
    cache $repo
    scan $cache_dir/$repo | tee $results_dir/$repo.out
    # add latest commmit
    git --git-dir $cache_dir/$repo/.git rev-list --max-count=1 HEAD >> $results_dir/$repo.out
done
