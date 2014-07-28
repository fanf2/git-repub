#!/bin/sh
#
# git-repub: make rebasing branches publishable
#
# Written by Tony Finch <fanf2@cam.ac.uk> <dot@dotat.at>
# at the University of Cambridge Computing Service.
# You may do anything with this. It has no warranty.
# <http://creativecommons.org/publicdomain/zero/1.0/>

set -e

usage() {
	cat 1>&2 <<EOF
usage: git repub [options] [--rw <branch>] [--ff <branch>]

    --rw <branch>    the rebasing branch to be published
    --ff <branch>    the history-preserving publication branch

If one of --rw or --ff is missing, the other defaults to the current
branch. If both are missing, the current branch's config is checked
to find its corresponding rebasing or repub branch.

    --dry-run    do not make any commits
    --force      do not check that the --ff branch looks right
    --init       same as --config --start
    --config     remember the --rw and --ff branches
    --start      create the --ff branch

EOF
	exit 1
}

# branches
rw=""
ff=""

# alternative modes
unpub=false
status=false

# safety checks
check_rw=false
check_ff=true
force=false

# setup modes
start=false
config=false

# everything except for the changes
doit=true

while [ $# != 0 ]
do
	case "$1" in
	--rw)
		rw=$2
		shift 2
		;;
	--ff)
		ff=$2
		shift 2
		;;
	--unpub)
		unpub=true
		check_rw=true
		shift
		;;
	--status)
		check_rw=true
		check_ff=true
		status=true
		shift
		;;
	--force)
		force=true
		shift
		;;
	--init)
		start=true
		config=true
		shift
		;;
	--start)
		start=true
		shift
		;;
	--config)
		config=true
		shift
		;;
	--config-only)
		config=true
		doit=false
		shift
		;;
	--dry-run)
		doit=false
		shift
		;;
	*)
		usage
		;;
	esac
done

if $force
then
	check_rw=false
	check_ff=false
fi

head="$(git rev-parse --abbrev-ref HEAD)"

# see if the current branch is configured for repub
# only one of these should be set for any branch
if [ -z "$rw" ] && [ -z "$ff" ]
then
	rw="$(git config "branch.$head.repub-rw" || :)"
	ff="$(git config "branch.$head.repub-ff" || :)"
fi

if [ -z "$rw" ] && [ -z "$ff" ]
then	echo 1>&2 "git-repub: could not find repub config for branch $head"
	exit 1
fi

# missing branch name defaults to current branch
if [ -z "$rw" ]
then rw="$head"
fi
if [ -z "$ff" ]
then ff="$head"
fi

# create initial commit on ff branch
if $start && ! $unpub
then
	empty_tree="$(git hash-object -t tree /dev/null)"
	message="git repub --rw $rw --ff $ff --start"
	if $doit
	then	commit="$(echo "$message" | git commit-tree $empty_tree)"
		git branch $ff $commit
	fi
	echo $message
	check_ff=false
fi

if $start && $unpub
then
	check_rw=false
else
	rw_hash="$(git rev-parse "$rw")"
fi

ff_hash="$(git rev-parse "$ff")"
ff_head="$(git rev-parse --symbolic-full-name "$ff")"

# To check a repub-ff branch looks plausible we just verify that the tree
# at its head matches the tree at its second parent. (We could perhaps also
# check the commit message?)

if $check_ff
then
	ff_tree="$(git rev-parse $ff_hash^{tree} 2>&1)"
	ff2hash="$(git rev-parse $ff_hash^2      2>&1)"
	ff2tree="$(git rev-parse $ff2hash^{tree} 2>&1)"
	if [ "$ff_tree" != "$ff2tree" ]
	then	echo 1>&2 "git-repub: $ff does not look like a repub-ff branch"
		$status || exit 1
	fi
	if [ "$rw_hash" = "$ff2hash" ]
	then	echo 1>&2 "git-repub: $rw and $ff are up-to-date"
		$status || exit 1
	fi
fi

# To unpub we will reset the repub-rw branch to repub-ff^2, i.e. the latest
# published version. This is safe if repub-rw is a second parent of one of
# the direct ancestors of repub-ff, i.e. repub-rw == repub-ff~N^2 for some
# N. To check this we verify that the repub-rw..repub-ff ancestry path is
# non-empty and it is a prefix of the first-parent history of the repub-ff
# branch.

# We check there is a newline between $ancestry_path and the rest of
# $ff_parentage. This cannot match if $ancestry_path is empty because
# $ff_parentage does not start with a newline.
$nl='
'

if $check_rw
then
	ff_parentage="$(git rev-list --first-parent $ff_hash)"
	ancestry_path="$(git rev-list --ancestry-path $rw_hash..$ff_hash)"
	case $ff_parentage in
	($ancestry_path$nl*)
		: ok ;;
	(*)	echo 1>&2 "git-repub: unsafe to update $rw because it has diverged from $ff"
		exit 1
	esac
fi

if $status
then exit
fi

if $config
then
	git config "branch.$rw.repub-ff" "$ff"
	git config "branch.$ff.repub-rw" "$rw"
fi

if $unpub
then
	if ! git diff-index --quiet HEAD
	then	echo 1>&2 "git-repub: please commit your changes before switching branches"
		exit 1
	fi
	message="git repub --unpub --ff $ff --rw $rw"
	git update-ref -m "$message" "refs/heads/$rw" "$ff_hash^2"
	git read-tree --reset -u -v "$ff_hash^2"
	echo "Updated branch '$rw' to $ff^2"
	git update-ref -m "$message" HEAD "refs/heads/$rw"
	exit 0
fi

message="git repub --rw $rw --ff $ff \
# rev $(git describe --tags "$rw" 2>/dev/null ||
	git name-rev --name-only "$rw_hash")"
if $doit
then	commit="$(echo "$message" |
		 git commit-tree -p $ff_hash -p $rw_hash $rw_hash^{tree})"
	git update-ref -m "$message" $ff_head $commit $ff_hash
fi
echo $message

exit 0
