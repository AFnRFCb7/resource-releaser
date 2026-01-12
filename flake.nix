{
    inputs = { } ;
    outputs =
        { self } :
            {
                lib =
                    {
                        failure ,
                        pkgs
                    } :
                        let
                            implementation =
                                {
                                    channel ? "redis" ,
                                    gc-roots-directory ,
                                    locks-directory ,
                                    mounts-directory ,
                                    quarantine-directory
                                } :
                                    let
                                        application =
                                            pkgs.writeShellApplication
                                                {
                                                    name = "resource-releaser" ;
                                                    runtimeInputs =
                                                        [
                                                            pkgs.redis
                                                            pkgs.yq-go
                                                            failure
                                                            (
                                                                pkgs.writeShellApplication
                                                                    {
                                                                        name = "iteration" ;
                                                                        runtimeInputs =
                                                                            [
                                                                                pkgs.coreutils
                                                                                pkgs.flock
                                                                                pkgs.gettext
                                                                                pkgs.gnutar
                                                                                pkgs.jq
                                                                                pkgs.nix
                                                                                pkgs.xz
                                                                                failure
                                                                                (
                                                                                    pkgs.buildFHSUserEnv
                                                                                        {
                                                                                            name = "release-application" ;
                                                                                            extraBwrapArgs =
                                                                                                [
                                                                                                    "--ro-bind ${ mounts-directory }/$INDEX /mount"
                                                                                                    "--tmpfs /scratch"
                                                                                                ] ;
                                                                                            runScript =
                                                                                                let
                                                                                                    application =
                                                                                                        pkgs.writeShellApplication
                                                                                                            {
                                                                                                                name = "runScript" ;
                                                                                                                text = "$RELEASE" ;
                                                                                                            } ;
                                                                                                    in "${ application }/bin/runScript" ;
                                                                                        }
                                                                                )
                                                                            ] ;
                                                                        text =
                                                                            let
                                                                                resolve =
                                                                                    let
                                                                                        application =
                                                                                            pkgs.writeShellApplication
                                                                                                {
                                                                                                    name = "resolve" ;
                                                                                                    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.redis pkgs.yq-go failure ] ;
                                                                                                    text =
                                                                                                        ''
                                                                                                            if [[ -t 0 ]]
                                                                                                            then
                                                                                                                HAS_STANDARD_INPUT=false
                                                                                                                STANDARD_INPUT=
                                                                                                            else
                                                                                                                HAS_STANDARD_INPUT=true
                                                                                                                STANDARD_INPUT="$( cat )" || failure 3010bde7
                                                                                                            fi
                                                                                                            ARGUMENTS=( "$@" )
                                                                                                            ARGUMENTS_JSON="$( printf '%s\n' "${ builtins.concatStringsSep "" [ "$" "{" "ARGUMENTS[@]" "}" ] }" | jq -R . | jq -s . )" || failure 93afac56
                                                                                                            export HAS_STANDARD_INPUT
                                                                                                            export STANDARD_INPUT
                                                                                                            export RELEASE
                                                                                                            JSON="$(
                                                                                                                jq \
                                                                                                                    --null-input \
                                                                                                                    --compact-output \
                                                                                                                    --argjson ARGUMENTS "$ARGUMENTS_JSON" \
                                                                                                                    --arg HAS_STANDARD_INPUT "$HAS_STANDARD_INPUT" \
                                                                                                                    --arg STANDARD_INPUT "$STANDARD_INPUT" \
                                                                                                                    '
                                                                                                                        {
                                                                                                                            "arguments" : $ARGUMENTS ,
                                                                                                                            "has-standard-input" : ( $HAS_STANDARD_INPUT | test("true") ) ,
                                                                                                                            "index" : ( "$INDEX" | tostring ) ,
                                                                                                                            "mode" : ( "$MODE" | test("true") ) ,
                                                                                                                            "resolution" : "$RESOLUTION" ,
                                                                                                                            "standard-input" : $STANDARD_INPUT ,
                                                                                                                            "type" : "resolve-release"
                                                                                                                        }
                                                                                                                    '
                                                                                                            )" || failure e6780fa1
                                                                                                            redis-cli PUBLISH ${ channel } "$JSON" > /dev/null
                                                                                                            yq eval --prettyPrint "." - <<< "$JSON"
                                                                                                            rm --force "${ quarantine-directory }/$INDEX/release.sh"
                                                                                                            rm --recursive --force "${ quarantine-directory }/$INDEX/release"
                                                                                                        '' ;
                                                                                                } ;
                                                                                        in "${ application }/bin/resolve" ;
                                                                                in
                                                                                    ''
                                                                                       INDEX=
                                                                                       HASH=
                                                                                       ORIGINATOR_PID=
                                                                                       RELEASE=
                                                                                       while [[ "$#" -gt 0 ]]
                                                                                       do
                                                                                           case "$1" in
                                                                                               --index)
                                                                                                   INDEX="$2"
                                                                                                   shift 2
                                                                                                   ;;
                                                                                               --hash)
                                                                                                   HASH="$2"
                                                                                                   shift 2
                                                                                                   ;;
                                                                                               --originator-pid)
                                                                                                   ORIGINATOR_PID="$2"
                                                                                                   shift 2
                                                                                                   ;;
                                                                                               --release)
                                                                                                   RELEASE="$2"
                                                                                                   shift 2
                                                                                                   ;;
                                                                                               --resolution)
                                                                                                   RESOLUTIONS+=("$2")
                                                                                                   shift 2
                                                                                                   ;;
                                                                                               *)
                                                                                                   failure 464417ef
                                                                                                   ;;
                                                                                           esac
                                                                                       done
                                                                                       export ORIGINATOR_PID
                                                                                       if [[ -n "$ORIGINATOR_PID" ]]
                                                                                       then
                                                                                           tail --follow /dev/null --pid "$ORIGINATOR_PID"
                                                                                       fi
                                                                                       mkdir --parents "${ gc-roots-directory }"
                                                                                       while find "${ gc-roots-directory }" -type l -exec readlink -f {} \; | grep --quiet "${ mounts-directory }/$INDEX"
                                                                                       do
                                                                                            sleep 1
                                                                                       done
                                                                                       export HASH
                                                                                       mkdir --parents "${ locks-directory }"
                                                                                       if [[ -n "$HASH" ]]
                                                                                       then
                                                                                           exec 203> "${ locks-directory }/$HASH.lock"
                                                                                           flock -x 203
                                                                                       fi
                                                                                       export INDEX
                                                                                       export RELEASE
                                                                                       STANDARD_OUTPUT_FILE="$( mktemp )" || failure 5e6fd302
                                                                                       STANDARD_ERROR_FILE="$( mktemp )" || failure da84a50d
                                                                                       if [[ -n "$RELEASE" ]]
                                                                                       then
                                                                                           if release-application > "$STANDARD_OUTPUT_FILE" 2> "$STANDARD_ERROR_FILE"
                                                                                           then
                                                                                               STATUS="$?"
                                                                                           else
                                                                                               STATUS="$?"
                                                                                           fi
                                                                                       else
                                                                                           STATUS=0
                                                                                       fi
                                                                                       if [[ 0 == "$STATUS" ]] && [[ -n "$STANDARD_ERROR_FILE" ]]
                                                                                       then
                                                                                           TEMPORARY="$( mktemp --suffix .xz.tar )" || failure 1e7a248a
                                                                                            tar --create --file "$TEMPORARY" --xz "${ locks-directory }/$INDEX" "${ mounts-directory }/$INDEX" "${ quarantine-directory }/$INDEX" "${ gc-roots-directory }/$INDEX"
                                                                                            rm --recursive --force "${ locks-directory }/$INDEX" "${ mounts-directory }/$INDEX" "${ quarantine-directory }/$INDEX" "${ gc-roots-directory }/$INDEX"
                                                                                           # nix-collect-garbage
                                                                                       else
                                                                                           mkdir --parents "${ quarantine-directory }/$INDEX/release"
                                                                                           RELEASE_RESOLUTIONS_JSON_1="$( printf '"%s",'  "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTIONS[*]" "}" ] }" )" || failure 456dd0ed
                                                                                           RELEASE_RESOLUTIONS_JSON="[${ builtins.concatStringsSep "" [ "$" "{" "RELEASE_RESOLUTIONS_JSON_1%," "}" ] }]"
                                                                                           STANDARD_ERROR="$( cat "$STANDARD_ERROR_FILE" )" || failure be48c573
                                                                                           STANDARD_OUTPUT="$( cat "$STANDARD_OUTPUT_FILE" )" || failure 83137e6b
                                                                                           cat "$STANDARD_ERROR_FILE"
                                                                                           jq \
                                                                                               --null-input \
                                                                                               --arg HASH "$HASH" \
                                                                                               --arg INDEX "$INDEX" \
                                                                                               --arg ORIGINATOR_PID "$ORIGINATOR_PID" \
                                                                                               --arg RELEASE "$RELEASE" \
                                                                                               --argjson RELEASE_RESOLUTIONS "$RELEASE_RESOLUTIONS_JSON" \
                                                                                               --arg STANDARD_ERROR "$STANDARD_ERROR" \
                                                                                               --arg STANDARD_OUTPUT "$STANDARD_OUTPUT" \
                                                                                               --arg STATUS "$STATUS" \
                                                                                               '{
                                                                                                   "hash" : $HASH ,
                                                                                                   "index" : $INDEX ,
                                                                                                   "originator-pid" : $ORIGINATOR_PID ,
                                                                                                   "release" : $RELEASE ,
                                                                                                   "release-resolutions" : $RELEASE_RESOLUTIONS ,
                                                                                                   "standard-error" : $STANDARD_ERROR ,
                                                                                                   "standard-output" : $STANDARD_OUTPUT ,
                                                                                                   "status" : $STATUS
                                                                                               }' | yq eval --prettyPrint '.' - > "${ quarantine-directory }/$INDEX/release.yaml"
                                                                                           chmod 0400 "${ quarantine-directory }/$INDEX/release.yaml"
                                                                                           export ARGUMENTS="\$ARGUMENTS"
                                                                                           export ARGUMENTS_JSON="\$ARGUMENTS_JSON"
                                                                                           export HAS_STANDARD_INPUT="\$HAS_STANDARD_INPUT"
                                                                                           export JSON="\$JSON"
                                                                                           export INDEX
                                                                                           export STANDARD_INPUT="\$STANDARD_INPUT"
                                                                                           export TYPE="resolve-release"
                                                                                           MODE=false RESOLUTION=release envsubst < ${ resolve } > "${ quarantine-directory }/$INDEX/release.sh"
                                                                                           chmod 0500 "${ quarantine-directory }/$INDEX/release.sh"
                                                                                           for RESOLUTION in "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTIONS[@]" "}" ] }"
                                                                                           do
                                                                                               envsubst < ${ resolve } > "${ quarantine-directory }/$INDEX/release/$RESOLUTION"
                                                                                               chmod 0500 "${ quarantine-directory }/$INDEX/release/$RESOLUTION"
                                                                                           done
                                                                                       fi
                                                                                       rm "$STANDARD_OUTPUT_FILE" "$STANDARD_ERROR_FILE"
                                                                                    '' ;
                                                                    }
                                                            )
                                                        ] ;
                                                    text =
                                                        ''
                                                            redis-cli SUBSCRIBE ${ channel } | while read -r TYPE
                                                            do
                                                                if [[ "$TYPE" == "message" ]]
                                                                then
                                                                    read -r CHANNEL
                                                                    if [[ ${ channel } == "$CHANNEL" ]]
                                                                    then
                                                                        read -r PAYLOAD
                                                                        TYPE_="$( yq eval ".type" <<< "$PAYLOAD" - )" || failure 2ee1309a
                                                                        if [[ "valid" == "$TYPE_" ]]
                                                                        then
                                                                            INDEX="$( yq eval ".index | tostring" - <<< "$PAYLOAD" )" || failure d79eee6f
                                                                            HASH="$( yq eval ".hash | tostring" - <<< "$PAYLOAD" )" || failure 7753e2d6
                                                                            ORIGINATOR_PID="$( yq eval '."originator-pid" | tostring' - <<< "$PAYLOAD" )" || failure de9dd0f2
                                                                            RELEASE="$( yq eval ".description.secondary.seed.release // \"\" | tostring" - <<< "$PAYLOAD" )" || failure 784a6c15
                                                                            RESOLUTIONS=()
                                                                            yq eval --prettyPrint ".description.secondary.seed.resolutions" <<< "$PAYLOAD"
                                                                            yq eval '.description.secondary.seed.resolutions.init // [] | .[]' - <<< "$PAYLOAD" | while IFS= read -r RESOLUTION
                                                                            do
                                                                                RESOLUTIONS+=( "--resolution" "$RESOLUTION" )
                                                                            done
                                                                            iteration --hash "$HASH" --index "$INDEX" --originator-pid "$ORIGINATOR_PID" --release "$RELEASE" "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTION[@]" "}" ] }" &
                                                                        elif [[ "resolve-init" == "$TYPE_" ]]
                                                                        then
                                                                            INDEX="$( yq eval ".index | tostring" - <<< "$PAYLOAD" )" || failure f3c64901
                                                                            RELEASE="$( yq eval ".release" - <<< "$PAYLOAD" )" || failure 3ae6bdb4
                                                                            RESOLUTIONS=()
                                                                            while IFS= read -r RESOLUTION
                                                                            do
                                                                                RESOLUTIONS+=( "--resolution" "$RESOLUTION" )
                                                                            done <<< "$( yq eval '.release-resolutions // [] | .[]' - <<< "$PAYLOAD" )" || failure 0075bf74
                                                                            iteration --index "$INDEX" --release "$RELEASE" "${ builtins.concatStringsSep "" [ "$" "{" "RESOLUTIONS[@]" "}" ] }" &
                                                                        elif [[ "resolve-release" == "$TYPE_" ]]
                                                                        then
                                                                            INDEX="$( yq eval ".index | tostring" - <<< "$PAYLOAD" )" || failure 182712c3
                                                                            iteration --index "$INDEX"
                                                                        fi
                                                                    fi
                                                                fi
                                                            done
                                                        '' ;
                                                } ;
                                        in "${ application }/bin/resource-releaser" ;
                            in
                                {
                                    check =
                                        {
                                            channel ? "c8807213" ,
                                            expected ? "24a5ba9c" ,
                                            gc-roots-directory ? "8584bd77" ,
                                            locks-directory ? "4c3fa402" ,
                                            mounts-directory ? "cfef9d2a" ,
                                            quarantine-directory ? "58c023ee"
                                        } :
                                            pkgs.stdenv.mkDerivation
                                                {
                                                    installPhase = ''execute-test "$out"'' ;
                                                    name = "check" ;
                                                    nativeBuildInputs =
                                                        [
                                                            (
                                                                let
                                                                    observed =
                                                                        builtins.toString
                                                                            (
                                                                                implementation
                                                                                    {
                                                                                        channel = channel ;
                                                                                        gc-roots-directory = gc-roots-directory ;
                                                                                        locks-directory = locks-directory ;
                                                                                        mounts-directory = mounts-directory ;
                                                                                        quarantine-directory = quarantine-directory ;
                                                                                    }
                                                                            ) ;
                                                                    in
                                                                        if expected == observed then
                                                                            pkgs.writeShellApplication
                                                                                {
                                                                                    name = "execute-test" ;
                                                                                    runtimeInputs = [ pkgs.coreutils ] ;
                                                                                    text =
                                                                                        ''
                                                                                            OUT="$1"
                                                                                            touch "$OUT"
                                                                                        '' ;
                                                                                }
                                                                        else
                                                                            pkgs.writeShellApplication
                                                                                {
                                                                                    name = "execute-test" ;
                                                                                    runtimeInputs = [ failure ] ;
                                                                                    text =
                                                                                        ''
                                                                                            failure 8c67cfa1 resource-releaser "We expected to see ${ expected } but we observed ${ observed }"
                                                                                        '' ;
                                                                                }
                                                            )
                                                        ] ;
                                                    src = ./. ;
                                                } ;
                                    implementation = implementation ;
                                } ;
            } ;
}