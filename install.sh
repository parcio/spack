#!/bin/sh

set -e

SPACK_MIRROR="${HOME}/spack-mirror"
#SPACK_MIRROR=''

spack_mirror ()
{
	test -n "${SPACK_MIRROR}" || return 0
	test -d "${SPACK_MIRROR}" || mkdir "${SPACK_MIRROR}"

	./bin/spack mirror add local "file://${SPACK_MIRROR}"
}

spack_install ()
{
	if test -n "${SPACK_MIRROR}"
	then
		echo "Mirroring $@"
		./bin/spack mirror create --directory "${SPACK_MIRROR}" --dependencies "$@"
	fi

	echo "Installing $@"
	./bin/spack install "$@"
}

spack_install_compiler ()
{
	local location

	spack_install "$@"

	location="$(./bin/spack location --install-dir "$@")"
	./bin/spack compiler find "${location}"
}

. /etc/profile.d/modules.sh

module purge

rm --force --recursive "${HOME}/.spack"

cp config/config.yaml spack/etc/spack
cp config/modules.yaml spack/etc/spack
cp config/packages.yaml spack/etc/spack

cd spack

# FIXME Find a better way to do this
patch --strip=1 --forward --reject-file=- < ../patches/env.patch || true

spack_mirror

# Keep in sync with packages.yaml and modules.yaml
spack_install_compiler gcc@11.2.0 %gcc@8.4.1

# MPI
spack_install mpich

# I/O
#spack_install adios
spack_install adios2
spack_install fio
spack_install hdf5
spack_install netcdf-c

# Tracing
spack_install cube
spack_install likwid
spack_install scalasca
spack_install scorep
#spack_install vampirtrace

# Compression
spack_install c-blosc
spack_install lz4
spack_install lzma
spack_install lzo
spack_install snappy
spack_install zfp
spack_install zstd

# Math
spack_install gsl
#spack_install netlib-scalapack

# Development
spack_install autoconf
spack_install automake
spack_install bison
spack_install boost
spack_install cmake
spack_install doxygen
spack_install flex
spack_install git
spack_install hwloc
spack_install json-c
spack_install libtool
spack_install m4
spack_install meson
spack_install ninja
spack_install numactl
spack_install pkgconf

# Languages
spack_install go
spack_install llvm

# Visualization
spack_install gnuplot
spack_install graphviz

# Python
spack_install python
spack_install py-flake8
spack_install py-matplotlib
spack_install py-numpy
spack_install py-pandas
spack_install py-pip
spack_install py-scikit-learn
spack_install py-sphinx
spack_install py-virtualenv

# Remove all unneeded packages
./bin/spack gc --yes-to-all
# Precreate the variables for our hack in setup-env.sh
./bin/spack --print-shell-vars sh > share/spack/setup-env.vars
# This is required for chaining to work
./bin/spack module tcl refresh --delete-tree --yes-to-all
