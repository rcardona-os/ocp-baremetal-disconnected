#!/bin/bash

export OCP_RELEASE='4.13.12'
export OCP_VERSION='4.13'
export OCP_RELEASE_PATH='ocp'
export LOCAL_REPOSITORY='ocp4/openshift4'
export PRODUCT_REPO='openshift-release-dev'
export RELEASE_NAME='ocp-release'
export REGISTRY_PORT='8443'
export ARCHITECTURE='x86_64'
export REGISTRY_FQDN='registry.sandbox549.opentlc.com'
export GODEBUG='x509ignoreCN=0'


usage () {
    echo " ---- Script Descrtipion ---- "
    echo "  "
    echo " This script configures the bastion host that is meant to serve as local registry and core installation components of Red Hat Openshift 4"
    echo " "
    echo " Pre-requisites: "
    echo " "
    echo -e "\n\e[1;32m - Update the registry installation variables at the beginning of this script \e[0m\n"
    echo -e "\n\e[1;32m - Download the OCP installation secret in https://cloud.redhat.com/openshift/install/pull-secret and create a file called 'pull-secret.json', \e[0m"
    echo -e "\e[1;32m   this file should also include the credential of the mirrored registry. Place this at this location: ${HOME} directory \e[0m\n"
    echo " "
    echo " Options:  "
    echo " "
    echo " * check-dependencies: downloads and prepare the os packages"
    echo " * get-artifacts : downloads and prepare the oc client and OCP installation program"
    echo " * list-redhat-operators : Red Hat products packaged and shipped by Red Hat. Supported by Red Hat."
    echo " * list-certified-operators : Products from leading independent software vendors (ISVs)."
    echo " * list-redhat-marketplace : Certified software that can be purchased from Red Hat Marketplace."
    echo " * list-community-operators : Software maintained by relevant representatives in the operator-framework/community-operators GitHub repository. No official support."
    echo " * redhat-operators : Red Hat products packaged and shipped by Red Hat. Supported by Red Hat."
    echo " * certified-operators : Products from leading independent software vendors (ISVs)."
    echo " * redhat-marketplace : Certified software that can be purchased from Red Hat Marketplace."
    echo " * community-operators : Software maintained by relevant representatives in the operator-framework/community-operators GitHub repository. No official support."
    echo " * create-custom-catalog-redhat-operators : Red Hat products packaged and shipped by Red Hat. Supported by Red Hat."
    echo " * create-custom-catalog-certified-operators : Products from leading independent software vendors (ISVs)."
    echo " * create-custom-catalog-redhat-marketplace : Certified software that can be purchased from Red Hat Marketplace."
    echo " * create-custom-catalog-community-operators : Software maintained by relevant representatives in the operator-framework/community-operators GitHub repository. No official support."
    echo " * export-base-registry : Exports base container images for disconnected environments."
    echo " * export-custom-catalog-redhat-operators : Exports custom operator catalogs for disconnected environments."
    echo "  "
    echo -e " Usage: $0 [ prep_dependencies | get_artifacts | prep_registry | mirror_registry | list_redhat-operators | list_certified-operators | list_redhat-marketplace | list_community-operators | redhat-operators | certified-operators | redhat-marketplace | community-operators | create-custom-catalog-redhat-operators | create-custom-catalog-certified-operators | create-custom-catalog-redhat-marketplace | create-custom-catalog-community-operators ] "
    echo "  "
    echo " ---- Ends Descrtipion ---- "
    echo "  "
}


check_deps () {
    if [[ ! $(rpm -qa podman skopeo bind bind-utils net-tools jq  | wc -l) -ge 7 ]] ;
    then
        install_tools
    fi
}

get_artifacts () {
    cd ~/
    test -d artifacts || mkdir artifacts ; cd artifacts
    test -f opm-linux-${OCP_RELEASE}.tar.gz || curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_RELEASE}/opm-linux-${OCP_RELEASE}.tar.gz
    test -f grpcurl_1.8.0_linux_x86_64.tar.gz || curl -J -L -O https://github.com/fullstorydev/grpcurl/releases/download/v1.8.8/grpcurl_1.8.8_linux_x86_64.tar.gz
    cd ..
    sudo tar -xzf ./artifacts/opm-linux-${OCP_RELEASE}.tar.gz -C /usr/local/bin/
    sudo tar -xzf ./artifacts/grpcurl_1.8.8_linux_x86_64.tar.gz -C /usr/local/bin/
}


