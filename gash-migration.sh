#!/bin/sh
#
# This script is a modified version of the blog post of
# http://www.geekaholic.org/2010/02/splitting-git-repo.html
#
# All directories beneath the given directory repository ($1 - moved 
# to $1.tmp), are shifted into an own git repository in a subdirectory 
# ($1).
#
# In the following we assume server-core as the given repository, this
# is to make the examples easier. We are showing just one package (abs)
# with only one file (PKGBUILD). The .git directory is shown explicitly
# to show, which directories are real git-repositories.
# The given repository (server-core) is called super-repository, the 
# sub-directories are packages in our case. Packages are then transferred
# to own repositories after the migration.
#
# Directory structure before migration (server):
# /srv/git/server-core.git/.git
# /srv/git/server-core.git/.gitignore
# /srv/git/server-core.git/abs
# /srv/git/server-core.git/abs/PKGBUILD
# ...
#
# Directory structure after migration (server):
# /srv/git/server-core.git/.git
# /srv/git/server-core.git/.gitignore
# /srv/git/server-core.git/.gashlist
#
# /srv/git/server-core/abs
# /srv/git/server-core/abs/.git
# /srv/git/server-core/abs/.gitignore
# /srv/git/server-core/abs/PKGBUILD
#
# The migration is done on a client, the original repository (server-core)
# is copied to a temporary directory (server-core.tmp) to allow adoptions 
# on the structure of the super-repository.
#
# The given repository is then used as the new super-repository. 
# This super-repository will just contain a special file (.gashlist) 
# which contains a list of all sub-repositories. All the history in this
# repository is still left in the repository. This could be moved in a 
# separate step.
# The new base directory and the sub-repositories needs to get created 
# on the server.
#

# The given paramater is the used repository
repo=$1
# Server, where git-directories are located on
SERVER=hydrogen.archserver.org
# Directory on the server, where git-repositories are located
GIT_SERVER_BASE_DIR=/srv/git

# check if the given repository name is not empty
if [ "$repo" == "" ]; then
  echo "Please provide a valid repository name (you provided an empty name)"
	exit 1
fi

# check if the given repository name is a directory
if [ ! -d "$repo" ]; then
	echo "Please provide a valid repository name (the given name is not a directory)"
	exit 1
fi

# check if the given repository name is really a repository (git)
if [ ! -d "$repo/.git" ]; then
	echo "Please provide a valid repository name (the given name is not a valid git repo)"
	exit 1
fi

# store base directory
base_dir=$PWD
repo_dir=$base_dir/$repo
echo $base_dir

# local movement of the directory to temporary location
tmp_repo_name=$repo.tmp
cp $repo $tmp_repo_name -rf

# fetch latest changes of the given repository
cd $base_dir/$tmp_repo_name
git pull
cd $base_dir

# clean repository
cd $repo
git rm * -rf

# determine all sub-repositories in the super-repository
cd $tmp_repo_name

# create the new project directory (eg. server-core, explicitly without 
# .git-suffix) on the server, to store new sub-repositories.
ssh $SERVER 'mkdir $GIT_SERVER_BASE_DIR/$repo'

# this should be more error prone, concerning spaces in names
# and stuff like this.
for subrepo in * ; do
  # check if the subrepo is a directory, if not, continue
  if [ ! -d "$subrepo" ]; then
		echo "given sub-repository ($subrepo) is not a directory, cannot go further"
		continue
	fi

  # clone repository into sub-repository
	echo "base_dir/subrepo: $base_dir/$subrepo"
	cd $base_dir
	git clone --no-hardlinks $tmp_repo_name $repo_dir/$subrepo

  # cleanup sub-repository
	cd $subrepo
	echo $PWD
	git filter-branch --subdirectory-filter $subrepo HEAD -- -- all
	git reset --hard
  git gc --aggressive
	git prune

  exit 1

  # the new git repository needs to be created on the live system
  # create directory
	ssh $SERVER 'mkdir $GIT_SERVER_BASE_DIR/$repo/$subrepo.git'
	# create repository
	ssh $SERVER 'cd $GIT_SERVER_BASE_DIR/$repo/$subrepo.git && git --bare init'

	# remove remote from sub-repository and add new remote on remote
	# server
  git remote rm origin
	git remote add origin git@git.archserver.org:$repo/$subrepo
	git push origin master

  # add sub-repository to .gitignore and .gashlist in 
  # super-repository
	cd $repo_dir
	echo $subrepo >> .gitignore
	echo $subrepo >> .gashlist

	exit 1
done
