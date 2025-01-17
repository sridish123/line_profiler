#!/bin/bash
__heredoc__="""
notes:
    Manylinux repo: https://github.com/pypa/manylinux 
    Win + Osx repo: https://github.com/mavlink/MAVSDK-Python
"""


DOCKER_IMAGE=${DOCKER_IMAGE:="quay.io/pypa/manylinux2014_aarch64:latest"}
# Valid multibuild python versions are:
# cp27-cp27m  cp27-cp27mu  cp34-cp34m  cp35-cp35m  cp36-cp36m  cp37-cp37m, cp38-cp38m
MB_PYTHON_TAG=${MB_PYTHON_TAG:=$(python -c "import setup; print(setup.native_mb_python_tag())")}
NAME=${NAME:=$(python -c "import setup; print(setup.NAME)")}
VERSION=${VERSION:=$(python -c "import setup; print(setup.VERSION)")}
REPO_ROOT=${REPO_ROOT:=/io}
echo "
MB_PYTHON_TAG = $MB_PYTHON_TAG
DOCKER_IMAGE = $DOCKER_IMAGE
VERSION = $VERSION
NAME = $NAME
"

if [ "$_INSIDE_DOCKER" != "YES" ]; then

    set -e
    docker run --rm \
        -v $PWD:/io \
        -e _INSIDE_DOCKER="YES" \
        -e NAME="$NAME" \
        -e VERSION="$VERSION" \
        -e MB_PYTHON_TAG="$MB_PYTHON_TAG" \
        -e WHEEL_NAME_HACK="$WHEEL_NAME_HACK" \
        $DOCKER_IMAGE bash -c 'cd /io && ./run_manylinux_aarch64_build_publish.sh'

    __interactive__='''
    docker run --rm \
        -v $PWD:/io \
        -e _INSIDE_DOCKER="YES" \
        -e NAME="$NAME" \
        -e VERSION="$VERSION" \
        -e MB_PYTHON_TAG="$MB_PYTHON_TAG" \
        -e WHEEL_NAME_HACK="$WHEEL_NAME_HACK" \
        -it $DOCKER_IMAGE bash
    set +e
    set +x
    '''

    ls -al wheelhouse
    BDIST_WHEEL_PATH=$(ls wheelhouse/$NAME-$VERSION-$MB_PYTHON_TAG*.whl)
    echo "BDIST_WHEEL_PATH = $BDIST_WHEEL_PATH"
else
    set -x
    set -e

    VENV_DIR=/root/venv-$MB_PYTHON_TAG

    # Setup a virtual environment for the target python version
    /opt/python/$MB_PYTHON_TAG/bin/python -m pip install pip
    /opt/python/$MB_PYTHON_TAG/bin/python -m pip install setuptools pip virtualenv scikit-build cmake ninja ubelt wheel
    /opt/python/$MB_PYTHON_TAG/bin/python -m virtualenv $VENV_DIR

    source $VENV_DIR/bin/activate 
    echo "============================================ Sign and Publish ================================================"
    ls -al
    GPG_EXECUTABLE=gpg
    $GPG_EXECUTABLE --version
    openssl version
    $GPG_EXECUTABLE --list-keys
    export PYUTILS_CI_GITHUB_SECRET=${{ secrets.PYUTILS_CI_GITHUB_SECRET }}
    GLKWS=$PYUTILS_CI_GITHUB_SECRET openssl enc -aes-256-cbc -pbkdf2 -md SHA512 -pass env:GLKWS -d -a -in dev/cci_public_gpg_key.pgp.enc | $GPG_EXECUTABLE --import 
    GLKWS=$PYUTILS_CI_GITHUB_SECRET openssl enc -aes-256-cbc -pbkdf2 -md SHA512 -pass env:GLKWS -d -a -in dev/cci_gpg_owner_trust.enc | $GPG_EXECUTABLE --import-ownertrust
    GLKWS=$PYUTILS_CI_GITHUB_SECRET openssl enc -aes-256-cbc -pbkdf2 -md SHA512 -pass env:GLKWS -d -a -in dev/cci_secret_gpg_key.pgp.enc | $GPG_EXECUTABLE --import 
    $GPG_EXECUTABLE --list-keys  || echo "first one fails for some reason"
    $GPG_EXECUTABLE --list-keys  
    MB_PYTHON_TAG=$(python -c "import setup; print(setup.MB_PYTHON_TAG)")
    VERSION=$(python -c "import setup; print(setup.VERSION)") 
    pip install twine
    pip install six pyopenssl ndg-httpsclient pyasn1 -U --user
    pip install requests[security] twine --user
    GPG_KEYID=$(cat dev/public_gpg_key)
    echo "GPG_KEYID = '$GPG_KEYID'"
    export TWINE_REPOSITORY_URL=https://upload.pypi.org/legacy/
    export PYUTILS_TWINE_USERNAME=${{ secrets.PYUTILS_TWINE_USERNAME }}
    export PYUTILS_TWINE_PASSWORD=${{ secrets.PYUTILS_TWINE_PASSWORD }}
    MB_PYTHON_TAG=$MB_PYTHON_TAG \
        DO_GPG=True GPG_KEYID=$GPG_KEYID \
        TWINE_PASSWORD=$PYUTILS_TWINE_PASSWORD \
        TWINE_USERNAME=$PYUTILS_TWINE_USERNAME \
        GPG_EXECUTABLE=$GPG_EXECUTABLE \
        DO_UPLOAD=True \
        DO_TAG=False ./publish.sh 
fi
