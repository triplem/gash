#!/bin/bash
# 
# Git ArchServer Helper
# Helper scripts for the work with multiple repositories and a 
# super-repository.
# The super-repository contains a list of all related repositories
# in the file .gashlist.
# This script is based on the asterisk gitall-script:
# https://code.asterisk.org/code/browse/~raw,r=01dea494b7c1ed3f006fe72e456f9ea8332d64db/astscf-gitall-integration/gitall-asterisk-scf.sh
#
exe="$(basename $0)"

function usage()
{
    cat <<EOF
usage: ${exe} [-ssh-key key-file] [GIT_COMMAND] [GIT_COMMAND_OPTIONS]

This script will startup ssh-agent (if necessary) and run a series of git
commands on all of the repos managed by gitall.

Options:
   --ssh-key   Specify the key-file to use for git. Usually fine without it.

Commands:
   pull, push, tag, status, branch, diff, submodule

   Pull will detect missing repos and clone as necessary.
   Other than pull, all commands accept normal git options.
   Push tries to be safe by running --dry-run prior to the actual push.
     Still recommend *serious* paranoia when running this command.

If no command is given, pull is run by default.
EOF
}

# a temp file for holding the output of git commands for later comparison
last_text_file=.gitall.TMP
rm -f ${last_text_file}
touch ${last_text_file}

# on exit, cat the last output and delete the temp file
trap "cat ${last_text_file}; rm -f ${last_text_file}" EXIT

# collapse multiple identical inputs into a single input
function collapse()
{
    # first line is a header; always print
    head="$(head -n 1)"
    # rest is the text.  add a line for spacing.
    new_text="$(cat && echo ' ')"

    if test "${new_text}" != "$(cat ${last_text_file})"; then
        cat ${last_text_file}
        echo "${new_text}" > ${last_text_file}
    fi
    echo "${head}"
}

gitdepot=`git config --get remote.origin.url | sed "s@asterisk-scf/integration/gitall.*@@"`
gitdepot_push=`git config --get remote.origin.pushurl | sed "s@asterisk-scf/integration/gitall.*@@"`

# tree should probably be set by menu prompts or command line args
# one day
tree=asterisk-scf

repos=( ${ cat .gashlist } )

# by default, pull
cmd=pull

while test $# -gt 0; do
    case $1 in
        tag|status|branch|diff|submodule|fetch|remote|gc|fsck|log)
            cmd=passthrough
            break
            ;;
        push)
            cmd=dry_run
            break
            ;;
        pull)
            cmd=pull
            break
            ;;
        --ssh-key)
            export ssh_key=$2
            shift 2
            ;;
        --help|help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
done

