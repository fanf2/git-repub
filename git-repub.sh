#!/bin/sh

check=true
case "$1" in
--first)
	check=false
	shift
esac

case $# in
2) : ok ;;
*)	echo 1>&2 'usage: git-publish <publish> <rebasing>'
	exit 1
	;;
esac

p="$1"
r="$2"
if ! p_hash="$(git rev-parse "$p")"
then exit $?; fi
if ! r_hash="$(git rev-parse "$r")"
then exit $?; fi
if ! p_head="$(git rev-parse --symbolic-full-name "$p")"
then exit $?; fi

if $check
then
	p_tree="$(git rev-parse $p_hash^{tree} 2>&1)"
	p2tree="$(git rev-parse $p_hash^2^{tree} 2>&1)"
	if [ "$p_tree" != "$p2tree" ]
	then	echo 1>&2 "$p is not a publication branch"
		exit 1
	fi
fi

msg="Update $p to $(git describe --tags "$r")"

commit="$(echo "$msg" | git commit-tree -p $p_hash -p $r_hash $r_hash^{tree})"
git update-ref -m "$msg" $p_head $commit $p_hash
echo $msg
