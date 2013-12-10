#!/bin/sh

set -e

usage() {
	echo 1>&2 'usage: git-repub <publish> <rebasing>'
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
	from="$(git config "branch.$head.repub-from")"
	onto="$(git config "branch.$head.repub-onto")"
fi

if [ -z "$from" ] && [ -z "$onto" ]
then usage
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