function pull()
{
    # don't need the pull argument
    shift 1

    # between cloning if child repo's aren't there, and exec'ing out to
    # git pull for this repo, passing along params is a bit difficult
    if test $# -gt 0; then
        echo "error: ${exe} pull take no params" >&2
        exit 1
    fi

    # check to see if gitall needs a pull
    {
        echo ">> Fetching gitall"
        git fetch
    } 2>&1 | collapse

    # if there is an upstream branch, and it has changes we don't
    if git rev-parse --verify @{upstream} > /dev/null 2>&1 &&
        ! test -z "$(git log ^HEAD @{upstream})"; then
        # We can't just git pull, because that would modify the running script,
        # which tends to upset bash.  So we'll exec out to the git pull, and try
        # this script again.
        #
        # DONT_PULL_GITALL is a recursion guard, in case of git weirdness.
        if test ${DONT_PULL_GITALL-no} = no; then
            echo ">> Updating gitall"
            exec bash -c "git pull && DONT_PULL_GITALL=yes $0"
        else
            cat <<EOF >&2

Cowardly refusing to pull gitall repo and re-run $0.
Run git pull and try again.
EOF
            exit 1
        fi
    fi

    if [ -d pjproject ] && [ ! -d pjproject/.git ]; then
        echo " "
        echo "---------"
        echo "Previous versions of this build tree required you to download and"
        echo "unpack pjproject into a subdirectory so it could be built along"
	echo "with the other components. This version will pull pjproject from"
	echo "a git repository along with the other components, so manual"
	echo "download and unpacking is no longer needed."
	echo " "
	echo "Since your build tree has an existing pjproject directory, you'll"
	echo "need to remove it and re-run this script."
        echo "---------"
        echo " "
	exit 1
    fi

    for repo in "${repos[@]}"; do
        {
            repoDir=$(basename ${repo})
            repoUri=${gitdepot}${tree}/${repo}
            repoPushUri=${gitdepot_push}${tree}/${repo}

            if [ -d ${repoDir}/.git ]; then
                # update the origin to what is specified in repoUri
                ( cd ${repoDir} && git config remote.origin.url ${repoUri} )
                ( cd ${repoDir} && if test ${gitdepot_push}; then
                        git config remote.origin.pushurl ${repoPushUri};
                    else
                        git config --unset remote.origin.pushurl
                    fi )
                if ( cd ${repoDir} && git rev-parse --verify @{upstream} > /dev/null 2>&1 ); then
                    upstream=$(
                        cd ${repoDir} &&
                        git for-each-ref --format="%(upstream:short)" \
                            $(git rev-parse --symbolic-full-name HEAD))
                    echo ">> Pulling from ${upstream} (${repoDir})"
                    ( cd ${repoDir} && git pull )
                else
                    echo "-- Skipping ${repoDir}; no upstream branch"
                fi
            else
                echo ">> Cloning from ${repoUri} to ${repoDir}"
                git clone ${repoUri} ${repoDir}
            fi
        } 2>&1 | collapse
    done

    # Make sure that config_site.h exists for Windows.
    # harmless for all other platforms.  Only touch it if you have to
    # to avoid triggering needless builds.
    if ! test -e ./pjproject/pjlib/include/pj/config_site.h; then
        touch ./pjproject/pjlib/include/pj/config_site.h
    fi

} # pull

function passthrough()
{
    for repo in . "${repos[@]}"; do
        {
            repoDir=$(basename ${repo})
            repoName=$(basename "$(cd ${repoDir} && pwd)")
            if ! test -d ${repoDir}/.git; then
                echo >&2
                echo "!! Repo ${repoName} not yet cloned" >&2
                exit 1
            fi
            echo ">> git" "$@" "(${repoName})"
            ( cd ${repoDir} && git "$@" )
            if test $? -ne 0; then
                echo >&2
                echo "!! Failed to $1 ${repoName}." >&2
                exit 1
            fi
        } 2>&1 | collapse
    done
} # passthrough

function dry_run()
{
    echo ">> git" "$@" "(dry-run)"
    for repo in . "${repos[@]}"; do
        repoDir=$(basename ${repo})
        repoName=$(basename "$(cd ${repoDir} && pwd)")
        if ! test -d ${repoDir}/.git; then
            echo "!! Repo ${repoName} not yet cloned" >&2
            exit 1
        fi
        ( cd ${repoDir} && git "$@" --dry-run --quiet )
        if test $? -ne 0; then
            echo >&2
            echo "!! Would fail to $1 ${repoName}." >&2
            exit 1
        fi
    done
    echo

    for repo in . "${repos[@]}"; do
        {
            repoDir=$(basename ${repo})
            repoName=$(basename "$(cd ${repoDir} && pwd)")
            echo ">> git" "$@" "(${repoName})"
            ( cd ${repoDir} && git "$@" )
            if test $? -ne 0; then
                echo "!! Failed to push ${repoName}." >&2
                exit 1
            fi
        } 2>&1 | collapse
    done
} # dry_run

#
# Main script
#

# if we don't already have an ssh-agent running, fire one up
# if GIT_SSH is set, presumably you're on Windows and using plink and pageant
if test ${SSH_AUTH_SOCK-no} = no && test "${GIT_SSH-no}" = no; then
    eval `ssh-agent`

    echo "SSH_AGENT_PID = ${SSH_AGENT_PID}"
    exec `ssh-add ${1}`
    export kill_agent=yes
fi

$cmd "$@"

if test ${kill_agent-no} != no; then
    echo "killing ssh-agent"
    kill $SSH_AGENT_PID
fi
