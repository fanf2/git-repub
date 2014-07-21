#!/bin/sh
#
# git-repub: make rebasing branches publishable
#
# Written by Tony Finch <fanf2@cam.ac.uk> <dot@dotat.at>
# at the University of Cambridge Computing Service.
# You may do anything with this. It has no warranty.
# <http://creativecommons.org/publicdomain/zero/1.0/>

# TODO
#
# an unpub action that creates a branch pointing to repub-branch^2
# or updates it - need to check the update is safe
# $ git merge-base --is-ancestor repub-from repub-onto

set -e

usage() {
	cat 1>&2 <<EOF
usage: git repub [options] [--from <branch>] [--onto <branch>]

    --from <branch>    the rebasing branch to be published
    --onto <branch>    the history-preserving publication branch

If one of --from or --onto is missing, the other defaults to the
current branch. If both are missing, the current branch's config is
checked to find its corresponding repub-from or repub-onto branch.

    --dry-run    do not make any commits
    --force      do not check that the --onto branch looks right
    --init       same as --config --start
    --config     remember the --from and --onto branches
    --start      create the --onto branch

For more information see http://fanf.livejournal.com/128282.html

EOF
	exit 1
}

check_onto=true
check_only=false
start=false
config=false
unpub=false
doit=true
onto=""
from=""

while [ $# != 0 ]
do
	case "$1" in
	--force)
		check_onto=false
		shift
		;;
	--start)
		start=true
		shift
		;;
	--check)
		check_only=true
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
	--init)
		start=true
		config=true
		shift
		;;
	--from)
		from=$2
		shift 2
		;;
	--onto)
		onto=$2
		shift 2
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

head="$(git rev-parse --abbrev-ref HEAD)"

# see if the current branch is configured for repub
# only one of these should be set for any branch
if [ -z "$from" ] && [ -z "$onto" ]
then
	from="$(git config "branch.$head.repub-from" || :)"
	onto="$(git config "branch.$head.repub-onto" || :)"
fi

if ! $check_only && [ -z "$from" ] && [ -z "$onto" ]
then	echo 1>&2 "error: could not find repub config for branch $head"
	exit 1
fi

# missing branch name defaults to current branch
if [ -z "$from" ]
then from="$head"
fi
if [ -z "$onto" ]
then onto="$head"
fi

if $start
then
	empty_tree="$(git hash-object -t tree /dev/null)"
	message="Create $onto for repub from $from"
	if $doit
	then	commit="$(echo "$message" | git commit-tree $empty_tree)"
		git branch $onto $commit
	fi
	echo $message
	check_onto=false
fi

from_hash="$(git rev-parse "$from")"
onto_hash="$(git rev-parse "$onto")"
onto_head="$(git rev-parse --symbolic-full-name "$onto")"

# To check a repub-onto branch looks plausible we just verify that the tree
# at its head matches the tree at its second parent. (We could perhaps also
# check the commit message?)

if $check_onto
then
	onto_tree="$(git rev-parse $onto_hash^{tree} 2>&1)"
	onto2hash="$(git rev-parse $onto_hash^2      2>&1)"
	onto2tree="$(git rev-parse $onto2hash^{tree} 2>&1)"
	if [ "$onto_tree" != "$onto2tree" ]
	then	echo 1>&2 "$onto does not look like a repub-onto branch"
		exit 1
	fi
	if $check_only
	then	exit 0
	fi
	if [ "$from_hash" = "$onto2hash" ]
	then	echo 1>&2 "$from has already been merged onto $onto"
		exit 1
	fi
fi

# To unpub we reset the repub-from branch to repub-onto^2, i.e. the latest
# published version. This is safe if repub-from is a second parent of one
# of the direct ancestors of repub-onto, i.e. repub-from == repub-onto~N^2
# for some N. To check this we verify that the repub-from..repub-onto
# ancestry path is non-empty and it is a prefix of the first-parent history
# of the repub-onto branch.

# We check there is a newline between $ancestry_path and the rest of
# $onto_parentage. This cannot match if $ancestry_path is empty because
# $onto_parentage does not start with a newline.
$nl='
'

if $check_from
then
	onto_parentage="$(git rev-list --first-parent $onto_hash)"
	ancestry_path="$(git rev-list --ancestry-path $from_hash..$onto_hash)"
	case $onto_parentage in
	($ancestry_path$nl*)
		: ok ;;
	(*)	echo 1>&2 "it is not safe to update $from"
		echo 1>&2 "$onto is not a descendent of $from"
		exit 1
	esac
fi

if $config
then
	git config "branch.$from.repub-onto" "$onto"
	git config "branch.$onto.repub-from" "$from"
fi

message="git-repub --from $from --onto $onto \
# rev $(git describe --tags "$from" 2>/dev/null ||
	git name-rev --name-only "$from_hash")"
if $doit
then	commit="$(echo "$message" |
		 git commit-tree -p $onto_hash -p $from_hash $from_hash^{tree})"
	git update-ref -m "$message" $onto_head $commit $onto_hash
fi
echo $message

exit 0
