#!/bin/bash

unset CDPATH 
## Script to help checkout jbosstools repositories.
##
## How to get/use:
## curl -O https://raw.github.com/jbosstools/jbosstools-build/master/scripts/checkout.sh
## chmod +x checkout.sh
## ./checkout.sh -d jbosstools jbosstools-openshift

usage()
{
    app=`basename $0`
    cat <<EOF
    usage: $app options <module> <module2> ..
    
    This script will check out repositories from JBoss Tools github reposiotry (http://github.com/jbosstools).
  
    OPTIONS:.
        -p   use private remote (SSH mode) (default is read-only)
        -d   destination directory, otherwise pwd is used.
        -u   username for remote fork to add (will not fork, but just assume the github user has one)
	-n   no upstream checkout. Default pom.xml will be parsed to checkout additional modules based on "bootstrap" profile in pom.xml

	Examples: 
          $app openshift
	  $app jbosstools-openshift webservices
	  $app base server gwt -u nickboldt -n
EOF
}

dbg=":" # debug off
#dbg="echo -e" # debug on
debug ()
{
	$dbg "${grey}$1${norm}"
}

basedir=`pwd`
username=""
moduleNames=""
noUpstreamClone=0
privaterepo=0

# colours!
norm="\033[0;39m";
grey="\033[1;30m";
green="\033[1;32m";
brown="\033[0;33m";
yellow="\033[1;33m";
blue="\033[1;34m";
cyan="\033[1;36m";
red="\033[1;31m";

# read commandline args
while [[ "$#" -gt 0 ]]; do
	case $1 in
		'-n'|'--no-upstream') noUpstreamClone=1;;
	        '-u') username="$2"; shift 1;;
                '-d') basedir="$2"; shift 1;;
                '-p') privaterepo=1;; 
		*) moduleNames="$moduleNames $1";;
	esac
	shift 1
done

showStatus()
{
	module=$1
	if [ -d "${basedir}/${module}" ]; then
	    cd ${basedir}/${module}
	    echo '=============================================================';
	    echo "git status:"
	    git status
	    echo '-------------------------------------------------------------';
	    echo "git remote -v"
	    git remote -v
	    echo '-------------------------------------------------------------';
	    echo "git branch -v"
	    git branch -v
	    echo '=============================================================';
	    cd -
       else 
	    echo ${basedir}/${module} not found
       fi
}

function realname() 
{
## TODO replace with a 404 check for the github repo
    reporesult=`curl --output /dev/null --silent --head -L --write-out '%{http_code}\n' https://github.com/jbosstools/$1`  
    if [ "$reporesult" == "404" ]; then
        echo jbosstools-$1
    else
        echo $1
    fi
}


readOp ()
{
	echo -e "There is already a folder in this directory called ${blue}${module}${norm}. Would you like to ${red}DELETE${norm} (d) and do a new clone or hit enter to ${grey}SKIP${norm}?"
	read op
	case $op in
		'd'|'D'|'delete'|'DELETE')
			rm -fr ${basedir}/${module}
			gitClone ${module}
			;;
	        *) 
			debug "Module ${module} skipped."
			;;
	esac
}

# store list of modules so we don't do them twice
doneModules=""
gitClone ()
{
	module=$1
        doneModules="${doneModules} ${module}"

	if [[ -d ${basedir}/${module} ]]; then
		readOp;
	else
                if [[ ${privaterepo} == "1" ]]; then
		    protocol=git@github.com:
		else
		    protocol=git://github.com/
		fi

                # main repo
		git clone ${protocol}jbosstools/${module}.git ${basedir}/${module}

		if [[ $username ]]; then
		    debug "Adding remote to fork for $username"
		    cd ${basedir}/${module}
		    git remote add $username git@github.com:${username}/${module}.git
		fi

		showStatus ${module}
	fi
}

# parse 
gitCloneUpstream ()
{
	if [[ -f ${basedir}/${moduleName}/pom.xml ]]; then
		debug "Read ${moduleName}/pom.xml ..."
		SEQ=/usr/bin/seq
		a=( $( cat ${basedir}/${moduleName}/pom.xml ) )
		nextModules=""
		for i in $($SEQ 0 $((${#a[@]} - 1))); do
			line="${a[$i]}"
			if [[ ${line//<id>bootstrap<\/id>} != $line ]]; then # begin processing actual content
				#debug "Found bootstrap entry on line $i: $line"
				i=$(( $i + 1 )); nextLine="${a[$i]}"; 
				while [[ ${nextLine//\/modules} == ${nextLine} ]]; do # collect upstream repos
					nextModule=$nextLine
					if [[ ${nextModule//module>} != ${nextModule} ]]; then # want this one
						nextModule=$(echo ${nextModule} | sed -e "s/<module>..\/\(.*\)<\/module>/\1/g")
						nextModule=`realname $nextModule`
						nextModules="${nextModules} ${nextModule}"
						debug "nextModule = $nextModule"
					fi
					i=$(( $i + 1 )); nextLine="${a[$i]}"
				done
				for nextModule in ${nextModules}; do gitCloneAll ${nextModule}; done
			fi
		done
		debug "Done reading ${basedir}/${moduleName}/pom.xml."
	else
		debug "File ${basedir}/${moduleName}/pom.xml not found. Did the previous step fail to git clone?"
	fi
}

gitCloneAll ()
{
	moduleName=$1
	if [[ $moduleName ]]; then
		debug "Done modules: $doneModules"
		if [[ ${doneModules/ ${moduleName}/} == $doneModules ]]; then
			if [[ ${noUpstreamClone} == "1" ]]; then
				debug "Fetching module ${moduleName} (no upstream modules will be fetched) ..."
				gitClone ${moduleName}
			else
				debug "Fetching module ${moduleName} (and upstream modules) ..."
				gitClone ${moduleName}
				# next step will only do something useful if the previous step completed; without it there's no ${moduleName}/pom.xml to parse
				gitCloneUpstream ${moduleName}
			fi
		else
			debug "Already processed ${moduleName}: skip."
		fi
	fi
}

if [[ ${basedir} == "." ]]; then basedir=`pwd`; fi

if [[ $moduleNames ]]; then
    for moduleName in $moduleNames; do    
	moduleName=`realname $moduleName`
	gitCloneAll ${moduleName}
    done
else
    echo "No modules listed. Try use jbosstools-central."
    echo
    usage
fi

