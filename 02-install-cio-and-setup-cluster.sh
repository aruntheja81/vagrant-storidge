#!/usr/bin/env bash

INSTALL_CIO="curl -fsSL ftp://download.storidge.com/pub/ce/cio-ce | sudo bash;"
STORIDGE_CLUSTER_NODES=3

if [ ! -z "${VAGRANT_STORIDGE_CLUSTER_NODES}" ]
then
    STORIDGE_CLUSTER_NODES=${VAGRANT_STORIDGE_CLUSTER_NODES}
fi

if [ ! -d "logs" ]
then
    mkdir logs
fi

# Install CIO on all machines
function install_cio() {
    echo " ===== STARTING CIO INSTALL FOR ${STORIDGE_CLUSTER_NODES} MACHINES ====="

    for (( i=1; i<=$STORIDGE_CLUSTER_NODES; i++ ))
    do
        echo " === Starting install for machine storidge-$i ==="
        echo " = Install logs are in logs/install_cio.storidge-$i.log ="
        (vagrant ssh storidge-$i --no-tty -c "${INSTALL_CIO}" 2>&1 | tee logs/install_cio.storidge-$i.log) &
    done
    wait

    echo " ===== CIO SUCCESSFULLY INSTALLED ====="
}

# Copy keys across all machines
function copy_keys() {
    echo " ===== COPYING SSH KEYS ====="

    for (( i=1; i<=$STORIDGE_CLUSTER_NODES; i++ ))
    do
        for (( j=1; j<=$STORIDGE_CLUSTER_NODES; j++ ))
        do
            if [ $j != $i ]
            then
                (vagrant upload storidge-$j/id_rsa.pub /tmp/id_rsa.pub.$j storidge-$i) &
            fi
        done
    done
    wait

    echo " ===== SSH KEYS COPIED ====="
}

# Add keys to authorized keys
function authorize_keys() {
    echo " ===== ADDING SSH KEYS TO AUTHORIZED KEYS ====="

    for (( i=1; i<=$STORIDGE_CLUSTER_NODES; i++ ))
    do
        for (( j=1; j<=$STORIDGE_CLUSTER_NODES; j++ ))
        do
            if [ $j != $i ]
            then
                (vagrant ssh storidge-$i --no-tty -c "cat /tmp/id_rsa.pub.$j | sudo tee -a /root/.ssh/authorized_keys") &
            fi
        done
    done
    wait

    echo " ===== SSH KEYS ADDED TO AUTHORIZED KEYS ====="
}

# Setup cio cluster
function setup_cluster() {
    echo " ===== STARTING CLUSTER SETUP FOR ${STORIDGE_CLUSTER_NODES} NODES ====="

    vagrant ssh storidge-1 --no-tty -c "sudo sed -i 's/ExecStart=\/usr\/bin\/dockerd -H fd:\/\//ExecStart=\/usr\/bin\/dockerd -H fd:\/\/ -H tcp:\/\/10.0.9.10:2375/g' /lib/systemd/system/docker.service"
    vagrant ssh storidge-1 --no-tty -c "sudo systemctl daemon-reload && sudo systemctl restart docker"

    CLUSTER_CREATE_OUTPUT=$(vagrant ssh storidge-1 --no-tty -c "sudo cioctl create --ip 10.0.9.10")
    JOIN_COMMAND=$(echo "${CLUSTER_CREATE_OUTPUT}" | grep 'cioctl join' | xargs)
    INIT_COMMAND=$(echo "${CLUSTER_CREATE_OUTPUT}" | grep 'cioctl init' | xargs)

    for (( i=2; i<=$STORIDGE_CLUSTER_NODES; i++ ))
    do
        ADDR=$(( $i + 9 ))
        (vagrant ssh storidge-$i --no-tty -c "sudo ${JOIN_COMMAND} --ip 10.0.9.${ADDR}")
    done

    vagrant ssh storidge-1 --no-tty -c "sudo ${INIT_COMMAND}"

    echo " ===== CLUSTER SETUP FINISHED ====="
}

case "$1" in
    1)
        install_cio
        ;;
    2)
        copy_keys
        authorize_keys
        ;;
    3)
        setup_cluster
        ;;
    all)
        install_cio
        copy_keys
        authorize_keys
        setup_cluster
        ;;
    *)
        echo "Usage: ./02-install-cio-and-setup-cluster.sh { 1 | 2 | 3 | all }"
        echo "  where: 1 - cio install"
        echo "         2 - ssh keys copies across cluster"
        echo "         3 - cluster setup"
        echo "         all - run all steps"
        ;;
esac
exit 0
