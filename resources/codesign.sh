#!/bin/bash

# Code signing functionality

SERVERLIST=(http://timestamp.comodoca.com/authenticode \
http://timestamp.verisign.com/scripts/timstamp.dll \
http://timestamp.globalsign.com/scripts/timestamp.dll \
http://tsa.starfieldtech.com)

RFC3161SERVERLIST=(http://sha256timestamp.ws.symantec.com/sha256/timestamp \
http://timestamp.globalsign.com/scripts/timstamp.dll \
http://timestamp.comodoca.com/rfc3161 \
http://tsa.startssl.com/rfc3161 \
http://time.certum.pl \
http://timestamp.digicert.com)

# RfC3161SERVERLIST from https://gist.github.com/Manouchehri/fd754e402d98430243455713efada710
# Note: removed the following servers post testing for various reasons:
#   https://timestamp.geotrust.com/tsa not available
#   http://timestamp.verisign.com/scripts/timstamp.dll not RFC3161
#   http://timestamp.wosign.com timed out
#   https://freetsa.org failed
#   http://dse200.ncipher.com/TSS/HttpTspServer hmm
#   http://tsa.safecreative.org hmm
#   http://zeitstempel.dfn.de hmm
#   https://ca.signfiles.com/tsa/get.aspx is a demo server not intended for extended use
#   http://services.globaltrustfinder.com/adss/tsa invalid response
#   https://tsp.iaik.tugraz.at/tsp/TspRequest invalid
#   http://timestamp.apple.com/ts01 returns okay but does not countersign validly

##
## Code sign a Windows PE executable or msi installer database
##
function codesign {
  local target="$1"
  local SIGNNAME="$2"
  local SIGNFILE="$target"

  local file_extension=${target##*.}
  if [[ "$file_extension" == "msi" ]] || [[ "$file_extension" == "msm" ]]; then
    # msi can only be single-signed, not dual-signed
    "$SIGNTOOL" sign //f "$SC_PFX_SHA256" //fd sha256 //du "$SC_URL" //p "$SC_PWD" //v //d "$SIGNNAME" "$SIGNFILE" || die "Unable to sign with sha256 $SIGNFILE"
    codesign_timestamp "$SIGNFILE" sha256msi || die "Unable to timestamp $SIGNFILE"
  else
    # dual sign, first with sha1, then with sha256
    "$SIGNTOOL" sign //f "$SC_PFX_SHA1" //fd sha1 //du "$SC_URL" //p "$SC_PWD" //v //d "$SIGNNAME" "$SIGNFILE" || die "Unable to sign with sha1 $SIGNFILE"
    codesign_timestamp "$SIGNFILE" sha1 || die "Unable to timestamp $SIGNFILE"
    "$SIGNTOOL" sign //as //f "$SC_PFX_SHA256" //fd sha256 //du "$SC_URL" //p "$SC_PWD" //v //d "$SIGNNAME" "$SIGNFILE" || die "Unable to sign with sha256 $SIGNFILE"
    codesign_timestamp "$SIGNFILE" sha256 || die "Unable to timestamp $SIGNFILE"
  fi
}

##
## Add a code signing timestamp to a PE executable or msi installer database
##
function codesign_timestamp {
  local SIGNFILE=$1
  local MODE=$2
  local SERVER=$3
  
  if [[ -z $SERVER ]]; then
    if [[ $MODE == sha1 ]]; then
      local SERVERS=${SERVERLIST[*]}
    else
      local SERVERS=${RFC3161SERVERLIST[*]}
    fi
  else
    local SERVERS=($SERVER)
  fi
  
  #
  # Randomize the server list so that we don't always try
  # the same order
  #
  SERVERS=$(echo ${SERVERS[*]} | tr " " "\n" | shuf | tr "\n" " ")
  
  local a
  local s
  
  #
  # Retry the code signing 3 times against the server list in case of
  # temporary network failure. After that we'll give up and fail the
  # build
  #
  for a in `seq 1 3`; do
    for s in ${SERVERS[@]}; do
      echo Attempting to sign file with timestamp server $s
      # try to timestamp the file. This operation is unreliable and may need to be repeated...
      case $MODE in
        sha1)
          "$SIGNTOOL" timestamp //t "$s" //v "$SIGNFILE" && return 0
          ;;
        sha256)
          "$SIGNTOOL" timestamp //tr "$s" //tp 1 //td sha256 //v "$SIGNFILE" && return 0
          ;;
        sha256msi)
          "$SIGNTOOL" timestamp //tr "$s" //td sha256 //v "$SIGNFILE" && return 0
          ;;
      esac
      
      echo "Signing failed. Probably cannot find the timestamp server at $s"
    done

    sleep 2
  done

  return 1
}