install_tools () {
    #RHEL9
    if grep -q -i "release 9" /etc/redhat-release; then
        sudo dnf -y install podman skopeo bind bind-utils net-tools jq
        echo -e "\e[1;32m Packages - Dependencies installed\e[0m"
    fi

}

check_login_redhat_io_registry () {
  podman login --authfile ${HOME}/pull-secret.json registry.redhat.io
}

# MIRRORING DEAFULT CATALOG OPERATORS

redhat-operators () {
  check_login_redhat_io_registry
  echo "Mirror redhat-operators images "
  echo " "
  oc adm catalog mirror registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm  --registry-config=${HOME}/pull-secret.json --insecure --index-filter-by-os='linux/amd64'
  echo " "
}

certified-operators () {
  check_login_redhat_io_registry
  echo "Mirror certified-operators images"
  echo " "
  oc adm catalog mirror registry.redhat.io/redhat/certified-operator-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm --registry-config=${HOME}/pull-secret.json --insecure --index-filter-by-os='linux/amd64'
  echo " "
}

redhat-marketplace () {
  check_login_redhat_io_registry
  echo "Mirror redhat-marketplace images"
  echo " "
  oc adm catalog mirror registry.redhat.io/redhat/redhat-marketplace-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm  --registry-config=${HOME}/pull-secret.json --insecure --index-filter-by-os='linux/amd64'
  echo " "
}

community-operators () {
  check_login_redhat_io_registry
  echo "Mirror community-operators images"
  echo " "
  oc adm catalog mirror registry.redhat.io/redhat/community-operator-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm  --registry-config=${HOME}/pull-secret.json --insecure--index-filter-by-os='linux/amd64'
  echo " "
}


# MIRRORING CUSTOM COTALOG OPERATORS

OPERATOR_NAMES="$2"

