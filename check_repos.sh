#! /bin/sh -euo pipefail

fail() {
    echo $@
    echo "Usage: $0 root_dir (check_precommit_hook | check_hooks_gitleak)"
    exit 2
}

[ $# = 2 ] || fail "need two args" 
if [ ! -d $1 ]; then 
    fail "first argument must be a directory"
else
    root=$1
fi 

case $2 in 
   check_hooks_gitleak|check_precommit_hook) 
        option=$2
        :;;
   *) fail "invalid second argument";;
esac

exit_status=0

check_hooks_gitleak() {
    hooks_gitleak=$(cd $gitrepo; git config --bool hooks.gitleaks)
    if [ $hooks_gitleak = "true" ]; then
        return 0
    else
        return 1
    fi
}

check_precommit_hook() {
    echo "check_precommit_hook"
    return 0
}

find $root -name '.git' -type d -maxdepth 5 2>/dev/null | 
    while read gitrepo; do 
        echo $gitrepo
        if eval $option $gitrepo; then
            echo "OK $gitrepo"
            :
        else
            echo Fail: $gitrepo
            exit_status=1
        fi
    done

echo status $exit_status
exit $exit_status 