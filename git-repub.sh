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

EOF
	exit 1
}

check=true
start=false
config=false
doit=true
onto=""
from=""

while [ $# != 0 ]
do
	case "$1" in
	--force)
		check=false
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

if [ -z "$from" ] && [ -z "$onto" ]
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

from_hash="$(git rev-parse "$from")"
onto_hash="$(git rev-parse "$onto")"
onto_head="$(git rev-parse --symbolic-full-name "$onto")"

if $start
then
	empty_tree="$(git hash-object -t tree /dev/null)"
	message="Create $onto for repub from $from"
	if $doit
	then	commit="$(echo "$msg" | git commit-tree $empty_tree)"
		git branch $onto $commit
	fi
	echo $message
	check=false
fi

if $check
then
	onto_tree="$(git rev-parse $onto_hash^{tree} 2>&1)"
	onto2tree="$(git rev-parse $onto_hash^2^{tree} 2>&1)"
	if [ "$onto_tree" != "$onto2tree" ]
	then	echo 1>&2 "$onto does not look like a repub-onto branch"
		exit 1
	fi
fi

if $config
then
	git config "branch.$from.repub-onto" "$onto"
	git config "branch.$onto.repub-from" "$from"
fi

message="Update $onto to $(git describe --tags "$from")"
if $doit
then	commit="$(echo "$msg" | git commit-tree -p $onto_hash -p $from_hash $from_hash^{tree})"
	git update-ref -m "$msg" $onto_head $commit $onto_hash
fi
echo $message

exit 0
