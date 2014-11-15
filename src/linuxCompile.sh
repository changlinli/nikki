#!/bin/bash

set -o errexit

# building c++-part (qt-bindings)
cd cpp
mkdir -p dist
cd dist
cmake ..
make
cd ../..

cabal sandbox init
cabal install --only-dependencies $@ || true
cabal install --only-dependencies -j1 $@
cabal configure $@
cabal build
