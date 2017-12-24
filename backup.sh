#!/bin/bash

# configurable variables
UUID=""
# preconfdSrc=""

check_failed() {
  if ! [ $1 -eq 0 ]; then
    echo "$2" >> /tmp/failed.txt
  fi
}

d=0 # demo
h=0 # help
v=0 # verbose
p=0 # prompt
P=0 # prompt only before overwriting

mode=0 # check how to choose source(s) and target
smf=0 # source must follow
tmf=0 # target must follow

# Parsing shell arguments
for i in `seq 1 $#`;
do
  if [ $smf -eq "1" ]; then
    if [[ ${!i} == [-][stdvpP] ]]; then
      echo "source is given, can't be empty"
      exit
    fi
    opo=$((i+1))
    if [[ ${!opo} == [-][a-zA-Z] ]]; then
      if [ ! -z ${sourceDir+x} ]; then
        sourceDir="$sourceDir"
      fi
      mode=$((mode+1))
      smf=0
    else
      if [ $i -eq $# ]; then
        mode=$((mode+1))
      fi
      sourceDir="$sourceDir"
    fi
    sourceDir="$sourceDir""${!i};"
    continue
  fi
  if [ $tmf -eq "1" ]; then
    if [[ ${!i} == [-][stdvpP] ]]; then
      echo "target is given, can't be empty"
      exit
    fi
    targetDir="${!i}"
    mode=$((mode+2))
    tmf=0
    continue
  fi

  case ${!i} in
    -s ) smf=1
    if [ $i -eq $# ]; then
      echo "Source is given, can't be empty. Exiting."
      exit
    fi
    ;;
    -t ) tmf=1
    if [ $i -eq $# ]; then
      echo "Target is given, can't be empty. Exiting."
      exit
    fi
    ;;
    -d ) d=1
    # mode=$((mode+4))
    ;;
    -v ) v=1
    ;;
    -h ) h=1
    ;;
    -p ) p=1
    ;;
    -P ) P=1
    ;;
    *) echo "This option doesn't exist:" ${!i}
  esac
done

if [ $h -eq "1" ]; then
  echo """
  # Script for backing up folders to an external hard drive.
  # Written in bash.
  # Options:
  # -s source
  # -t target
  # -d demo
  # -h help
  # -p prompt
  # -P prompt only when overwriting
  # -v verbose
  """
  exit
fi

if [ -x /bin/blkid ]; then
	blkid=/bin/blkid
else
	if [ -x /sbin/blkid ]; then
		blkid=/sbin/blkid
	else
		echo "blkid not found in /bin/ nor in /sbin/. Exiting."
		exit
	fi
fi

$blkid | grep $UUID &> /dev/null
if [ $? == 0 ]; then
	echo "Found"
else
  echo "Configured backup disk not found. Exiting. Try running blkid manually and then re-running the script."
  if ! [ $d -eq "1" ]; then
	  exit
  fi
fi

drive=$($blkid | sed -n "s/\(\/[a-z]\{3\}\/[a-z0-9]\+\).*\sUUID=\"$UUID\".*/\1/p")
mountPath=$(mount | grep -e $drive | sed -n 's/\/[a-z0-9\/-]\+\s\+on\s\(\/[a-zA-Z0-9\/-]\+\)\s\+.*/\1/p')

if [ -z ${sourceDir+x} ]; then
	src="."
else
	src="$sourceDir"
fi

# To loop through the list of source directories
IFS=";"

echo "This is the target disk:"
echo ""$mountPath" on "$drive""
echo "-------------------------"
#Write a listing of all directories and ask if ok to continue
echo "These directories are going to be backed up."
for i in $src
do
  echo "$i"
done

read -p "Continue? Y/n" dirsOk
if [[ $dirsOk == "n" ]] || [[ $dirsOk == "N" ]]; then
  echo "Exiting."
  exit
fi
echo "-------------------------"

#the exec below redirect is used for reading input when prompt enabled.
#Not sure about the solution (using fd 3 with /dev/tty),
#it works, but might not be the best solution.
if [ $p -eq "1" ] || [ $P -eq "1" ]; then
  exec 3<> /dev/tty
fi

for pth in $src
do
	find $pth -not -type d -print0 | while IFS= read -r -d '' file
	do
    case $mode in
      "0" | "1") # target not given
        temp=${file/.\//\/}
        copyTarget="$mountPath/backup/$temp"
        copyTarget=${copyTarget/.\//\/}
        ;;
  		"2" | "3") # target given
         temp="${file#$pth}"
         copyTarget="$targetDir/$temp"
  	    ;;
    esac

    if [ -e $copyTarget ]
		then
      if [ $d -eq "1" ]; then
        echo "md5sum "$file" | awk -v var1="$copyTarget" '{print $1,var1}' > /tmp/cksum.txt"
        echo "Demo: cp -pf "$file" "$copyTarget" >> "
        continue
      fi
      if [ $v -eq "1" ]; then
        echo "Getting md5sum with:"
        echo "md5sum "$file" | awk -v var1="$copyTarget" '{print $1,var1}' > /tmp/cksum.txt"
      fi
      md5sum "$file" | awk -v var1="$copyTarget" '{print $1,var1}' > /tmp/cksum.txt
		  if ! md5sum -c /tmp/cksum.txt &> /dev/null; then
        if [ $v -eq "1" ]; then
          echo "cp -pf "$file" "$copyTarget" >> /tmp/log.txt"
        fi
        if [ $p -eq "1" ] || [ $P -eq "1" ]; then
          echo "Overwriting "$file" with "$copyTarget"."
          lc=0
          while [ $lc -eq 0 ]
          do
            read -u 3 -p "y/N?" inp
            if [[ $inp =~ ^[Nn][Oo]?$ ]]; then
              lc=1
              break
            else
              if ! [[ $inp =~ ^[Yy]([Ee][Ss])?$ ]]; then
                echo "Couldnt understand "$inp". Try again"
              else
                cp -pf "$file" "$copyTarget" >> /tmp/log.txt
                check_failed $? "$file"
                lc=2
              fi
            fi
          done
          if [ $lc -eq 1 ]; then
            continue
          fi
        else
           cp -pf "$file" "$copyTarget" >> /tmp/log.txt
           check_failed $? "$file"
        fi
      fi
    else
      if [ $d -eq "1" ]; then
        echo "mkdir -p $(dirname "$copyTarget")"
        echo "cp -pf "$file" "$copyTarget" >> /tmp/log.txt"
        continue
      fi

      if [ $v -eq "1" ]; then
        echo "mkdir -p $(dirname "$copyTarget")"
        echo "cp -pf "$file" "$copyTarget" >> /tmp/log.txt"
      fi

      mkdir -p $(dirname "$copyTarget")

      if [ $p -eq "1" ]; then
        echo "Copying "$file" to "$copyTarget"."
        lc=0
        while [ $lc -eq 0 ]
        do
          read -u 3 -p "y/N?" inp
          if [[ $inp =~ ^[Nn][Oo]?$ ]]; then
            lc=1
            break
          else
            if ! [[ $inp =~ ^[Yy]([Ee][Ss])?$ ]]; then
              echo "Couldnt understand "$inp". Try again"
            else
              cp -pf "$file" "$copyTarget" >> /tmp/log.txt
              check_failed $? "$file"
              lc=2
            fi
          fi
        done
        if [ $lc -eq 1 ]; then
          continue
        fi
      else
         cp -pf "$file" "$copyTarget" >> /tmp/log.txt
         check_failed $? "$file"
      fi
    fi
  done
  IFS=";"
done
exec 3>&-
echo "Done"
