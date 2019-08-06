#!/bin/bash

# ALL_VARS stores key / value pairs from the parsed manifest files
declare -A ALL_VARS
export ALL_VARS
# FINAL_VALS stores ALL_VARS after mapping and manipulation
# FINAL_VALS is used to generate terraform files
declare -A FINAL_VALS
export FINAL_VALS

parse_manifests() {
    local manifest_dir=$1

    printf "Parsing manifest files in %s\n" "$manifest_dir"
    for file in "$manifest_dir"/*.yaml; do
        printf "\nParsing %s\n" "$file"

        # Parse the yaml file using yq
        # The end result is an associative array, manifest_vars
        # The keys are the fields in the yaml file
        # and the values are the values in the yaml file
        # shellcheck disable=SC2016
        values=$(yq 'paths(scalars) as $p | [ ( [ $p[] | tostring ] | join(".") ) , ( getpath($p) | tojson ) ] | join(" ")' "$file")
        if [ $? -ne 0 ]; then
            printf "Error during parsing..."
            exit 1
        fi
        mapfile -t lines < <(echo "$values" | sed -e 's/^"//' -e 's/"$//' -e 's/\\"//g')
        unset manifest_vars
        declare -A manifest_vars
        for line in "${lines[@]}"; do
            # shellcheck disable=SC2206
            l=($line)
            # create the associative array
            manifest_vars[${l[0]}]=${l[1]}
            #echo "manifest_vars[${l[0]}] == ${l[1]}"
        done

        name=""
        if [[ $file =~ install-config.yaml ]]; then
            # the install-config file is not really a manifest and
            # does not have a kind: tag.
            kind="install-config"
            name="install-config"
        elif [[ ${manifest_vars[kind]} ]]; then
            # All the manifest types must have at least one entry
            # in MANIFEST_CHECK.  The entry can just be an optional
            # field.
            kind=${manifest_vars[kind]}
            name=${manifest_vars[metadata.name]}
        else
            printf "kind parameter missing OR of unrecognized type in file %s" "$file"
            exit 1
        fi

        recognized=false
        printf "Kind: %s\n" "$kind"
        # Loop through all entries in MANIFEST_CHECK
        for v in "${!MANIFEST_CHECK[@]}"; do
            # Split the path (i.e. bootstrap.spec.hardwareProfile ) into array
            IFS='.' read -r -a split <<<"$v"
            # MANIFEST_CHECK has the kind as the first component
            # do we recognize this kind?
            if [[ ${split[0]} =~ $kind ]]; then
                recognized=true
                required=false
                # MANIFEST_CHECK has req/opt as second component
                [[ ${split[1]} =~ req ]] && required=true
                # Reform path removing kind.req/opt
                v_vars=$(join_by "." "${split[@]:2}")
                # Now check if there is a value for this MANIFEST_CHECK entry
                # in the parsed manifest
                if [[ ${manifest_vars[$v_vars]} ]]; then
                    if [[ ! "${manifest_vars[$v_vars]}" =~ ${MANIFEST_CHECK[$v]} ]]; then
                        printf "Invalid value for \"%s\" : \"%s\" does not match %s in %s\n" "$v" "${manifest_vars[$v_vars]}" "${MANIFEST_CHECK[$v]}" "$file"
                        exit 1
                    fi
                    # echo " ${manifest_vars[$v_vars]} ===== ${BASH_REMATCH[1]} === ${MANIFEST_CHECK[$v]}"
                    # The regex contains a capture group that retrieves the value to use
                    # from the field in the yaml file
                    # Update manifest_var with the captured value.
                    manifest_vars[$v_vars]="${BASH_REMATCH[1]}"
                elif [[ "$required" =~ true ]]; then
                    # There was no value found in the manifest and the value
                    # was required.
                    printf "Missing value, %s, in %s...\n" "$v" "$file"
                    exit 1
                fi
            fi
        done

        if [[ $recognized =~ false ]]; then
            printf "File: %s contains an unrecognized kind:\n" "$file"
        fi

        # Finished the parse
        # Take all final values and place them in the ALL_VARS
        # array for use by gen_terraform
        for v in "${!manifest_vars[@]}"; do
            # Make entries unique by prepending with manifest object name
            # Should have a uniqueness check here!
            val="$name.$v"
            if [[ ${ALL_VARS[$val]} ]]; then
                printf "Duplicate Manifest value...\"%s\"\n" "$val"
                printf "This usually occurs when two manifests have the same metadata.name...\n"
                exit 1
            fi
            ALL_VARS[$val]=${manifest_vars[$v]}
            printf "\tALL_VARS[%s] == \"%s\"\n" "$val" "${manifest_vars[$v]}"
        done
    done

    for v in "${!ALL_VARS[@]}"; do
        echo "$v : ${ALL_VARS[$v]}"
    done
}

map_cluster_vars() {

    # shellcheck disable=SC1091
    source scripts/cluster_map.sh

    # The keys in the following associative array
    # specify varies to be emitted in the terraform vars file.
    # the associated value contains
    #  1. A static string value
    #  2. A string with ENV vars that have been previously defined
    #  3. A string prepended with '%' to indicate the final value is
    #     located in the ALL_VARS array
    #  4. ALL_VARS references may contain path.[field].field
    #     i.e. bootstrap.spec.bmc.[credentialsName].password
    #     in this instance [name].field references another manifest file
    #  5. If a rule ends with an '@', the field will be base64 decoded
    #

    # Generate the cluster terraform values for the fixed
    # variables
    #
    for v in "${!CLUSTER_MAP[@]}"; do
        rule=${CLUSTER_MAP[$v]}
        printf "Apply map-rule: \"%s\"\n" "$rule"
        # Map rules that start with % indicate that the value for the
        mapped_val="unknown"
        if [[ $rule =~ ^\% ]]; then
            rule=${rule/#%/}     # Remove beginning %
            ref_path=${rule/%@/} # Remove any trailing @ (base64)
            # Allow for indirect references to other manifests...
            if [[ $rule =~ \[([-_A-Za-z0-9]+)\] ]]; then
                ref_field="${BASH_REMATCH[1]}"
                [[ $rule =~ ([^\[]+).*$ ]] && ref="${BASH_REMATCH[1]}$ref_field"
                if [[ ! ${ALL_VARS[$ref]} ]]; then
                    printf "Indirect ref in rule \"%s\" failed...\n" "$rule"
                    printf "\"%s\" does not exist...\n" "$ref"
                    exit 1
                fi
                ref="${ALL_VARS[$ref]}"
                [[ $rule =~ [^\]]+\]([^@]+) ]] && ref_path="$ref${BASH_REMATCH[1]}"
                if [[ ! ${ALL_VARS[$ref_path]} ]]; then
                    printf "Indirect ref in rule \"%s\" failed...\n" "$rule"
                    printf "\"%s\" does not exist...\n" "$ref_path"
                    exit 1
                fi
            fi
            if [[ $rule =~ .*@$ ]]; then
                mapped_val=$(echo "${ALL_VARS[$ref_path]}" | base64 -d)
            else
                mapped_val="${ALL_VARS[$ref_path]}"
            fi
        else
            # static mapping
            mapped_val="$rule"
            ref_path="constant"
        fi
        
        FINAL_VALS[$v]="$mapped_val"

        printf "\tFINAL_VALS[%s] = \"%s\"\n" "$v" "$mapped_val"
    done
}

check_var() {

    if [ "$#" -ne 2 ]; then
        echo "${FUNCNAME[0]} requires 2 arguements, varname and config_file...($(caller))"
        exit 1
    fi

    local varname=$1
    local config_file=$2

    if [ -z "${!varname}" ]; then
        echo "$varname not set in ${config_file}, must define $varname"
        exit 1
    fi
}

check_regular_file_exists() {
    cfile="$1"

    if [ ! -f "$cfile" ]; then
        echo "file does not exist: $cfile"
        exit 1
    fi
}

check_directory_exists() {
    dir="$1"

    if [ ! -d "$dir" ]; then
        echo "directory does not exist: $dir"
        exit 1
    fi
}

join_by() {
    local IFS="$1"
    shift
    echo "$*"
}

#
# The prep_bm_host.src file contains information
# about the provisioning interface, baremetal interface
# and external (internet facing) interface of the
# provisioning host
#
parse_prep_bm_host_src() {
    prep_src="$1"

    check_regular_file_exists "$prep_src"

    # shellcheck source=/dev/null
    source "$prep_src"

    if [ -z "${PROV_INTF}" ]; then
        echo "PROV_INTF not set in ${prep_src}, must define PROV_INTF"
        exit 1
    fi

    if [ -z "${BM_INTF}" ]; then
        echo "BM_INTF not set in ${prep_src}, must define BM_INTF"
        exit 1
    fi

    echo "PROV_IP_CIDR $PROV_IP_CIDR"
}