create-custom-redhat-operators () {
  check_login_redhat_io_registry
  if [[ -z "${OPERATOR_NAMES}" ]]
  then
    echo -e "\n\e[1;31m FAILED => Command expects custom images to be added to the custom Operator Catalog, please execute the command as follows: \e[0m"
    echo -e "\n\e[1;34m Command => mirror-operator-catalog-v4.x.sh create-custom-catalog-redhat-operators [OPERATOR_NAME_1, ...  ,OPERATOR_NAME_N] \e[0m"
    echo -e "\n\e[1;45m Example => mirror-operator-catalog-v4.x.sh create-custom-catalog-redhat-operators advanced-cluster-management,jaeger-product,quay-operator \e[0m"
    echo " "
    exit 1
  else
    echo -e "\n\e[1;32m Pruning custom-redhat-operators image \e[0m\n"
    opm index prune -f registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION} -p ${OPERATOR_NAMES} -t ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators/redhat-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Pushing custom-redhat-operators image to local registry \e[0m\n"
    podman push ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators/redhat-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Creating custom-redhat-operators catalog \e[0m\n"
    oc adm catalog mirror ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators/redhat-operator-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators  -a ${HOME}/pull-secret.json --insecure --index-filter-by-os='linux/amd64'
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;32m STATUS: Custom redhat-operator SUCCESFUL CREATED \e[0m"
    else
      echo -e "\n\e[1;31m STATUS: FAILED => Custom redhat-operator NOT CREATED \e[0m"
      exit 1
    fi
  fi
}

create-custom-certified-operators () {
  check_login_redhat_io_registry
  if [[ -z "${OPERATOR_NAMES}" ]]
  then
    echo -e "\n\e[1;31m FAILED => Command expects custom images to be added to the custom Operator Catalog, please execute the command as follows: \e[0m"
    echo -e "\n\e[1;34m Command => mirror-operator-catalog-v4.x.sh create-custom-catalog-certified-operators [OPERATOR_NAME_1, ...  ,OPERATOR_NAME_N] \e[0m"
    echo -e "\n\e[1;45m Example => mirror-operator-catalog-v4.x.sh create-custom-catalog-certified-operators cass-operator,dataset-operator,h2o-operator \e[0m"
    echo " "
    exit 1
  else
    echo -e "\n\e[1;32m Pruning custom-certified-operators image \e[0m\n"
    opm index prune -f registry.redhat.io/redhat/certified-operator-index:v${OCP_VERSION} -p ${OPERATOR_NAMES} -t ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-certified-operators/certified-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Pushing custom-certified-operators image to local registry \e[0m\n"
    podman push ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-certified-operators/certified-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Creating custom-certified-operators catalog \e[0m\n"
    oc adm catalog mirror ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-certified-operators/certified-operator-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-certified-operators -a ${HOME}/pull-secret.json --insecure --index-filter-by-os='linux/amd64'
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;32m STATUS: Custom certified-operators SUCCESFUL CREATED \e[0m"
    else
      echo -e "\n\e[1;31m STATUS: FAILED => Custom certified-operators NOT CREATED \e[0m"
      exit 1
    fi
  fi
}

create-custom-redhat-marketplace () {
  check_login_redhat_io_registry
  if [[ -z "${OPERATOR_NAMES}" ]]
  then
    echo -e "\n\e[1;31m FAILED => Command expects custom images to be added to the custom Operator Catalog, please execute the command as follows: \e[0m"
    echo -e "\n\e[1;34m Command => mirror-operator-catalog-v4.x.sh create-custom-catalog-redhat-marketplace [OPERATOR_NAME_1, ...  ,OPERATOR_NAME_N] \e[0m"
    echo -e "\n\e[1;45m Example => mirror-operator-catalog-v4.x.sh create-custom-catalog-redhat-marketplace cloudhedge-rhmp,instana-agent-rhmp,orca-rhmp \e[0m"
    echo " "
    exit 1
  else
    echo -e "\n\e[1;32m Pruning custom-redhat-marketplace image \e[0m\n"
    opm index prune -f registry.redhat.io/redhat/redhat-marketplace-index:v${OCP_VERSION} -p ${OPERATOR_NAMES} -t ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-marketplace/redhat-marketplace-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Pushing custom-redhat-marketplace image to local registry \e[0m\n"
    podman push ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-marketplace/redhat-marketplace-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Creating custom-redhat-marketplace catalog \e[0m\n"
    oc adm catalog mirror ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-marketplace/redhat-marketplace-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-marketplace  -a ${HOME}/pull-secret.json--insecure --index-filter-by-os='linux/amd64'
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;32m STATUS: Custom redhat-marketplace SUCCESFUL CREATED \e[0m"
    else
      echo -e "\n\e[1;31m STATUS: FAILED => Custom redhat-marketplace NOT CREATED \e[0m"
      exit 1
    fi
  fi
}

create-custom-community-operators () {
  check_login_redhat_io_registry
  if [[ -z "${OPERATOR_NAMES}" ]]
  then
    echo -e "\n\e[1;31m FAILED => Command expects custom images to be added to the custom Operator Catalog, please execute the command as follows: \e[0m"
    echo -e "\n\e[1;34m Command => mirror-operator-catalog-v4.x.sh create-custom-catalog-community-operator [OPERATOR_NAME_1, ...  ,OPERATOR_NAME_N] \e[0m"
    echo -e "\n\e[1;45m Example => mirror-operator-catalog-v4.x.sh create-custom-catalog-community-operator cloudhedge-rhmp,instana-agent-rhmp,orca-rhmp \e[0m"
    echo " "
    exit 1
  else
    echo -e "\n\e[1;32m Pruning custom-community-operator image \e[0m\n"
    opm index prune -f registry.redhat.io/redhat/community-operator-index:v${OCP_VERSION} -p ${OPERATOR_NAMES} -t ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-community-operators/community-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Pushing custom-community-operator image to local registry \e[0m\n"
    podman push ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-community-operators/community-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Creating custom-community-operator catalog \e[0m\n"
    oc adm catalog mirror ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-community-operators/community-operator-index:v${OCP_VERSION} ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-community-operators  -a ${HOME}/pull-secret.json --insecure --index-filter-by-os='linux/amd64'
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;32m STATUS: Custom community-operators SUCCESFUL CREATED \e[0m"
    else
      echo -e "\n\e[1;31m STATUS: FAILED => Custom community-operators NOT CREATED \e[0m"
      exit 1
    fi
  fi
}

# LISTING OPERATOR PACKAGES

list_packages_organization_redhat-operator () {
  check_login_redhat_io_registry
  if podman ps | grep redhat-operator
  then
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - redhat-operator"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50051 api.Registry/ListPackages | jq -r .name) \e[0m"
  else
    podman run -p50051:50051 -dt --name redhat-operator  registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION}
    sleep 5
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - redhat-operator"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50051 api.Registry/ListPackages | jq -r .name) \e[0m"
  fi
}

list_packages_organization_certified-operators () {
  check_login_redhat_io_registry
  if podman ps | grep certified-operators
  then
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - certified-operators"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50052 api.Registry/ListPackages | jq -r .name) \e[0m"
  else
    podman run -p50052:50051 -dt --name certified-operators registry.redhat.io/redhat/certified-operator-index:v${OCP_VERSION}
    sleep 5
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - certified-operators"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50052 api.Registry/ListPackages | jq -r .name) \e[0m"
  fi
}

list_packages_organization_redhat-marketplace () {
  check_login_redhat_io_registry
  if podman ps | grep redhat-marketplace
  then
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - redhat-marketplace"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50053 api.Registry/ListPackages | jq -r .name) \e[0m"
  else
    podman run -p50053:50051 -dt --name redhat-marketplace registry.redhat.io/redhat/redhat-marketplace-index:v${OCP_VERSION}
    sleep 5
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - redhat-marketplace"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50053 api.Registry/ListPackages | jq -r .name) \e[0m"
  fi
}

list_packages_organization_community-operators () {
  check_login_redhat_io_registry
  if podman ps | grep community-operators
  then
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - community-operators"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50054 api.Registry/ListPackages | jq -r .name) \e[0m"
  else
    podman run -p50054:50051 -dt --name community-operators registry.redhat.io/redhat/community-operator-index:v${OCP_VERSION}
    sleep 5
    echo -e "\n\e[1;34m* Listing Operator Packages Organization:  \e[0m"
    echo -e "\n\e[1;35m   " - community-operators"  \e[0m"
    echo -e "\n\e[1;32m$(grpcurl -plaintext :50054 api.Registry/ListPackages | jq -r .name) \e[0m"
  fi
}

export-base-registry () {
    cd ${HOME}

    echo -e "\n\e[1;32m Starting mirroring base images for OCP v${OCP_RELEASE} \e[0m"
    echo -e "\n\e[1;32m This operation may take up to 20 min depending on the network speed \e[0m\n"
    mkdir -p ${HOME}/mirror-${OCP_RELEASE}
    oc adm release mirror -a ${HOME}/pull-secret.json --to-dir=${HOME}/mirror-base-${OCP_RELEASE} quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE}
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;34m* Base images for OCP v${OCP_RELEASE} susscesfully mirrored to directory: \e[0m"
      echo -e "\n  \e[1;45m$(ls -d ${HOME}/mirror-base-${OCP_RELEASE}) \e[0m\n"
    else
      echo -e "\n\e[1;31m* FAILED => Mirroring base images for OCP v${OCP_RELEASE} \e[0m"
      rm -rf mirror-base-${OCP_RELEASE}
      echo " "
      exit 1
    fi

    echo -e "\n\e[1;32m Starting compressing ${HOME}/mirror-base-${OCP_RELEASE} \e[0m\n"
    tar -zcvf mirror-base-${OCP_RELEASE}.tar.gz mirror-base-${OCP_RELEASE}
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;34m* Tar file containing base images for OCP v${OCP_RELEASE} \e[0m"
      echo -e "\n  \e[1;45m$(ls -sh ${HOME}/mirror-base-${OCP_RELEASE}.tar.gz) \e[0m\n"
      rm -rf mirror-base-${OCP_RELEASE}
    else
      echo -e "\n\e[1;31m* FAILED => export-base-registry \e[0m"
      rm -rf mirror-base-${OCP_RELEASE}
      echo " "
      exit 1
    fi
}

mirror-custom-catalog-redhat-operators () {
  if [[ -z "${OPERATOR_NAMES}" ]]
  then
    echo -e "\n\e[1;31m FAILED => Command expects custom images to be added to the custom Operator Catalog, please execute the command as follows: \e[0m"
    echo -e "\n\e[1;34m Command => ./mirror-registry-v47.sh export-custom-catalog-redhat-operators [OPERATOR_NAME_1, ...  ,OPERATOR_NAME_N] \e[0m"
    echo -e "\n\e[1;45m Example => ./mirror-registry-v47.sh export-custom-catalog-redhat-operators advanced-cluster-management,jaeger-product,quay-operator \e[0m"
    echo " "
    exit 1
  else
    echo -e "\n\e[1;32m Pruning custom-redhat-operators image \e[0m\n"
    opm index prune -f registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION} -p ${OPERATOR_NAMES} -t ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators/redhat-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Pushing custom-redhat-operators image to local registry \e[0m\n"
    podman push ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators/redhat-operator-index:v${OCP_VERSION}
    echo -e "\n\e[1;32m Mirroring custom-redhat-operators catalog to file mirror-redhat-operators-${OCP_RELEASE} \e[0m\n"
    cd ${HOME}
    oc adm catalog mirror -a ${HOME}/pull-secret.json ${REGISTRY_FQDN}:${REGISTRY_PORT}/olm-redhat-operators/redhat-operator-index:v${OCP_VERSION} file://mirror-redhat-operators-${OCP_RELEASE} --insecure
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;32m STATUS: Mirroring redhat-operator SUCCESFUL DONE => ls -d ${HOME}/v2/mirror-redhat-operators-${OCP_RELEASE} \e[0m"
    else
      echo -e "\n\e[1;31m STATUS: FAILED => Mirroring mirror-redhat-operators-${OCP_RELEASE} NOT DONE \e[0m"
      exit 1
    fi
    echo -e "\n\e[1;32m Compressing mirror-redhat-operators-${OCP_RELEASE} file \e[0m\n"
    tar czvf mirror-redhat-operators-${OCP_RELEASE}.tar.gz v2
    if [[ $? -eq 0 ]]
    then
      echo -e "\n\e[1;32m STATUS: mirror-redhat-operators-${OCP_RELEASE} SUCCESFUL compressed => ls -sh ${HOME}/mirror-redhat-operators-${OCP_RELEASE}.tar.gz \e[0m"
      rm -rf ${HOME}/mirror-redhat-operators-${OCP_RELEASE}
    else
      echo -e "\n\e[1;31m STATUS: FAILED => Compressing mirror-redhat-operators-${OCP_RELEASE} NOT DONE \e[0m"
      exit 1
    fi
  fi
}

# MENU OPTIONS

key="$1"

case $key in
    get-artifacts)
        get_artifacts
        ;;
    check-dependencies)
        check_deps
        ;;
    redhat-operators)
        redhat-operators
        ;;
    certified-operators)
        certified-operators
        ;;
    redhat-marketplace)
        redhat-marketplace
        ;;
    community-operators)
        community-operators
        ;;
    create-custom-catalog-redhat-operators)
        create-custom-redhat-operators
        ;;
    create-custom-catalog-certified-operators)
        create-custom-certified-operators
        ;;
    create-custom-catalog-redhat-marketplace)
        create-custom-redhat-marketplace
        ;;
    create-custom-catalog-community-operators)
        create-custom-community-operators
        ;;
    list-redhat-operators)
        list_packages_organization_redhat-operator
        ;;
    list-certified-operators)
        list_packages_organization_certified-operators
        ;;
    list-redhat-marketplace)
        list_packages_organization_redhat-marketplace
        ;;
    list-community-operators)
        list_packages_organization_community-operators
        ;;
    export-base-registry)
	       export-base-registry
	      ;;
    export-custom-catalog-redhat-operators)
        mirror-custom-catalog-redhat-operators
	      ;;
    *)
        usage
        ;;
esac
