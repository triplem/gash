#!/bin/sh
#
# This script is a modified version of the blog post of
# http://www.geekaholic.org/2010/02/splitting-git-repo.html
#
# All directories beneath the given directory repository ($1 - moved 
# to $1.tmp), are shifted into an own git repository in a subdirectory 
# ($1).
#

SERVER=hydrogen.archserver.org
GIT_SERVER_BASE_DIR=/srv/git

# check if the given repository name is not empty
if [ "$1" == "" ]; then
  echo "Please provide a valid repository name"
	exit 1
fi

# check if the given repository name is a directory
if [ ! -d "$1" ]; then
	echo "Please provide a valid repository name"
	exit 1
fi

# check if the given repository name is really a repository (git)
if [ ! -d "$1/.git" ]; then
	echo "Please provide a valid repository name"
	exit 1
fi

# local movement of the directory to temporary location
# the repository (e.g. server-core is moved to a temporary 
# location, e.g. server-core.tmp). The temporary location is
# used to detected all sub-projects.
# The repository is then used as the base directory for the new sub-
# repositories. The "old" repository is then used as the new super-
# repository.
# The new base directory, the sub-repositories needs to get created 
# on the server. The old repository (with .git as a suffix) is then 
# used as the new super-repository.
repo_name=$1
tmp_repo_name=$repo_name.tmp

mv $repo_name $tmp_repo_name
mkdir $repo_name

base_dir=$PWD/$repo_name

echo $base_dir

# determine all sub-repositories in the super-repository
cd $tmp_repo_name

# create the new project directory (eg. server-core, explicitly without 
# .git-suffix) on the server, to store new sub-repositories.
ssh $SERVER 'mkdir $GIT_SERVER_BASE_DIR/$1'


# this should be more error prone, concerning spaces in names
# and stuff like this.
for f in * ; do
  if [ ! -d "$f" ]; then
		echo "given sub-repository is not a directory, cannot go further"
		exit 1
	fi

	echo "base_dir/f: $base_dir/$f"
	cd $base_dir
	git clone --no-hardlinks ../$tmp_repo_name $f

	cd $f
	echo $PWD
	git filter-branch --subdirectory-filter $f HEAD -- -- all
	git reset --hard
  git gc --aggressive
	git prune

  # the new git repository needs to be created on the live system
  # create directory
	ssh $SERVER 'mkdir $GIT_SERVER_BASE_DIR/$1/$f.git'
	# create repository
	ssh $SERVER 'cd $GIT_SERVER_BASE_DIR/$1/$f.git && git --bare init'

  git remote rm origin
	git remote add origin git@git.archserver.org:$1/$f
	git push origin master

	cd $base_dir
	echo $f >> .gitignore
	echo $f >> .gashlist

	exit 1
done



