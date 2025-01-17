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
        $DOCKER_IMAGE bash -c 'cd /io && ./run_manylinux_aarch64_build.sh'

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

    cd $REPO_ROOT
    pip install -r requirements/build.txt
    python setup.py bdist_wheel

    chmod -R o+rw _skbuild
    chmod -R o+rw dist

    /opt/python/cp37-cp37m/bin/python -m pip install auditwheel
    /opt/python/cp37-cp37m/bin/python -m auditwheel show dist/$NAME-$VERSION-$MB_PYTHON_TAG*.whl
    /opt/python/cp37-cp37m/bin/python -m auditwheel repair dist/$NAME-$VERSION-$MB_PYTHON_TAG*.whl
    chmod -R o+rw wheelhouse
    chmod -R o+rw $NAME.egg-info
    #Install Wheel
    echo "================================================ Install Wheel ===================================================="
    ls -al
    ls -al wheelhouse
    MB_PYTHON_TAG=$(python -c "import setup; print(setup.MB_PYTHON_TAG)") 
    VERSION=$(python -c "import setup; print(setup.VERSION)") 
    echo "MB_PYTHON_TAG = $MB_PYTHON_TAG"
    echo "VERSION = $VERSION"
    BDIST_WHEEL_PATH=$(ls wheelhouse/*-${VERSION}-${MB_PYTHON_TAG}-*2014_aarch64.whl)
    echo "BDIST_WHEEL_PATH = $BDIST_WHEEL_PATH"
    python -m pip install $BDIST_WHEEL_PATH[all]
    #Test Wheel
    echo "================================================ Test Wheel ===================================================="
    python run_tests.py
fi
